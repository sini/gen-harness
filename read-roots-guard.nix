# `readRootsGuard` — the shared read-roots check, shipped to every `mkCi` consumer from one
# definition and published here for the non-mkCi consumer (the gen hub), following the
# `relock` / `processPlane` pattern: `flakeModule.nix` imports this file for its own `perSystem`
# binding, and `flake.nix` publishes the same file, so an mkCi consumer's guard and the hub's are
# the SAME value in any evaluation that reaches both — the module cannot drift from the published
# surface by construction rather than by discipline.
#
# WHY THE PUBLISHED SURFACE TAKES PATHS AND NOT `readRootsRel` STRINGS. This is a construction,
# not a repair. `readroots.nix` is where a misspelt or vacuous root throws. A surface that took
# strings would let a direct consumer hand in a pathspec that names nothing. The guard would then
# be silently off for that root, which is the exact state `readroots.nix`'s `deepSeq` exists to
# prevent. Taking paths makes that state impossible to form.
{
  pkgs,
  name,
  sourceRoot,
  roots,
}:
let
  # The EVAL half, derived HERE from the caller's paths — a root the guard does not cover is
  # then a root the suite cannot read. See `readroots.nix` for why it throws rather than returns
  # on a misspelt or vacuous root.
  readRootsRel = import ./readroots.nix {
    inherit (pkgs) lib;
    inherit sourceRoot;
  } roots;
in
# ★ THE READ-ROOTS GUARD. A suite's evaluator reads a GIT-FILTERED copy of this
# repository, so a file git does not know about — untracked, or gitignored — is simply
# absent from the source the cells are collected from and evaluated against. The suite
# then reports a number that agrees with itself while being short: an author who writes
# the cell proving their new guard fires, and forgets to `git add` it, reads a green that
# was computed over a tree without it. The run must yield NO VERDICT in that state, which
# is why this refuses rather than warns.
#
# It is ONE BINARY rather than a copy per caller because every wired invocation point needs
# it, and two statements of one check drift — the guard would then fall behind the thing it
# guards, which is the same argument `mdformat-plugins-check.nix` takes its `expected` from
# the installed value for.
pkgs.writeShellApplication {
  name = "${name}-ci-read-roots";
  # DECLARED, not ambient. `writeShellApplication` PREPENDS runtimeInputs to an inherited
  # PATH, so an undeclared `git` resolves to whatever the caller happens to carry and the
  # check stops being hermetic. `coreutils` is `realpath`, the symlink containment test.
  runtimeInputs = [
    pkgs.git
    pkgs.coreutils
  ];
  text = ''
    # The worktree, NAMED rather than assumed: the three call sites the harness wires run
    # from different working directories, and a linked worktree must resolve to ITSELF
    # rather than climb into the main checkout. Same reason treefmt's tree root is a
    # stated command below.
    if ! wt=$(git rev-parse --show-toplevel 2>&1); then
      printf 'CONTROL FAILED: the read-roots guard is not inside a git worktree: %s\n' "$wt"
      exit 2
    fi
    roots=(${pkgs.lib.escapeShellArgs readRootsRel})

    err=$(mktemp)
    trap 'rm -f "$err"' EXIT

    # ★★★ THE DISCRIMINATOR IS THE OUTPUT BEING EMPTY, AND `rc` IS A SEPARATE, THIRD
    # OUTCOME. Measured: `git ls-files` exits 0 in every worktree state this guard cares
    # about, refuse and pass alike, so `if ! git ls-files …` is a silent no-op that passes
    # everything. A non-zero rc means the instrument did not RUN — a misderived root that
    # leaked a store path reads rc=128 — and that is an abort, not a verdict about the tree.
    #
    # `--others` is the whole predicate over the CONTENT modes: exactly the files the index
    # does not know. `--exclude-standard` is deliberately NOT passed — omitting it is what
    # keeps the GITIGNORED half in domain, and it is the half that cannot be repaired by
    # staging. It cannot name a tracked-modified, tracked-deleted or staged file, and it
    # must not: those are fully visible to the evaluator with their worktree bytes, and
    # refusing them would reject every commit that touches a test cell.
    rc=0
    out=$(git -C "$wt" ls-files --others -- "''${roots[@]}" 2>"$err") || rc=$?
    if [ "$rc" -ne 0 ]; then
      printf 'CONTROL FAILED: the read-roots guard did not run (rc=%s): %s\n' "$rc" "$(cat "$err")"
      exit 2
    fi

    # ---- the REFERENCE-MODE half: one rule over a closed enumeration, not a list of cases.
    #
    # The two consumers of a declared root interpret it by different functions. The GUARD
    # hands it to git as a PATHSPEC, which matches index and worktree entries by NAME and
    # traverses nothing. The EVALUATOR hands it to Nix as a PATH, which resolves against the
    # materialised source: symlinks are followed, and objects with no NAR representation are
    # simply absent. They coincide over the modes whose object IS the bytes at that path.
    #
    # Git's index admits exactly four modes, and they split on that question:
    #   100644 / 100755  CONTENT   — the two extents are the same bytes; `--others` above
    #                                is the whole predicate.
    #   120000 SYMLINK   a reference to ANOTHER PATH. Git will not follow it; Nix will.
    #   160000 GITLINK   a reference to a COMMIT. It has no NAR representation, so the
    #                    source carries NONE of its bytes.
    # ⇒ REFUSE at the two REFERENCE modes unless the reference resolves INSIDE the declared
    # root set. For a gitlink that condition is unsatisfiable — a commit is never a path —
    # so its refusal is unconditional and falls out of the same rule. Because the mode
    # enumeration is CLOSED, the rule is total: a third reference mode cannot arrive
    # without git growing one.
    #
    # It is a REFUSAL in its own right and not a filter over the first command's output, so
    # the bad state cannot form. `--stage` names the ROOT ITSELF when the root is the
    # symlink, which is why the at-root and under-root cases are one loop.
    rc=0
    stage=$(git -C "$wt" ls-files --stage -- "''${roots[@]}" 2>"$err") || rc=$?
    if [ "$rc" -ne 0 ]; then
      printf 'CONTROL FAILED: the reference-mode half did not run (rc=%s): %s\n' "$rc" "$(cat "$err")"
      exit 2
    fi

    gitlinks=()
    escapes=()
    # `--stage` prints `<mode> <sha> <stage>\t<path>`, so a TAB split puts the path in
    # field 2 and a path containing spaces survives intact.
    while IFS=$'\t' read -r meta p; do
      [ -n "$p" ] || continue
      case "$meta" in
      "160000 "*)
        gitlinks+=("$p")
        continue
        ;;
      "120000 "*) ;;
      *) continue ;;
      esac
      # `-m` because a link may dangle. The worktree resolution is the right one to read:
      # the source copy materialises the same link text, so relative resolution is
      # identical, and where the two could differ — a target absent from the source — the
      # divergence is toward REFUSING.
      if ! tgt=$(realpath -m --relative-to="$wt" "$wt/$p" 2>"$err"); then
        printf 'CONTROL FAILED: could not resolve the symlink %s: %s\n' "$p" "$(cat "$err")"
        exit 2
      fi
      inside=no
      for r in "''${roots[@]}"; do
        case "$tgt" in "$r" | "$r"/*)
          inside=yes
          break
          ;;
        esac
      done
      [ "$inside" = yes ] || escapes+=("$p -> $tgt")
    done <<<"$stage"

    st=0
    if [ -n "$out" ]; then
      echo "REFUSE: git-unknown bytes under a declared read root — the evaluator cannot see them, so the suite would report a verdict it did not compute:"
      echo "$out"
      echo "remedy: \`git add\` it, or move it outside the declared read roots."
      st=1
    fi
    if [ ''${#gitlinks[@]} -gt 0 ]; then
      echo "REFUSE: a tracked SUBMODULE (gitlink) at or under a declared read root — the evaluated source carries none of its bytes:"
      printf '%s\n' "''${gitlinks[@]}"
      st=1
    fi
    if [ ''${#escapes[@]} -gt 0 ]; then
      echo "REFUSE: a tracked SYMLINK at or under a declared read root resolves outside the declared set — git matches the NAME, the evaluator resolves the LINK:"
      printf '%s\n' "''${escapes[@]}"
      st=1
    fi
    exit "$st"
  '';
}
