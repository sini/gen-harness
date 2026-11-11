# `stagedCommitHook` — the commit hook every `mkCi` consumer and the hub install, from one
# definition (den-hoag-commit-hook-stash-shared-checkout-ddjy2). `flakeModule.nix` imports this
# file for its devshell, and `flake.nix` publishes the same file, the `readRootsGuard` pattern: the
# hub's hook and a consumer's are the same construction by import, not by discipline.
#
# ★ WHY THE HOOK IS NOT pre-commit's OWN SHIM. For a normal commit `pre-commit run` stashes: it
# writes every unstaged tracked change to a patch, runs `git checkout -- .` over the WHOLE
# checkout, runs the hooks and re-applies. In a checkout several writers share, every other
# writer's unstaged edit is absent from disk for the length of the hooks, and a write that lands
# inside that window is lost on the rollback path. The stash is pre-commit's own
# (`stash = not args.all_files and not args.files`), with no setting above it, and `--files` stops
# it only by judging the working tree instead of the commit. So this is a construction: the hooks
# run in an EXPORT of the tree the commit records, and the shared checkout is only read.
#
# `{ pkgs, package, configFile, chained ? [ ], wholeTree ? null, postCommit ? [ ], prePush ? [ ] }`
#   -> `{ hook; install; postCommitHook; prePushHook; }`:
#   hook     the hook script, a store derivation. It names `package` and `configFile` by store
#            path, so its closure holds both and one GC root on it keeps the hook runnable.
#   install  the slot writer, run at devshell entry (stderr only).
#   chained  worktree-relative executables run BEFORE the export, in the real checkout with
#            git's hook environment intact (so `GIT_INDEX_FILE` still names the recorded tree), and
#            a non-zero exit refuses the commit. The declared home of a command a consumer used to
#            prepend to the slot by hand, which the writer below would otherwise erase. Each must
#            only read the checkout. In all three slots a declared command the committing revision
#            does not carry is skipped and named, and one it carries that the disk lacks refuses
#            (`presentFn` below).
#   wholeTree  the `files` regexes of the hooks that read the WHOLE tree rather than the files they
#            are handed (`pass_filenames = false`, or `always_run`, which is `""`). A commit whose
#            staged paths match none of them exports only the staged files. `null` (the default)
#            exports the whole tree on every commit, as before.
#   postCommit  worktree-relative executables run, in order, after every commit, in the real checkout.
#            Each runs even when an earlier one failed; git ignores a post-commit hook's status, so a
#            failure is reported on stderr and nothing more. The declared home of a hook that
#            records what a commit left behind.
#   prePush  worktree-relative executables run before every push, in the real checkout, each with
#            git's arguments (remote name, URL) and the same ref lines on stdin. The first non-zero
#            exit refuses the push.
#   postCommitHook, prePushHook  the slot scripts, `null` when nothing is declared for the slot.
#
# The two further slots are written, compared and removed by the same writer: a declared slot is
# written whole at devshell entry; a slot this writer wrote that is no longer declared is removed;
# a slot it did not write is left in place and named.
#
# ★ WHY THE EXPORT IS SPARSE WHEN IT CAN BE. A full export writes every tracked file. Measured on
# den-ag-design (721,158 files, 4.2 GB): about 29 s per commit for `checkout-index -a`, against 2.8 s
# sparse, for a commit touching one file. A files-scoped hook is handed only staged paths, so only
# those need to exist. The rest are marked `skip-worktree`, which keeps them out of
# `git diff` / `status`: pre-commit still finds nothing unstaged to stash. A hook that reads beyond
# the paths it is handed must declare `pass_filenames = false` or `always_run`, which puts it in
# `wholeTree`.
{
  pkgs,
  package,
  configFile,
  chained ? [ ],
  wholeTree ? null,
  postCommit ? [ ],
  prePush ? [ ],
}:
let
  marker = "# gen-harness: staged-tree commit hook";
  inherit (pkgs.lib)
    escapeShellArg
    concatMapStrings
    optionalString
    getExe
    makeBinPath
    ;
  git = getExe pkgs.git;
  slotMarker = slot: "# gen-harness: ${slot} hook";
  # ★ THE SLOTS ARE SHARED, THE DECLARATIONS ARE PER REVISION. Every linked worktree runs the one
  # common-dir slot, written by whichever worktree last entered its devshell, so a declared command
  # can be one the committing revision never carried: running it there refused every commit on every
  # other branch (den-ag-design, 2026-11-11, two minutes). Presence is judged by the REVISION, never
  # by the disk, so a gate cannot fail open by going missing:
  #   on disk                                    run it; its exit is the verdict
  #   in the recorded tree or HEAD, not on disk  refuse: a tracked gate is missing, or this commit
  #                                              deletes it (deleting a gate is a deliberate act)
  #   in neither                                 skip, named: this revision does not carry it
  presentFn = ''
    gen_harness_present() {
      if [ -e "$top/$1" ]; then return 0; fi
      if git -C "$top" ls-files --error-unmatch -- "$1" >/dev/null 2>&1 \
        || git -C "$top" cat-file -e "HEAD:$1" 2>/dev/null; then
        echo "gen-harness: refused: $1 is declared and tracked in this revision but missing from the worktree, or this commit deletes it. Restore it (git checkout HEAD -- $1), or delete it past the gate deliberately." >&2
        return 2
      fi
      echo "gen-harness: skipped $1: this revision does not carry it." >&2
      return 1
    }
  '';
  # One declared command: run it when the revision carries it, else skip or refuse (`presentFn`).
  # `onRefuse` is what a refusal does in the slot; `run` is the invocation.
  runDeclared =
    { onRefuse, run }:
    c: ''
      p=0; gen_harness_present ${escapeShellArg c} || p=$?
      case $p in
        0) ${run c} ;;
        1) ;;
        *) ${onRefuse} ;;
      esac
    '';

  postCommitHook =
    if postCommit == [ ] then
      null
    else
      pkgs.writeShellScript "gen-harness-post-commit-hook" ''
        ${slotMarker "post-commit"} — runs the declared post-commit commands in the real checkout.
        set -uo pipefail
        top=$(git rev-parse --show-toplevel)
        ${presentFn}
        rc=0
        ${concatMapStrings (runDeclared {
          onRefuse = "rc=1";
          run =
            c:
            ''"$top"/${escapeShellArg c} || { rc=$?; echo "gen-harness: post-commit command ${escapeShellArg c} failed (exit $rc)" >&2; }'';
        }) postCommit}
        exit "$rc"
      '';

  prePushHook =
    if prePush == [ ] then
      null
    else
      pkgs.writeShellScript "gen-harness-pre-push-hook" ''
        ${slotMarker "pre-push"} — runs the declared pre-push commands in the real checkout.
        set -euo pipefail
        top=$(git rev-parse --show-toplevel)
        # git hands the ref lines once, on stdin; every command reads the same lines.
        refs=$(mktemp "''${TMPDIR:-/tmp}/gen-harness-pre-push.XXXXXX")
        trap 'rm -f "$refs"' EXIT
        cat > "$refs"
        ${presentFn}
        ${concatMapStrings (runDeclared {
          onRefuse = "exit 1";
          run = c: ''"$top"/${escapeShellArg c} "$@" < "$refs"'';
        }) prePush}
      '';

  hook = pkgs.writeShellScript "gen-harness-staged-commit-hook" ''
    ${marker} — runs the pre-commit hooks against the STAGED tree, exported to a throwaway
    # repository; never stashes, checks out or rewrites the working tree.
    set -euo pipefail
    top=$(git rev-parse --show-toplevel)
    ${optionalString (chained != [ ]) presentFn}
    ${concatMapStrings (runDeclared {
      onRefuse = "exit 1";
      run = c: ''"$top"/${escapeShellArg c}'';
    }) chained}
    # The tree `git commit` is about to record. `write-tree` honours GIT_INDEX_FILE, which git
    # points at a temporary index for `git commit -- <paths>` and `git commit -a`.
    tree=$(git write-tree)
    head=$(git rev-parse -q --verify HEAD || true)
    objects=$(git rev-parse --path-format=absolute --git-common-dir)/objects
    export_dir=$(mktemp -d "''${TMPDIR:-/tmp}/gen-harness-staged.XXXXXX")
    trap 'rm -rf "$export_dir"' EXIT
    trap 'exit 1' HUP INT TERM
    # Everything below addresses the export; nothing inherited from the hook environment may point
    # back at the checkout.
    unset GIT_INDEX_FILE GIT_DIR GIT_WORK_TREE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
    cd "$export_dir"
    git init -q
    printf '%s\n' "$objects" > .git/objects/info/alternates
    if [ -n "$head" ]; then git update-ref HEAD "$head"; fi
    git read-tree "$tree"
    ${
      if wholeTree == null then
        ''
          git checkout-index -a
        ''
      else
        ''
          # Staged paths that exist in the recorded tree: deletions have no index entry to check out.
          staged=$(mktemp "''${TMPDIR:-/tmp}/gen-harness-staged-paths.XXXXXX")
          trap 'rm -rf "$export_dir" "$staged"' EXIT
          full=0
          if [ -z "$head" ]; then
            full=1
          else
            git diff --cached --name-only -z --no-renames --diff-filter=d HEAD > "$staged"
            # Any staged path a whole-tree hook would fire on needs the whole tree. An empty pattern
            # (`always_run`, or a hook with no `files`) matches every commit. A pattern grep cannot
            # compile errs toward the full export.
            for pattern in ${concatMapStrings (p: escapeShellArg p + " ") wholeTree}; do
              if [ -z "$pattern" ]; then full=1; break; fi
              rc=0
              tr '\0' '\n' < "$staged" | ${pkgs.gnugrep}/bin/grep -qE -- "$pattern" || rc=$?
              if [ "$rc" -ne 1 ]; then full=1; break; fi
            done
          fi
          if [ "$full" -eq 1 ]; then
            git checkout-index -a
          else
            git ls-files -z | git update-index -z --skip-worktree --stdin
            if [ -s "$staged" ]; then
              git update-index -z --no-skip-worktree --stdin < "$staged"
              git checkout-index -z --stdin < "$staged"
            fi
          fi
        ''
    }
    # In the export the working tree IS the index, so pre-commit's stash finds nothing to stash and
    # its file list is `diff --staged` against HEAD: exactly the commit's content. A fixer's rewrite
    # lands in the export and is discarded, so it refuses ("files were modified by this hook") and
    # the author formats their own tree.
    # NOT `exec`: exec replaces this shell, the EXIT trap never fires, and every commit leaks a
    # full copy of the tree into TMPDIR.
    ${getExe package} run --config ${configFile} --hook-stage pre-commit
  '';

  install = pkgs.writeShellScript "gen-harness-install-commit-hook" ''
    set -euo pipefail
    export PATH=${
      makeBinPath [
        pkgs.coreutils
        pkgs.diffutils
        pkgs.gnugrep
      ]
    }:$PATH
    # GUARDED against running with no repository underfoot (a tarball checkout, a sandboxed build):
    # unguarded, `rev-parse` fails and the devshell entrypoint's `set -euo pipefail` aborts entry.
    common_dir=$(${git} rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || exit 0
    hooks=$common_dir/hooks
    slot=$hooks/pre-commit
    mkdir -p "$hooks"

    # The hook's closure, `package` and `configFile` with it, stays alive while the checkout does.
    nix-store --add-root "$common_dir/gen-harness-pre-commit" --indirect --realise ${hook} >/dev/null

    # Written at the COMMON dir because worktrees share hooks: one slot serves every linked
    # worktree, which needs nothing materialised because the hook names its config by store path.
    # Via mktemp + `mv -f`, comparing first: a same-directory rename never truncates a file a
    # running interpreter is reading.
    if ! cmp -s ${hook} "$slot"; then
      if [ -e "$slot" ] && ! grep -qF ${escapeShellArg marker} "$slot" \
        && ! grep -qF '# File generated by pre-commit: https://pre-commit.com' "$slot"; then
        echo "gen-harness: NOT installing the commit hook: $slot is neither pre-commit's shim nor this hook, so it is left in place. Move it aside and re-enter the devshell; a command it ran belongs in gen.ci.commitHook.chained."
      else
        tmp=$(mktemp "$hooks/.pre-commit.XXXXXX")
        cat ${hook} > "$tmp"
        chmod +x "$tmp"
        mv -f "$tmp" "$slot"
        echo "gen-harness: installed the staged-tree commit hook at $slot"
      fi
    fi
    if [ -e "$hooks/pre-commit.legacy" ]; then
      echo "gen-harness: $hooks/pre-commit.legacy no longer runs: pre-commit's shim chained it, this hook does not. Declare it in gen.ci.commitHook.chained."
    fi

    ${concatMapStrings
      ({ slot, script }: ''
        slot=$hooks/${slot}
        ${
          if script == null then
            ''
              if [ -f "$slot" ] && grep -qF ${escapeShellArg (slotMarker slot)} "$slot"; then
                rm -f "$slot"
                echo "gen-harness: removed the ${slot} hook at $slot: nothing is declared for it any more."
              fi
            ''
          else
            ''
              nix-store --add-root "$common_dir/gen-harness-${slot}" --indirect --realise ${script} >/dev/null
              if ! cmp -s ${script} "$slot"; then
                if [ -e "$slot" ] && ! grep -qF ${escapeShellArg (slotMarker slot)} "$slot"; then
                  echo "gen-harness: NOT installing the ${slot} hook: $slot was not written by gen-harness, so it is left in place. Move it aside and re-enter the devshell; a command it ran belongs in its gen.ci.commitHook option."
                else
                  tmp=$(mktemp "$hooks/.${slot}.XXXXXX")
                  cat ${script} > "$tmp"
                  chmod +x "$tmp"
                  mv -f "$tmp" "$slot"
                  echo "gen-harness: installed the ${slot} hook at $slot"
                fi
              fi
            ''
        }
      '')
      [
        {
          slot = "post-commit";
          script = postCommitHook;
        }
        {
          slot = "pre-push";
          script = prePushHook;
        }
      ]
    }

    # git-hooks.nix's installer wrote `core.hooksPath` RELATIVE to the top-level, and in a linked
    # worktree, whose `.git` is a pointer file, that names nothing: git runs no hook and the commit
    # lands ungated. git's default already resolves to the common dir, so it is removed, not fixed.
    # Checkouts carry the old value until they re-enter. `--unset-all` tells REMOVED (0) from
    # ABSENT (5), and the `if` reads that rather than discarding it.
    if ${git} config --local --unset-all core.hooksPath; then
      echo "gen-harness: removed core.hooksPath - git's default already resolves hooks to the common dir, and the relative value the old installer wrote is unreachable from a linked worktree."
    fi

    # The RETIRED provisioner, by the marker it carries. It materialised a linked worktree's
    # `.pre-commit-config.yaml`, which nothing writes any more, so left in place it would run
    # `nix develop` on every checkout in every new linked worktree, permanently.
    if [ -f "$hooks/post-checkout" ] && grep -qF '# gen-harness: materialises' "$hooks/post-checkout"; then
      rm -f "$hooks/post-checkout"
      echo "gen-harness: removed the retired post-checkout provisioner at $hooks/post-checkout"
    fi
  '';
in
{
  inherit
    hook
    install
    postCommitHook
    prePushHook
    ;
}
