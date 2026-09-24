# Oracle for the SELF-INPUT invariant: a member's `ci/` never tests a PUBLISHED COPY OF ITSELF.
#
# INVARIANT. No node in this repository's `ci/flake.lock` closure resolves to this repository, and
# none in its root `flake.lock` either. The root lock is in the domain because a `ci/` may evaluate
# the root flake itself: the hub's ci reads it at its own locked identity (den-hoag-lbtnv D1), so the
# root lock's nodes are in ci's evaluated closure while `ci/flake.lock` no longer holds a copy of
# them. A self-node in a root lock is a violation for every member, so widening the domain reds none
# that is clean — measured 2026-09-24 over the 31 local consumer root locks: 0 hits, with a planted
# `github:sini/gen` node in the hub's root lock firing rc 1 in the same run.
#
# THE RULING IT ENCODES (owner, 2026-09-18): "for internal coherence the ci → root will always
# diverge — and because of that ci in a module should always override its self-input", disambiguated
# to the arm above. Spec: den-ag-design `specs/2026-09-18-gen-harness-relock-command-spec.md` §2.2.
#
# WHY. A `ci/` that pins its own repository from a forge puts TWO IDENTITY FORMULAS FOR ONE NODE in
# a single evaluation — the working tree under test, and some published revision of it — and every
# cell downstream of the pair then reports about a mixture rather than about the tree. The invariant
# held across the ecosystem by accident: nothing checked it, and a relock is exactly the act that
# breaks it. This is that check.
#
# ★ MATCHED ON `locked.repo`, NEVER ON THE NODE LABEL. Labels are mangled by the locker, and the
# mangling is live: this repository's own `ci/flake.lock` carries `gen-prelude` AND `gen-prelude_2`
# for one repository, and gen-merge's carries four. A label predicate both misses a relabelled node
# and matches a longer label containing this one. Two arming seeds hold each half of that.
#
# ★ IT GUARDS THE PROPERTY, NOT THE MECHANISM. This check does NOT assert `flake = false` anywhere —
# that would pin one implementation of the invariant and pass the other two repairs. Dropping the
# input, `follows`-overriding it, and fetching it as a source tree all reach the invariant; adding a
# sibling that reaches back, or admitting the repository as a real flake input, all break it. A
# `flake = false` node is unremarkable in itself and matters only if it resolves to this member —
# `arm-self-flake-false` and `arm-clean-flake-false-other` are the two seeds that hold that apart.
#
# ★ A `path:` NODE IS NOT A VIOLATION. It locks as `{ type = "path"; path = ".."; }` with no `repo`
# at all, so it names no repository and is outside the domain. The invariant PRESCRIBES no
# mechanism: a `ci/` reaches its own tree by relative import (`import ../lib`, the majority form), by
# `self.sourceInfo`, or, where the root flake itself is the subject, by reading it at `self`'s own
# locked identity. No member uses `path:..` any more — Lix refuses that lock node — but
# `arm-clean-self-path` holds it green, so a later reader cannot "fix" the predicate into reding a
# shape that is the working tree rather than a published copy of it.
#
# ★ IT GATES. Per `den-hoag-6fmmb`'s criterion — a check whose red is cleared by a RULING must not
# gate, one cleared by a FIX should — a self-input is cleared by a fix, so it belongs in the gating
# set rather than beside `locks-agree`.
{
  pkgs,
  name,
  # The repository root, and it is `inputs.self.sourceInfo.outPath` — NEVER `outPath`. Under the
  # `?dir=ci` layout every consumer uses, the latter is `<root>/ci` and the lock would be looked for
  # one directory down. `agents-md-citations.nix` and `ci-plane-coverage.nix` state the same ground.
  root,
}:
let
  inherit (pkgs) lib;

  # ── THE PREDICATE, AND IT IS A SCRIPT RATHER THAN A NIX FUNCTION, DELIBERATELY ──
  # `relock` must run this same predicate on a tree it has just mutated, where there is no flake
  # evaluation to hang it off — the lock it produced is a file on disk, not an input to anything.
  # A Nix-side copy for the check and a shell-side copy for the command would be two statements of
  # one rule, and two statements drift; `mdformat-plugins-check.nix` takes its `expected` from the
  # installed value for the same reason. So there is ONE implementation, here, and both callers
  # exec it. The check below drives it over seeds; `relock.nix` execs it over its own output.
  #
  # Exit codes are three-valued on purpose, the way `readRootsGuard` splits them: 0 clean, 1 a
  # VERDICT about the lock, 2 the instrument did not run. A caller that folds 2 into 1 reports a
  # violation it never measured.
  scanner = pkgs.writeShellApplication {
    name = "${name}-ci-self-input";
    # DECLARED, not ambient, for the reason `readRootsGuard` states: `writeShellApplication`
    # PREPENDS runtimeInputs to an inherited PATH, so an undeclared `jq` would resolve to whatever
    # the caller happens to carry and the predicate would stop being hermetic.
    runtimeInputs = [ pkgs.jq ];
    text = ''
      if [ "$#" -ne 2 ]; then
        printf 'CONTROL FAILED: usage: %s <flake.lock> <repo>\n' "${name}-ci-self-input" >&2
        exit 2
      fi
      lock=$1
      target=$2

      if [ ! -f "$lock" ]; then
        printf 'CONTROL FAILED: no lock file at %s\n' "$lock" >&2
        exit 2
      fi

      # The RESOLVED REPOSITORY of a node, from the two lock shapes that name one:
      #   `github`/`gitlab`/`sourcehut` -> `locked.repo`, the field the spec names.
      #   `git`                         -> the last path segment of `locked.url`, `.git` stripped.
      # Compared by EQUALITY on that segment and never by substring, so `gen-harness-x` and
      # `gen-harnes` are both misses. Every other type (`path`, `tarball`, `file`) names no
      # repository and is not in the domain — which is why a `path:..` self-reference, the working
      # tree rather than a published copy, is silent here, and must stay silent.
      rc=0
      hits=$(jq -r --arg target "$target" '
        (.nodes // {})
        | to_entries[]
        | select(.value.locked != null)
        | . as $e
        | $e.value.locked as $l
        | (
            if ($l.repo // null) != null then $l.repo
            elif ($l.type // "") == "git" and ($l.url // null) != null
              then ($l.url | sub("\\.git$"; "") | split("/") | last)
            else null
            end
          ) as $repo
        | select($repo == $target)
        | "  node \($e.key)\ttype=\($l.type)\t\($l.owner // "?")/\($repo)\trev=\($l.rev // "-")"
      ' "$lock") || rc=$?
      if [ "$rc" -ne 0 ]; then
        printf 'CONTROL FAILED: %s is not readable as a flake lock (jq rc=%s)\n' "$lock" "$rc" >&2
        exit 2
      fi

      if [ -z "$hits" ]; then
        exit 0
      fi

      printf 'SELF-INPUT: %s carries %s node(s) resolving to this repository (%s):\n' \
        "$lock" "$(printf '%s\n' "$hits" | wc -l)" "$target" >&2
      printf '%s\n' "$hits" >&2
      printf '%s\n' \
        "The ci/ of a module must never test a PUBLISHED COPY OF ITSELF: the run would carry two" \
        "identity formulas for one node. Repair by any of — fetching it as a source tree" \
        "(<input>.flake = false), dropping the input, or follows-overriding it onto the tree already" \
        "under test. The check reads the RESOLVED CLOSURE and not any one line, so all three repairs" \
        "satisfy it and none of them is the one the check is looking for." >&2
      exit 1
    '';
  };

  bin = "${scanner}/bin/${name}-ci-self-input";

  # ── SEEDS: synthetic locks, disjoint from every live reading ──
  # Same discipline as `ci-plane-coverage.nix`: no fixture directory exists anywhere, so nothing
  # outside this file can move the arming, and a correct relock that lands in this repository
  # cannot break an arming green — the only cell such a landing moves is the live one.
  mkLock =
    nodes:
    builtins.toJSON {
      version = 7;
      root = "root";
      nodes = {
        root.inputs = { };
      }
      // nodes;
    };

  ghNode = repo: {
    locked = {
      type = "github";
      owner = "sini";
      inherit repo;
      rev = "0000000000000000000000000000000000000000";
    };
  };

  # ★★ EVERY REPOSITORY NAME IN A SEED IS DERIVED FROM `name`. NONE IS WRITTEN. A seed that names
  # "some other repository" by hardcoding a real member's name IS that member's own name in that
  # member, so the seed's expectation inverts in exactly the repositories it names — and it does so
  # silently, because these are NEGATIVE controls and a negative control that starts refusing reads
  # like the subject being dirty.
  #
  # MEASURED 2026-09-18, at the cost of two false CI reds in one propagation: `clean-siblings`
  # hardcoded `gen-prelude` and `gen-graph`, and its arming failed in exactly and only those two
  # members — `ARMING FAILED: clean-siblings expected rc=0, got rc=1`, on node `a` in gen-prelude
  # and node `b` in gen-graph — while both members' real locks were clean and the live arm said so
  # in the same output. `clean-flake-false-other` hardcoded `gen` and held the identical defect
  # latent, firing the moment the check is asked about the hub (measured: it does). Renaming to two
  # other members would only move the bug onto them; the property has to be structural.
  #
  # THE PROPERTY: a string that strictly CONTAINS `name` can never equal `name`, so a name built by
  # extending it is provably not the member under test, whatever that member is called. That is also
  # the rule the predicate itself implements — equality on the resolved repository, never substring
  # — so these stand-ins exercise it in both directions while they play foreign repositories.
  shorterName = builtins.substring 0 (builtins.stringLength name - 1) name;
  longerName = "${name}-sibling";
  prefixedName = "sibling-${name}";

  seeds = [
    {
      label = "self-github";
      expect = 1;
      nodes = {
        self = ghNode name;
      };
    }
    {
      # The one that keeps the check off the mechanism: a self-node fetched as a source tree is
      # STILL this repository in this repository's closure, and still red.
      label = "self-flake-false";
      expect = 1;
      nodes = {
        self = (ghNode name) // {
          flake = false;
        };
      };
    }
    {
      # Label-independence, first half: the locker's mangled label must not hide the node.
      label = "self-mangled-label";
      expect = 1;
      nodes = {
        "_4" = ghNode name;
      };
    }
    {
      label = "self-git-url";
      expect = 1;
      nodes = {
        anything = {
          locked = {
            type = "git";
            url = "https://github.com/sini/${name}.git";
            rev = "0000000000000000000000000000000000000000";
          };
        };
      };
    }
    {
      # TWO foreign nodes rather than one: a populated lock must read clean, not merely an empty
      # one. Both names are derived (see above) and they extend `name` in opposite directions, so
      # the cell also says that neither a prefix nor a suffix match is an equality match.
      label = "clean-siblings";
      expect = 0;
      nodes = {
        a = ghNode longerName;
        b = ghNode prefixedName;
      };
    }
    {
      # A `flake = false` node for ANOTHER repository is unremarkable — gen-memo's hub pin is
      # exactly this — and a predicate that reded here would be asserting the mechanism. The name
      # is DERIVED, not `gen`: written as the hub's real name this cell inverted whenever the check
      # was asked about the hub, which is the same defect `clean-siblings` carried live.
      label = "clean-flake-false-other";
      expect = 0;
      nodes = {
        hub = (ghNode prefixedName) // {
          flake = false;
        };
      };
    }
    {
      # Label-independence, second half: a LONGER repo name containing this one is a miss.
      label = "clean-longer-name";
      expect = 0;
      nodes = {
        x = ghNode longerName;
      };
    }
    {
      label = "clean-shorter-name";
      expect = 0;
      nodes = {
        x = ghNode shorterName;
      };
    }
    {
      # A path node names no repository: the working tree, never a published copy. Held green so a
      # later reader cannot "repair" the predicate into reding it.
      label = "clean-self-path";
      expect = 0;
      nodes = {
        self = {
          locked = {
            type = "path";
            path = "..";
          };
        };
      };
    }
  ];

  armLines = lib.concatMapStrings (
    s:
    "arm ${toString s.expect} ${lib.escapeShellArg s.label} ${pkgs.writeText "${name}-self-input-seed-${s.label}.json" (mkLock s.nodes)}\n"
  ) seeds;

  # ── THE LIVE SUBJECT, read at EVAL time and materialised ──
  # `builtins.readFile` under `root`, the way `ci-plane-coverage.nix` reads its facts: the builder
  # then has the bytes as a declared input rather than reaching into a store path it never depends
  # on. An absent lock is VACUOUS, not a red — but `readerLive` below still has to fire, so a check
  # bound to the wrong tree cannot pass by finding nothing.
  lockPath = "${root}/ci/flake.lock";
  hasLock = builtins.pathExists lockPath;
  liveLock = pkgs.writeText "${name}-ci-flake-lock.json" (
    if hasLock then builtins.readFile lockPath else mkLock { }
  );

  # The ROOT lock, the second subject (see the header). Absent is vacuous here too: a ci-only member
  # has no root lock.
  rootLockPath = "${root}/flake.lock";
  hasRootLock = builtins.pathExists rootLockPath;
  liveRootLock = pkgs.writeText "${name}-root-flake-lock.json" (
    if hasRootLock then builtins.readFile rootLockPath else mkLock { }
  );

  readerLive = builtins.pathExists "${root}/ci/flake.nix";
  readerRepair = "CONTROL FAILED: the reader cannot see ci/flake.nix under its root (${root}): the check is bound to the wrong tree. `root` must be inputs.self.sourceInfo.outPath.";
  # ★ READ WHICH WAY THE CELL FAILED BEFORE TOUCHING ANYTHING — the two directions have opposite
  # repairs, and the single-direction version of this sentence sent a reader at a correct scanner.
  armingRepair = "an arming cell stopped discriminating, and WHICH WAY it failed decides the repair. (1) A cell that expected a REFUSAL (expect=1) and got a pass means the scanner can no longer refuse. A guard that cannot refuse is not a passing guard: repair the predicate, never the seed. (2) A cell that expected a PASS (expect=0) and got a refusal may instead mean the SEED IS INVALID IN THIS REPOSITORY — a seed standing in for another repository must be DERIVED from `name`, because a hardcoded name is the member's own name in that member. Measured 2026-09-18: `clean-siblings` hardcoded gen-prelude and gen-graph and reded in exactly those two, with both real locks clean. The `live:` line below is the tell — if it says no node resolves to this repository, the member is fine and the seed is the defect.";
in
pkgs.runCommand "${name}-ci-self-input"
  {
    # The predicate itself, reachable for `relock.nix` and for any instrument that wants to drive
    # the landed scanner over another tree without a flake around it.
    passthru = {
      inherit scanner seeds;
    };
  }
  ''
    echo "── ${name}-ci-self-input ──"
    ${lib.optionalString (!readerLive) ''
      echo ${lib.escapeShellArg readerRepair} >&2
      exit 1
    ''}
    echo "reader-live: ci/flake.nix found under ${root}"
    echo ${
      lib.escapeShellArg (
        if hasLock then
          "subject: ci/flake.lock"
        else
          "subject: no ci/flake.lock — the closure is empty and the invariant is vacuous"
      )
    }

    fail=0
    arm() {
      want=$1
      label=$2
      seed=$3
      rc=0
      ${bin} "$seed" ${lib.escapeShellArg name} > arm.log 2>&1 || rc=$?
      if [ "$rc" -eq "$want" ]; then
        echo "arming ok:     $label (rc=$rc)"
      else
        echo "ARMING FAILED: $label expected rc=$want, got rc=$rc" >&2
        cat arm.log >&2
        echo ${lib.escapeShellArg armingRepair} >&2
        fail=1
      fi
    }
    ${armLines}

    live() {
      label=$1
      lock=$2
      rc=0
      ${bin} "$lock" ${lib.escapeShellArg name} || rc=$?
      if [ "$rc" -eq 0 ]; then
        echo "live:          no node in $label resolves to ${name}"
      elif [ "$rc" -eq 2 ]; then
        echo "CONTROL FAILED: the scanner could not read this repository's own $label" >&2
        fail=1
      else
        fail=1
      fi
    }
    live ci/flake.lock ${liveLock}
    live flake.lock ${liveRootLock}

    [ "$fail" -eq 0 ] || exit 1
    touch $out
  ''
