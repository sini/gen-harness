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
        "  relock <input>   bump one declared input" \
        "  relock --hub     converge both locks onto whatever the gen hub pins" \
        "" \
        "The hub defaults to github:sini/gen; set GEN_HUB to name another." >&2
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
    hasInput() {
      jq -e --arg i "$2" '. as $d | (($d.nodes[$d.root // "root"].inputs // {}) | has($i))' "$1" \
        > /dev/null
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

      --hub)
        # CONVERGE, which is not the same act as bump: each input goes to the revision the HUB
        # pins, not to its own tip. `nix flake lock --override-input` is the form that lands a
        # NAMED revision; `--update-input`/`nix flake update` follows the dependency's own tip and
        # would make this member a lone outlier one commit AHEAD of the roster instead of joining
        # it (measured 2026-09-17 on gen-inspect, carried at den-hoag-graph-viz-viy69).
        hub=''${GEN_HUB:-github:sini/gen}
        printf '%s: converging onto %s.\n' "$self" "$hub"
        hubMap=$(nix flake metadata --json --refresh "$hub" \
          | jq -c '[ .locks.nodes | to_entries[]
                     | select(.value.locked.repo != null and .value.locked.rev != null)
                     | { key: .value.locked.repo,
                         value: { owner: .value.locked.owner, rev: .value.locked.rev } } ]
                   | from_entries')

        converge() {
          dir=$1
          lock=$2
          [ -f "$lock" ] || return 0
          while IFS= read -r input; do
            [ -n "$input" ] || continue
            spec=$(jq -r --arg i "$input" --argjson hub "$hubMap" '
              . as $d
              | ($d.nodes[$d.root // "root"].inputs[$i]) as $k
              | ($d.nodes[$k].locked // {}) as $l
              | if ($l.repo // null) != null and ($hub[$l.repo] // null) != null
                   and $hub[$l.repo].rev != ($l.rev // "")
                then "github:\($hub[$l.repo].owner)/\($l.repo)/\($hub[$l.repo].rev)"
                else "" end' "$lock")
            [ -n "$spec" ] || continue
            printf '  %s <- %s\n' "$input" "$spec"
            nix flake lock "$dir" --override-input "$input" "$spec"
          done < <(declared "$lock")
        }
        converge "$root" "$rootLock"
        converge "$ciDir" "$ciLock"
        ;;

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
            mapfile -t carriers < <(jq -r --arg repo "$repo" '
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
              | $e.key' "$ciLock")
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
  '';
}
