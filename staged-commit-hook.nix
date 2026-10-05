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
# `{ pkgs, package, configFile, chained ? [ ] }` -> `{ hook; install; }`:
#   hook     the hook script, a store derivation. It names `package` and `configFile` by store
#            path, so its closure holds both and one GC root on it keeps the hook runnable.
#   install  the slot writer, run at devshell entry (stderr only).
#   chained  worktree-relative executables run BEFORE the export, in the real checkout with
#            git's hook environment intact (so `GIT_INDEX_FILE` still names the recorded tree), and
#            a non-zero exit refuses the commit. The declared home of a command a consumer used to
#            prepend to the slot by hand, which the writer below would otherwise erase. Each must
#            only read the checkout.
{
  pkgs,
  package,
  configFile,
  chained ? [ ],
}:
let
  marker = "# gen-harness: staged-tree commit hook";
  inherit (pkgs.lib)
    escapeShellArg
    concatMapStrings
    getExe
    makeBinPath
    ;
  git = getExe pkgs.git;

  hook = pkgs.writeShellScript "gen-harness-staged-commit-hook" ''
    ${marker} — runs the pre-commit hooks against the STAGED tree, exported to a throwaway
    # repository; never stashes, checks out or rewrites the working tree.
    set -euo pipefail
    top=$(git rev-parse --show-toplevel)
    ${concatMapStrings (c: ''
      "$top"/${escapeShellArg c}
    '') chained}
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
    git checkout-index -a
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
  inherit hook install;
}
