# `relock` — the shared lock-bump command, shipped to every `mkCi` consumer from one definition.
#
# THE PROBLEM IT ENCODES AWAY. Bumping a member's locks is a TWO-ACT task — root first, then `./ci`
# through the node that carries the input there — and every way of getting it wrong is a CLEAN EXIT:
#
#   1. `nix flake update <x> --flake <dir>` EXITS 0 WHEN `<x>` IS NOT A DIRECT INPUT of that flake,
#      warning on stderr and writing nothing. Measured again on 2026-09-18 at this repository:
#      `nix flake update not-a-real-input --flake .` => rc 0, lock byte-unchanged. The command that
#      exists to remove that failure mode may not inherit it, so `<input>` is resolved against the
#      declared set BEFORE anything is written.
#   2. The second act is not obvious and was got wrong in production: gen `87a74a3` relocked the
#      root alone, `ci/flake.lock` lagged, `lock-agreement` read `agree=False` and exited 0 anyway,
#      and that lag SUPPRESSED a genuine `architecture-library-graph` red until the catch-up landed.
#   3. An input PINNED TO A REV in `flake.nix` moves nothing on an update, legitimately. Silence is
#      then indistinguishable from success, so this reports the node delta on every run, always.
#
# ★ IT NEVER ATTEMPTS root ≡ ci. The two locks diverge BY DESIGN — `ci/` carries `gen-harness`,
# `nixpkgs` and test-only dependencies the root never sees — and convergence between them is not a
# goal. Each side is bumped on its own terms; the only cross-lock assertion is the self-input
# invariant below.
#
# ★★ AND THE LOCKS DECIDE MORE THAN THE LOCKS. A member's FORMATTER and its PRE-COMMIT HOOK are
# both pinned by `ci/flake.lock` and neither follows a bump on its own, so a relock that stops at
# the lock leaves the member unable to pass its OWN CI and running a hook that silently reverts
# what that CI now requires. Both are caught up at the foot of this script, gated on a node having
# actually moved; the comment there carries the seven measurements.
#
# EXIT VOCABULARY: 0 done · 1 REFUSED, nothing written · 2 a control failed or the invocation was
# malformed · 3 THE LOCKS ARE WRITTEN AND THE TOOLING DID NOT FOLLOW — a state the other three
# cannot express, and the one a caller must not read as either success or as "nothing happened".
#
# ★ IT VERIFIES ITS OWN OUTPUT AND REFUSES TO LEAVE A VIOLATING STATE. A relock is exactly the act
# that can pull a member's own repository into its `ci/` closure, so `ci-self-input.nix`'s scanner
# runs on the lock this command just produced, and both locks are RESTORED on a violation. The
# `checks.ci-self-input` cell catches that state at `nix flake check`; this catches it at the moment
# of mutation, so it never lands in the first place.
#
# Spec: den-ag-design `specs/2026-09-18-gen-harness-relock-command-spec.md` §2.1, §2.3.
{
  pkgs,
  name,
  # The self-input predicate, from `ci-self-input.nix`. ONE implementation, two callers — see the
  # comment on `scanner` there for why it is a script and not a Nix function.
  scanner,
}:
pkgs.writeShellApplication {
  name = "${name}-relock";
  # DECLARED, not ambient, except for `nix` itself: `nix` must be the CALLER's, because it talks to
  # the caller's daemon and writes the caller's locks. `writeShellApplication` prepends these to an
  # inherited PATH, so the ambient `nix` still resolves — the same arrangement the `fmt` and `repl`
  # devshell commands rely on.
  runtimeInputs = [
    pkgs.jq
    pkgs.coreutils
    pkgs.git
  ];
  text = ''
    self=${name}-relock

    # printf rather than a heredoc: the terminator of a quoted heredoc has to sit at column 0 of
    # the SHELL script, and what reaches the shell here is whatever Nix leaves after stripping the
    # common indentation of this string. A formatter that reindents the block would move it.
    usage() {
      printf '%s\n' \
        "relock — bump this repository's locks, root first and then ./ci through the node that" \
        "carries the input there." \
        "" \
        "  relock           bump every declared input to its own tip, both locks" \
        "  relock <input>   bump one declared input; an input that FOLLOWS another is refused" \
        "" \
        "When nodes actually move, the pre-commit hook is REINSTALLED and the formatter is" \
        "APPLIED, because both are pinned by the locks just bumped and neither follows on its" \
        "own. THIS REWRITES SOURCE. A run that moves nothing, and every refusal, does neither." \
        "" \
        "relock --hub is RETIRED (it pinned inputs to the hub's revisions). Use bare relock for this" \
        "repository, and den-ag-design's relock-all to move the whole gen graph to its tips." >&2
    }

    # The worktree, NAMED rather than assumed, for the reason `readRootsGuard` states: the devshell
    # sets FLAKE_ROOT to the repository root (not to ci/), and a linked worktree must resolve to
    # ITSELF rather than climb into the main checkout.
    if [ -n "''${FLAKE_ROOT:-}" ]; then
      root=$FLAKE_ROOT
    elif ! root=$(git rev-parse --show-toplevel 2>&1); then
      printf '%s: not inside a git worktree and FLAKE_ROOT is unset: %s\n' "$self" "$root" >&2
      exit 2
    fi
    rootLock=$root/flake.lock
    ciDir=$root/ci
    ciLock=$ciDir/flake.lock

    # ★ THE REPOSITORY IS ESTABLISHED, NOT TRUSTED, AND THE ANSWER CAN BE A REFUSAL. The devshell
    # sets FLAKE_ROOT to the directory it was ENTERED FROM, not to the flake's own root, so a hand
    # `nix develop` run from inside <repo>/ci sets it to <repo>/ci and every path above is off by
    # one level: $rootLock is the REAL ci lock misread as the root lock, and $ciLock is a
    # nonexistent <repo>/ci/ci/flake.lock whose absence SKIPS the incoming self-input check on a
    # lock that was therefore never read. Bare relock then bumps the ci lock, reports it as a root
    # delta and exits 0 — the clean-exit failure this command exists to remove, reintroduced one
    # directory up from where the bare primitive used to do it.
    #
    # DISCRIMINATED, NOT DEFAULTED. Falling back to $PWD, or to git, when FLAKE_ROOT "looks wrong"
    # would be another guess one layer up. The ci/ shape is decidable on EXISTENCE ALONE — a flake
    # directory whose parent is a flake directory too is never a member's root — and existence
    # needs no git, which a `git rev-parse` cross-check would have newly required of the git-less
    # checkouts (tarball extractions, CI artifact checkouts) that work today.
    #
    # KNOWN RESIDUAL, named rather than hidden: a worktree created AS A SUBDIRECTORY of another
    # flake-bearing repository has this shape and would be refused here. This roster's worktrees
    # are siblings, never nested. The repair if it is ever hit is additive — name the intended root
    # explicitly — and does not change the discrimination above.
    #
    # Spec: den-ag-design `specs/2026-09-19-relock-repository-discrimination-spec.md` §2.2 (b), §2.3.
    parent=$(dirname "$root")
    if [ -f "$root/flake.nix" ] && [ -f "$parent/flake.nix" ]; then
      printf '%s\n' \
        "$self: MALFORMED INVOCATION, and nothing was written. FLAKE_ROOT names $root, a flake" \
        "directory whose parent $parent is a flake directory too — the ci/ shape. The devshell" \
        "sets FLAKE_ROOT to the directory it was ENTERED FROM, so this is what entering it from" \
        "inside ci/ looks like, and every path derived from it would be one level down: the ci" \
        "lock read as the root lock, and the self-input check skipped on a lock never read." \
        "Re-enter from the repository root:  cd $parent && nix develop ./ci" >&2
      exit 2
    fi

    # ★ A MISSING ROOT LOCK IS USUALLY CORRECT, AND THE DISCRIMINATION IS THE WHOLE POINT. A flake
    # that declares ZERO inputs never acquires a lock, and that shape is the stated objective for a
    # gen library (den-hoag-4dfsv: usable WITH and WITHOUT flakes — no flake inputs, a `default.nix`
    # deferring to `ci/flake.lock`). Measured 2026-09-18: gen-identity, gen-prelude and gen-algebra
    # are all of that shape, and they are the leaves everything else depends on — so refusing them
    # refused exactly the members that best match the architecture this command serves.
    #
    # DECLARED-BUT-UNLOCKED IS A DIFFERENT STATE AND IS REFUSED, never folded into the one above.
    # Such a repository has never been locked at all, and writing its FIRST lock is not a relock:
    # it is a larger act than this command takes on its own authority, and `nix flake lock` is the
    # one line that takes it deliberately. Folding the two together would silently ci-only a member
    # whose root inputs are simply not locked yet, which is the class of clean exit this whole
    # command exists to remove.
    rootLocked=yes
    if [ ! -f "$rootLock" ]; then
      rootLocked=no
      if [ ! -f "$root/flake.nix" ]; then
        printf '%s: no flake.nix and no flake.lock at %s — not a flake repository.\n' "$self" "$root" >&2
        exit 2
      fi
      # Read from the FILE, because with no lock there is nothing else to read it from. This is the
      # one place the lock is not the statement of the declared set — and `outputs` is never forced,
      # so no input is fetched and nothing is evaluated beyond the attribute names.
      rc=0
      rootInputs=$(nix eval --json --file "$root/flake.nix" \
        --apply 'f: builtins.attrNames (f.inputs or { })') || rc=$?
      if [ "$rc" -ne 0 ]; then
        printf '%s: CONTROL FAILED — could not read the declared inputs of %s/flake.nix.\n' \
          "$self" "$root" >&2
        exit 2
      fi
      if [ "$rootInputs" != "[]" ]; then
        printf '%s\n' \
          "$self: REFUSED, and nothing was written. $root/flake.nix DECLARES inputs but carries no" \
          "flake.lock:" \
          "  $(printf '%s' "$rootInputs" | jq -r 'join(" ")')" \
          "A flake with zero inputs legitimately has no lock and this command relocks its ci/ alone;" \
          "a flake with inputs and no lock has never been locked, and writing its first lock is not" \
          "a relock. Run: nix flake lock" >&2
        exit 1
      fi
    fi

    # The DECLARED INPUT SET of a flake, read from its LOCK. The lock is the only offline statement
    # of it, and it is the one the update primitive itself resolves against — so a name this refuses
    # is exactly a name that primitive would have no-opped on. An input just added to flake.nix and
    # not yet locked is therefore refused, and the message below says so and says what to run.
    declared() {
      jq -r '. as $d | ($d.nodes[$d.root // "root"].inputs // {}) | keys[]' "$1"
    }
    # ★ THREE ANSWERS, NOT TWO. `jq -e` exits 1 for false and ≥2 when it could not read the lock at
    # all, and inside an `if` errexit does not fire — so a bare `jq -e` here read an unreadable lock
    # as "not declared", printed `skipped`, and went on to act (den-hoag-yjs6x). The error is a
    # refusal, never a value.
    hasInput() {
      local rc=0
      jq -e --arg i "$2" '. as $d | (($d.nodes[$d.root // "root"].inputs // {}) | has($i))' "$1" \
        > /dev/null || rc=$?
      case $rc in
        0) return 0 ;;
        1) return 1 ;;
      esac
      printf '%s\n' \
        "$self: REFUSED, and nothing was written. $1 could not be read to decide whether $2 is" \
        "declared there (jq rc=$rc): its root node's inputs are not a set. Repair the lock first." >&2
      exit 1
    }

    # The node delta between two states of one lock, keyed by the lock's OWN node names. A
    # relabelling therefore reads as absent -> present on both sides, which is the honest rendering:
    # the node identity did change. Revision, else narHash, else path — a `path:` node has no rev
    # and must still be visible when it moves.
    moved() {
      jq -rn --slurpfile a "$1" --slurpfile b "$2" '
        def m($d):
          ($d.nodes // {}) | to_entries
          | map(select(.value.locked != null)
                | { key: .key,
                    value: (.value.locked.rev // .value.locked.narHash // .value.locked.path // "-") })
          | from_entries;
        (m($a[0])) as $x | (m($b[0])) as $y
        | (($x | keys) + ($y | keys) | unique)
        | map(select(($x[.] // "absent") != ($y[.] // "absent"))
              | "    \(.): \($x[.] // "absent") -> \($y[.] // "absent")")
        | .[]'
    }

    # ★ WHETHER ANYTHING MOVED AT ALL, which is a different question from whether the command
    # SUCCEEDED and is the one the catch-up step at the foot of this script turns on. A run that
    # moved no node bumped no formatter and no hook, so there is nothing for that step to do —
    # and saying so this way keeps it out of every path that writes nothing, which is what lets
    # `relock-behaviour.nix` stay hermetic.
    movedAny=no

    report() {
      label=$1
      before=$2
      after=$3
      if [ ! -f "$after" ]; then
        return 0
      fi
      delta=$(moved "$before" "$after")
      if [ -z "$delta" ]; then
        printf '  %s: 0 nodes moved\n' "$label"
      else
        movedAny=yes
        printf '  %s: %s node(s) moved\n' "$label" "$(printf '%s\n' "$delta" | wc -l)"
        printf '%s\n' "$delta"
      fi
    }

    # The self-input predicate, run twice — once on the INCOMING state and once on the produced
    # one — because the two verdicts are different findings and a command that only checks its
    # output blames itself for a violation it inherited.
    selfInput() {
      ${scanner}/bin/${name}-ci-self-input "$1" ${name}
    }

    mode=''${1:-}
    # Handled before anything is read or written: `--help` must not depend on a lock being
    # well-formed. The EMPTY mode is not handled here — it is the bump-everything act, dispatched
    # with the others below.
    case "$mode" in
      -h | --help)
        usage
        exit 0
        ;;
    esac

    # ★ AN UNREADABLE LOCK IS REFUSED BY NAME, BEFORE ANYTHING IS DECIDED FROM IT. Every reader
    # below takes a lock's shape for granted, and the ones inside a condition read a jq failure as
    # an answer: measured at 0f32611 on gen-demo with its root lock truncated to 200 bytes,
    # `relock nixpkgs` printed `root: nixpkgs is not declared there; skipped`, ran `nix flake
    # update` on ci, and died only at the node delta (den-hoag-yjs6x). The shape asserted is the
    # one those readers index: an object whose `nodes` is a set containing the root node.
    for lock in "$rootLock" "$ciLock"; do
      [ -f "$lock" ] || continue
      rc=0
      err=$(jq -e 'type == "object" and (.nodes | type == "object")
        and (.nodes[.root // "root"] | type == "object")' "$lock" 2>&1 > /dev/null) || rc=$?
      if [ "$rc" -ne 0 ]; then
        printf '%s\n' \
          "$self: REFUSED, and nothing was written. $lock is UNREADABLE as a flake lock (jq rc=$rc)." \
          "''${err:-It parses, but has no nodes set containing its root node.}" \
          "Every decision this command makes is read from that lock. Restore it, e.g.:" \
          "  git -C $root checkout -- $lock" >&2
        exit 1
      fi
    done

    # ★ THE INCOMING STATE IS CHECKED FIRST, AND A PRE-EXISTING VIOLATION STOPS THE COMMAND DEAD.
    # Two reasons, both measured on 2026-09-18 while building this. (1) `nix develop` AUTO-LOCKS an
    # input declared in `ci/flake.nix` and missing from `ci/flake.lock` — so merely LAUNCHING this
    # command through the devshell can write the violating node, and a post-only check would then
    # restore to a state that still violates while reporting that it had restored a clean one. (2)
    # Relocking on top of a violating closure buries the diagnosis under an unrelated node delta.
    if [ -f "$ciLock" ]; then
      rc=0
      selfInput "$ciLock" || rc=$?
      if [ "$rc" -eq 2 ]; then
        printf '%s: CONTROL FAILED — the self-input scanner did not run on the incoming lock.\n' "$self" >&2
        exit 2
      fi
      if [ "$rc" -ne 0 ]; then
        printf '%s\n' \
          "$self: REFUSED, and nothing was written. This repository is ALREADY in its own ci closure —" \
          "the violation above predates this command. Repair ci/flake.nix first; if the node appeared" \
          "just now, note that entering the devshell locks a newly declared input before any command" \
          "in it runs." >&2
        exit 1
      fi
    fi

    # BACKUPS SERVE TWICE: the baseline the delta is read against, and the state restored if the
    # produced tree violates the invariant the incoming one satisfied.
    backup=$(mktemp -d)
    trap 'rm -rf "$backup"' EXIT
    if [ "$rootLocked" = yes ]; then
      cp "$rootLock" "$backup/root.json"
    fi
    if [ -f "$ciLock" ]; then
      cp "$ciLock" "$backup/ci.json"
    fi

    case "$mode" in
      # NO ARGUMENT IS THE BUMP-EVERYTHING ACT, and it is spelled that way because the primitive
      # this wraps spells it that way: `nix flake update` with no input names updates ALL of them,
      # with a name updates that one. A flag for the unnamed case would be new vocabulary over a
      # verb the caller already knows (owner-ruled 2026-09-18).
      "")
        # The ci-only case ANNOUNCES ITSELF. Silence would leave the caller unable to tell a
        # one-act run from a two-act one, which is the same indistinguishability the delta report
        # below exists to remove.
        if [ "$rootLocked" = yes ]; then
          printf '%s: bumping every declared input to its own tip.\n' "$self"
          nix flake update --flake "$root"
        else
          printf '%s: no root inputs declared and no root lock; ci/ only.\n' "$self"
        fi
        if [ -f "$ciLock" ]; then
          nix flake update --flake "$ciDir"
        fi
        ;;

      # `--hub` (converge onto the hub's pins) is RETIRED and lands here as an unknown option,
      # whose usage names the replacement. Owner ruling 2026-09-23, den-hoag-n76a7 arm δ: every
      # lock points at the latest revision, so a mode that pins a member to the hub's closure has
      # no remaining purpose — and its node selection moved pins backwards.
      -*)
        printf '%s: unknown option %s\n' "$self" "$mode" >&2
        usage
        exit 2
        ;;

      *)
        input=$mode
        inRoot=no
        inCi=no
        if [ "$rootLocked" = yes ] && hasInput "$rootLock" "$input"; then inRoot=yes; fi
        if [ -f "$ciLock" ] && hasInput "$ciLock" "$input"; then inCi=yes; fi

        # ★ THE REFUSAL. Without it this command is `nix flake update`, which exits 0 on a name no
        # flake here declares and writes nothing — the failure mode the command exists to remove.
        if [ "$inRoot" = no ] && [ "$inCi" = no ]; then
          printf '%s: %s is not a declared input of this repository.\n' "$self" "$input" >&2
          if [ "$rootLocked" = yes ]; then
            printf '  root  (flake.lock):    %s\n' "$(declared "$rootLock" | tr '\n' ' ')" >&2
          else
            printf '  root  (flake.lock):    none — this flake declares no inputs and has no lock.\n' >&2
          fi
          if [ -f "$ciLock" ]; then
            printf '  ci    (ci/flake.lock): %s\n' "$(declared "$ciLock" | tr '\n' ' ')" >&2
          fi
          printf '%s\n' \
            "  The set is read from the LOCK. If you have just declared this input in flake.nix and" \
            "  not locked it yet, run: nix flake lock" >&2
          exit 1
        fi

        # ★ A FOLLOWS INPUT IS REFUSED BY NAME, BEFORE ACT ONE. Its lock value is a node PATH (a
        # list), not a node key: it has no revision of its own, `nix flake update <it>` no-ops
        # with a warning, and the carrier lookup below would index the node table with that list
        # and abort with a raw jq exit 5 (measured on gen-demo's `nixpkgs`, which follows
        # `gen/nixpkgs`). It moves when the input it follows moves, so that is what to name.
        for side in root ci; do
          if [ "$side" = root ]; then
            [ "$inRoot" = yes ] || continue
            lock=$rootLock
          else
            [ "$inCi" = yes ] || continue
            lock=$ciLock
          fi
          target=$(jq -r --arg i "$input" '
            . as $d | $d.nodes[$d.root // "root"].inputs[$i]
            | if type != "array" then "-" elif length == 0 then "" else join("/") end' "$lock")
          if [ "$target" != "-" ]; then
            # An EMPTY path is `follows = ""`: the input is disconnected and follows nothing.
            printf '%s\n' \
              "$self: REFUSED, and nothing was written. In the $side lock, $input follows ''${target:-nothing (follows = \"\")}:" \
              "it has no revision of its own and moves only with what it follows. Run: relock ''${target%%/*}" \
              "(or bare relock)." >&2
            exit 1
          fi
        done

        # ACT ONE — the root.
        if [ "$inRoot" = yes ]; then
          nix flake update "$input" --flake "$root"
        else
          printf '  root: %s is not declared there; skipped.\n' "$input"
        fi

        # ACT TWO — `./ci`, THROUGH THE NODE THAT CARRIES THE INPUT THERE. The sibling is usually
        # not a direct input of the ci flake: it arrives under some parent (`gen-harness`, or a
        # `path:..` back to the root), and naming it directly is the no-op of case 1 above. So the
        # carrier is DERIVED — the ci flake's direct inputs whose own closure resolves this
        # repository — and the carrier is what gets updated.
        #
        # KNOWN LIMIT, and it is the right one: only STRING input edges are followed, never the
        # array-valued `follows` edges. A node reachable from a direct input ONLY through a
        # `follows` is not built by that input's subtree, so bumping that input would not move it.
        if [ -f "$ciLock" ]; then
          repo=""
          if [ "$inRoot" = yes ]; then
            repo=$(jq -r --arg i "$input" '
              . as $d
              | ($d.nodes[$d.root // "root"].inputs[$i]) as $k
              | ($d.nodes[$k].locked.repo // "")' "$rootLock")
          fi

          carriers=()
          if [ -n "$repo" ]; then
            # Captured, never read through `< <(…)`: a process substitution's exit is discarded,
            # so a jq failure there read as "no input carries it" and left the ci lock behind.
            rc=0
            carrierList=$(jq -r --arg repo "$repo" '
              def repoOf($d; $n):
                ($d.nodes[$n].locked // {}) as $l
                | if ($l.repo // null) != null then $l.repo
                  elif ($l.type // "") == "git" and ($l.url // null) != null
                    then ($l.url | sub("\\.git$"; "") | split("/") | last)
                  else null end;
              def closure($d; $start):
                { seen: {}, todo: [$start] }
                | until((.todo | length) == 0;
                    (.todo[0]) as $n
                    | .todo = .todo[1:]
                    | if (.seen[$n] // false) then .
                      else .seen[$n] = true
                           | .todo = (.todo + [ ($d.nodes[$n].inputs // {}) | .[]
                                                | select(type == "string") ])
                      end)
                | (.seen | keys);
              . as $d
              | ($d.nodes[$d.root // "root"].inputs // {})
              | to_entries[]
              | select(.value | type == "string")
              | . as $e
              | select(closure($d; $e.value) | any(repoOf($d; .) == $repo))
              | $e.key' "$ciLock") || rc=$?
            if [ "$rc" -ne 0 ]; then
              printf '%s\n' \
                "$self: CONTROL FAILED — ci/flake.lock could not be read to find what carries $repo" \
                "(jq rc=$rc). The root lock is LEFT AS WRITTEN and ci/flake.lock was not touched." >&2
              exit 2
            fi
            if [ -n "$carrierList" ]; then
              mapfile -t carriers <<< "$carrierList"
            fi
          elif [ "$inCi" = yes ]; then
            # No resolved repository to trace (a tarball or path input, `nixpkgs` being the
            # standing case): the ci flake declares the name itself, so that name IS the carrier.
            carriers=("$input")
          fi

          if [ ''${#carriers[@]} -eq 0 ]; then
            printf '  ci: no input carries %s; ci/flake.lock left alone.\n' "''${repo:-$input}"
          else
            for c in "''${carriers[@]}"; do
              nix flake update "$c" --flake "$ciDir"
            done
          fi
        fi
        ;;
    esac

    printf '%s: node delta\n' "$self"
    if [ -f "$backup/root.json" ]; then
      report "root       " "$backup/root.json" "$rootLock"
    fi
    if [ -f "$backup/ci.json" ]; then
      report "ci/flake.lock" "$backup/ci.json" "$ciLock"
    fi

    # ★ THE PRODUCED TREE IS CHECKED, AND A VIOLATION IS RESTORED RATHER THAN REPORTED. The whole
    # point of running it here is that the bad state never lands. The incoming state was checked
    # above, so a red here is one THIS COMMAND introduced and the restore returns a state known to
    # satisfy the invariant — which is why the message can say so.
    if [ -f "$ciLock" ]; then
      rc=0
      selfInput "$ciLock" || rc=$?
      if [ "$rc" -eq 2 ]; then
        printf '%s: CONTROL FAILED — the self-input scanner did not run; the locks are LEFT AS WRITTEN.\n' \
          "$self" >&2
        exit 2
      fi
      if [ "$rc" -ne 0 ]; then
        # RESTORED FROM THE BACKUPS THAT WERE TAKEN, which on a ci-only member is `ci.json` alone.
        # Guarded rather than assumed: an unguarded `cp` of an absent root backup would abort here
        # under `set -e` and leave the violating ci lock ON DISK — an invariant that fires only on
        # the two-act path is worse than none, because the members it would skip are the leaves.
        if [ -f "$backup/root.json" ]; then
          cp "$backup/root.json" "$rootLock"
        fi
        if [ -f "$backup/ci.json" ]; then
          cp "$backup/ci.json" "$ciLock"
        fi
        printf '%s\n' \
          "$self: REFUSED — this relock would have put this repository into its own ci closure. Every" \
          "lock it touched has been RESTORED to the state before the command ran, which the same" \
          "check passed." >&2
        exit 1
      fi
    fi

    # ★★ THE LOCKS ARE NOT THE ONLY THING THE LOCKS DECIDE. A member's FORMATTER and its
    # PRE-COMMIT HOOK are both pinned by `ci/flake.lock`, and NEITHER follows a bump on its own:
    #
    #   THE FORMATTER. Measured four times on 2026-09-18 — gen-memo, gen-schema, gen-bind,
    #   gen-merge — `nix fmt -- --ci` gives `0 changed` at the old pins and `1 changed` after. A
    #   relock that moves its own formatter and does not apply it leaves the member UNABLE TO PASS
    #   ITS OWN CI, and all four had to be hand-landed. ★ The ordering is forced rather than
    #   preferred: measured on gen-schema, both arms in one run, a reformat carried into an
    #   old-pin copy is REVERTED by the OLD formatter. It cannot land ahead of the bump; it rides
    #   with it, which is here.
    #
    #   THE HOOK. `.pre-commit-config.yaml` is a MATERIALISED STORE PATH fixed at devshell entry,
    #   and its `treefmt` entry keeps pointing at the OLD formatter after a bump — so it silently
    #   REVERTS exactly what CI now requires, with both tools reporting success on their own
    #   terms and the commit failing for a reason neither names. Measured three times in three
    #   repositories (gen-memo 10998 -> 10978, gen-merge 12862 -> 12850). Re-entering the devshell
    #   reinstalls it and the disagreement vanishes.
    #
    # ★ RE-ENTRY FROM INSIDE A DEVSHELL IS AVAILABLE, measured rather than assumed: with this
    # repository's config deleted from inside its own `nix develop`, a NESTED `nix develop -c
    # true` printed the installer's own `pre-commit installed at .git/hooks/pre-commit` and
    # recreated the symlink, rc 0. The doubt this step was specified under does not hold.
    #
    # ★ GATED ON `movedAny`, NOT ON SUCCESS. A run that moved nothing moved no tooling, so this
    # does not fire — which is also what keeps it out of every refusing path and out of the
    # zero-input ci-only act, and therefore out of `relock-behaviour.nix`'s hermetic arms.
    if [ "$movedAny" = yes ] && [ -f "$ciDir/flake.nix" ]; then
      printf '%s: nodes moved, so the tooling those nodes pin moved with them.\n' "$self"

      # ENTERED FROM INSIDE `$ciDir`, never with `nix develop "$ciDir"` from elsewhere: the
      # installer resolves the repository from the CALLER's working directory, so the second form
      # rewrites the hooks of whatever repository the caller happens to be standing in.
      printf '  reinstalling the pre-commit hook at the new pin\n'
      if ! ( cd "$ciDir" && nix develop -c true ); then
        printf '%s\n' \
          "$self: THE LOCKS ARE WRITTEN AND THE TOOLING DID NOT FOLLOW. Re-entering the devshell" \
          "failed, so this repository's pre-commit hook still runs the formatter of the PREVIOUS" \
          "pin — which will silently revert what its own CI now requires. Locks: kept, they are" \
          "correct. Run: cd $ciDir && nix develop -c true" >&2
        exit 3
      fi

      # ★ THIS REWRITES SOURCE, and it is announced BEFORE it runs rather than after: a lock-bump
      # command that quietly edits tracked files is worse than one that does not, because the
      # caller decides what to stage.
      printf '  applying the formatter at the new pin — THIS REWRITES SOURCE\n'
      if ! ( cd "$ciDir" && nix fmt ); then
        printf '%s\n' \
          "$self: THE LOCKS ARE WRITTEN AND THE FORMATTER FAILED. This repository is left in a" \
          "state its own CI format step will refuse. Locks: kept, they are correct. Run:" \
          "  cd $ciDir && nix fmt" >&2
        exit 3
      fi

      # WHAT THE CALLER HAS TO STAGE BEYOND THE LOCKS. Named as what git reports rather than as
      # what the formatter wrote: on a tree that was already dirty those are not the same set, and
      # this command has no standing to claim the narrower one.
      if git -C "$root" rev-parse --git-dir > /dev/null 2>&1; then
        printf '%s: tracked files git now reports MODIFIED, the two locks excluded:\n' "$self"
        git -C "$root" status --porcelain --untracked-files=no -- \
          . ':(exclude)flake.lock' ':(exclude)ci/flake.lock'
      fi
    fi
  '';
}
