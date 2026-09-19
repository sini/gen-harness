# BEHAVIOUR ORACLE FOR `relock` — the arms that REFUSE, driven over synthetic trees.
#
# WHY IT EXISTS. `relock` mutates the locks of every repository in the ecosystem and is run before
# a push. It has had three defects, and ALL THREE were found by a person running it while this
# repository's suite stayed byte-identically green (`den-hoag-ecfua`):
#
#   1. THE INTERFACE. `--fresh` named an act the bare form should have been, and bare `relock`
#      printed usage and exited 2.
#   2. THE ARCHITECTURE. A member declaring ZERO root inputs has no root `flake.lock` — the shape
#      `den-hoag-4dfsv` prescribes — and the command aborted on exactly those members, which are
#      the leaves the rest of the roster depends on.
#   3. THE RESTORE. The self-input guard fired correctly on a ci-only member and then aborted under
#      `set -e` on an unguarded `cp` of a backup that had never been taken, leaving the violating
#      lock on disk while printing nothing about it.
#
# ★★ IT IS HERMETIC, AND THAT IS AN ASSERTION OF THIS CELL RATHER THAN A PROPERTY OF THE ARMS THAT
# HAPPENED TO BE CHOSEN. Every refusal `relock` makes is decided BEFORE its first `nix flake
# update`, so the whole refusing half of the command can be driven with the network off — and
# saying so here, with a live guard below, is what stops a later contributor quietly adding an
# acting arm and making this suite flaky at a distance. The guard at the head of the builder
# attempts an outbound TCP connection and FAILS THE BUILD IF IT SUCCEEDS.
#
# ★ WHAT IT DOES NOT COVER, stated rather than implied. Three arms need `nix flake update` and
# therefore a network and a daemon, and none of them is in here:
#   · the ci bump itself on the ci-only path (this cell asserts the DISCRIMINATION that reaches it,
#     not the act),
#   · the accepting half of the named-input refusal — asserted on its MESSAGE rather than its exit,
#     since the exit belongs to the act,
#   · defect 3's restore, whose post-act check can only fire on a lock the act has just written.
# The live acts are exercised by the owner running the command, which is where all three defects
# came from and remains the acceptance.
#
# THE FIXTURE SET SPANS THE SHAPES, WHICH IS THE POINT AND NOT THE ARM COUNT. Defects 2 and 3 were
# invisible partly because every fixture in play was copied from a member that HAS a root lock: a
# set derived from one shape tests that shape N times. These are synthetic and disjoint from every
# live reading — same discipline as `ci-self-input.nix`'s seeds, and for the same reason: no
# fixture directory exists anywhere, so nothing outside this file can move the result.
{
  pkgs,
  # The member name this harness instance is built for. Fixture identities are DERIVED from it and
  # never written, so no fixture can collide with a real repository — the defect measured in
  # `ci-self-input.nix`'s `clean-siblings` on 2026-09-18, where a hardcoded `gen-prelude` was
  # gen-prelude's own name in gen-prelude and inverted the cell there.
  name,
  # The COMMAND ITSELF, passed in rather than built here: this cell must drive the binary consumers
  # actually get. Built by the caller from `lib.relock` applied to `lib.checks.ciSelfInput`'s
  # `passthru.scanner`, which is the published route and makes this its third consumer.
  relock,
  # The name `relock` was built with — what its scanner treats as "this repository".
  fixtureName,
}:
let
  inherit (pkgs) lib;

  # A synthetic lock, minimal and well-formed. `version 7` and an explicit `root` because the
  # command's jq reads `$d.nodes[$d.root // "root"].inputs`.
  mkLock =
    inputs: nodes:
    builtins.toJSON {
      version = 7;
      root = "root";
      nodes = {
        root.inputs = inputs;
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

  # Two foreign repositories, derived so neither can ever be the fixture itself.
  alpha = "${fixtureName}-alpha";
  beta = "${fixtureName}-beta";

  # The INPUT NAME and the node key are both the repository name, which is the ordinary shape and
  # the one the arms below name. `declared` reads the KEYS of `root.inputs`, so an input keyed
  # `alpha` pointing at a node for some other repository would make this fixture encode a state no
  # arm here claims to test.
  declaredRootLock =
    mkLock
      {
        ${alpha} = alpha;
        ${beta} = beta;
      }
      {
        ${alpha} = ghNode alpha;
        ${beta} = ghNode beta;
      };
  cleanCiLock = mkLock { ${alpha} = alpha; } { ${alpha} = ghNode alpha; };
  # A ci lock that ALREADY carries this repository — the state §2.2's incoming arm refuses.
  dirtyCiLock = mkLock { ${alpha} = alpha; } {
    ${alpha} = ghNode alpha;
    self = ghNode fixtureName;
  };

  zeroInputFlake = "{ outputs = _: { }; }";

  # ★ EVERY FIXTURE CARRIES A `ci/flake.nix`, because every mkCi member does and a fixture without
  # one encodes a state no member can be in. It also makes the ONE guard that matters visible: the
  # post-bump catch-up at the foot of `relock` is gated on a node having moved AND on a ci flake
  # existing, and while no fixture had the second, the first could be deleted outright with every
  # arm here still green. Never evaluated by any arm — `relock` reads `ci/flake.lock`, and the one
  # `nix eval --file` it does is over the ROOT flake.
  ciFlake = "{ outputs = _: { }; }";
  declaredFlake = ''
    {
      inputs.${alpha}.url = "github:sini/${alpha}";
      outputs = _: { };
    }
  '';

  # ── THE FIXTURE SHAPES ──
  # `two-act`         root lock + ci lock, both clean — the ordinary member.
  # `dirty-ci`        the same, but its ci lock already resolves to itself.
  # `zero-input`      NO root lock and a flake declaring nothing — defect 2's shape, and the only
  #                   fixture here whose expected outcome is an ACT rather than a refusal. It
  #                   carries no ci lock either, so the act reduces to its announcement and the
  #                   arm stays hermetic.
  # `declared-unlocked`  NO root lock and a flake that DOES declare — the anomaly, refused.
  fixtures = {
    two-act = {
      rootLock = declaredRootLock;
      ciLock = cleanCiLock;
      flake = declaredFlake;
    };
    dirty-ci = {
      rootLock = declaredRootLock;
      ciLock = dirtyCiLock;
      flake = declaredFlake;
    };
    zero-input = {
      rootLock = null;
      ciLock = null;
      flake = zeroInputFlake;
    };
    declared-unlocked = {
      rootLock = null;
      ciLock = null;
      flake = declaredFlake;
    };
  };

  # ── THE ARMS ──
  # `wants` and `forbids` are matched against the COMBINED output. `locks` is `"unchanged"` where
  # the arm claims to write nothing — checked by digest around the whole invocation, never by
  # re-reading the file alone, because a write-then-restore returns a file to its original bytes.
  arms = [
    {
      label = "help-exits-zero-and-documents-the-bare-form";
      fixture = "two-act";
      args = [ "--help" ];
      rc = 0;
      wants = [
        "relock <input>"
        "bump every declared input to its own tip"
        # ★ THE SOURCE REWRITE IS DECLARED WHERE A CALLER LOOKS BEFORE RUNNING IT. A lock-bump
        # command that also reformats the tree and says so only afterwards has already spent the
        # caller's ability to decide; this arm holds the announcement to the ONE place it is
        # readable in advance.
        "THIS REWRITES SOURCE"
      ];
      forbids = [ "--fresh" ];
      locks = "unchanged";
    }
    {
      # `-h` and `--help` are ONE act with two spellings; asserted as identity below rather than by
      # re-listing the expectations, which two cells against one literal cannot catch drifting.
      label = "short-help-is-the-same-act";
      fixture = "two-act";
      args = [ "-h" ];
      rc = 0;
      wants = [ "relock <input>" ];
      forbids = [ "--fresh" ];
      locks = "unchanged";
    }
    {
      # ★ THE REMOVED FLAG MUST FAIL LOUDLY. Muscle memory types it; a silent acceptance and a
      # silent rejection are both wrong, and this command exists because the primitive under it
      # fails silently. It must NOT fall through to the bare act.
      label = "removed-flag-is-refused-by-name";
      fixture = "two-act";
      args = [ "--fresh" ];
      rc = 2;
      wants = [ "unknown option --fresh" ];
      forbids = [ "bumping every declared input" ];
      locks = "unchanged";
    }
    {
      # The discriminating partner of the arm above, and the reason it is `-h`: the unknown-option
      # branch is `-*`, so a dash-shaped argument that IS known must still be accepted. Without
      # this, an arm that rejected everything would read identically.
      label = "the-unknown-option-branch-accepts-a-known-dash-argument";
      fixture = "two-act";
      args = [ "-h" ];
      rc = 0;
      wants = [ ];
      forbids = [ "unknown option" ];
      locks = "unchanged";
    }
    {
      # Without this refusal the command is `nix flake update`, which exits 0 on a name no flake
      # here declares and writes nothing — the failure mode it exists to remove.
      label = "an-undeclared-input-is-refused-and-the-declared-set-is-shown";
      fixture = "two-act";
      args = [ "no-such-input" ];
      rc = 1;
      wants = [
        "no-such-input is not a declared input"
        "root  (flake.lock)"
        "ci    (ci/flake.lock)"
      ];
      forbids = [ ];
      locks = "unchanged";
    }
    {
      # ★ ASSERTED ON THE MESSAGE, NOT THE EXIT, and the header says why: a DECLARED input proceeds
      # to `nix flake update`, which is the act this cell does not run. What is checkable here is
      # that the refusal above discriminates by NAME rather than refusing everything.
      label = "a-declared-input-is-not-refused-as-undeclared";
      fixture = "two-act";
      args = [ alpha ];
      rc = null;
      wants = [ ];
      forbids = [ "is not a declared input" ];
      locks = "any";
    }
    {
      # ★ DEFECT 2. A member declaring nothing has no root lock, legitimately, and this is the one
      # arm here whose expectation is an ACT. It must not abort, it must SAY it took the one-act
      # path — silence leaves a caller unable to tell one act from two — and it must not invent a
      # root lock.
      label = "zero-root-inputs-and-no-root-lock-is-the-ci-only-act";
      fixture = "zero-input";
      args = [ ];
      rc = 0;
      wants = [ "no root inputs declared and no root lock; ci/ only" ];
      forbids = [
        "nothing to relock"
        "REFUSED"
      ];
      locks = "unchanged";
      noRootLockCreated = true;
    }
    {
      # The other side of defect 2's discrimination: declared-but-unlocked is a DIFFERENT state and
      # is refused by name. Folding it into the arm above would silently ci-only a member whose
      # root inputs merely are not locked yet.
      label = "declared-root-inputs-with-no-root-lock-are-refused-by-name";
      fixture = "declared-unlocked";
      args = [ ];
      rc = 1;
      wants = [
        "DECLARES inputs but carries no"
        alpha
        "nix flake lock"
      ];
      forbids = [ "ci/ only" ];
      locks = "unchanged";
      noRootLockCreated = true;
    }
    {
      # §2.2's INCOMING arm: a lock that already resolves to this repository stops the command dead,
      # before any backup or act, and says the violation predates it.
      label = "an-incoming-self-input-stops-the-command-dead";
      fixture = "dirty-ci";
      args = [ ];
      rc = 1;
      wants = [
        "SELF-INPUT"
        "ALREADY in its own ci closure"
      ];
      forbids = [ "bumping every declared input" ];
      locks = "unchanged";
    }
    {
      # ★ THE SAME CHECK, PROVEN TO DISCRIMINATE. `two-act` differs from `dirty-ci` in one node.
      # `--fresh` is used because it reaches PAST the incoming check before being refused, so a
      # clean fixture reaching the unknown-option branch is positive evidence the check passed
      # rather than never ran.
      label = "a-clean-incoming-lock-passes-the-same-check";
      fixture = "two-act";
      args = [ "--fresh" ];
      rc = 2;
      wants = [ "unknown option" ];
      forbids = [ "SELF-INPUT" ];
      locks = "unchanged";
    }
    {
      # `--help` must not depend on a lock being well-formed, which is why it is handled before
      # anything is read. Held on the fixture whose lock is a refusal.
      label = "help-does-not-depend-on-the-lock";
      fixture = "dirty-ci";
      args = [ "--help" ];
      rc = 0;
      wants = [ "relock <input>" ];
      forbids = [ "SELF-INPUT" ];
      locks = "unchanged";
    }
  ];

  sh = lib.escapeShellArg;

  mkFixture =
    fname:
    let
      f = fixtures.${fname};
    in
    ''
      rm -rf "$TMP/fix"
      mkdir -p "$TMP/fix/ci"
      cat > "$TMP/fix/flake.nix" <<'FIXTURE_FLAKE'
      ${f.flake}
      FIXTURE_FLAKE
      cat > "$TMP/fix/ci/flake.nix" <<'FIXTURE_CI_FLAKE'
      ${ciFlake}
      FIXTURE_CI_FLAKE
      ${lib.optionalString (f.rootLock != null) ''
        cat > "$TMP/fix/flake.lock" <<'FIXTURE_ROOT_LOCK'
        ${f.rootLock}
        FIXTURE_ROOT_LOCK
      ''}
      ${lib.optionalString (f.ciLock != null) ''
        cat > "$TMP/fix/ci/flake.lock" <<'FIXTURE_CI_LOCK'
        ${f.ciLock}
        FIXTURE_CI_LOCK
      ''}
      # The pre-state, as a DIGEST MANIFEST rather than a file comparison: a command that writes and
      # then restores returns the bytes it started with, and only a digest taken around the whole
      # invocation can tell "never written" from "written and put back". Both readings matter here,
      # but they are different claims and this cell makes the first one.
      ( cd "$TMP/fix" && find . -type f | sort | xargs md5sum ) > "$TMP/pre.md5"
    '';

  mkArm =
    arm:
    let
      wantChecks = lib.concatMapStringsSep "\n" (w: ''
        if ! grep -qF -- ${sh w} "$TMP/out"; then
          fail ${sh arm.label} "expected output to contain: ${lib.escapeShellArg w}"
        fi
      '') arm.wants;
      forbidChecks = lib.concatMapStringsSep "\n" (w: ''
        if grep -qF -- ${sh w} "$TMP/out"; then
          fail ${sh arm.label} "output must NOT contain: ${lib.escapeShellArg w}"
        fi
      '') arm.forbids;
    in
    ''
      ${mkFixture arm.fixture}
      rc=0
      FLAKE_ROOT="$TMP/fix" ${relock}/bin/${fixtureName}-relock ${
        lib.concatMapStringsSep " " sh arm.args
      } > "$TMP/out" 2>&1 || rc=$?

      ${lib.optionalString (arm.rc != null) ''
        if [ "$rc" -ne ${toString arm.rc} ]; then
          fail ${sh arm.label} "expected rc=${toString arm.rc}, got rc=$rc"
        fi
      ''}
      ${wantChecks}
      ${forbidChecks}
      ${lib.optionalString (arm.locks == "unchanged") ''
        ( cd "$TMP/fix" && find . -type f | sort | xargs md5sum ) > "$TMP/post.md5"
        if ! diff -q "$TMP/pre.md5" "$TMP/post.md5" > /dev/null; then
          fail ${sh arm.label} "the tree changed and this arm writes nothing:
        $(diff "$TMP/pre.md5" "$TMP/post.md5" || true)"
        fi
      ''}
      ${lib.optionalString (arm.noRootLockCreated or false) ''
        if [ -e "$TMP/fix/flake.lock" ]; then
          fail ${sh arm.label} "a root flake.lock was created; this shape legitimately has none"
        fi
      ''}
      # ★★ UNCONDITIONAL, ON EVERY ARM, AND IT IS THIS CELL'S HERMETICITY EXPRESSED AS AN
      # ASSERTION ABOUT THE COMMAND RATHER THAN ABOUT THE BUILDER. `relock` catches its formatter
      # and its pre-commit hook up after a bump — two acts that need a network and a devshell —
      # and it gates them on a NODE HAVING MOVED. No arm here can move a node, because moving one
      # needs the `nix flake update` none of them reaches. So the catch-up step must be silent in
      # every one of them, and a change that ungates it shows up HERE, as eleven named failures,
      # instead of as a suite that has quietly started needing the network.
      if grep -qF -- "so the tooling those nodes pin moved with them" "$TMP/out"; then
        fail ${sh arm.label} "the post-bump catch-up step ran on an arm that moved no node; it is gated on a node having moved, and this cell is hermetic only while that gate holds"
      fi
      if [ "$armFailed" -eq 0 ]; then
        echo "arm ok:     ${arm.label} (rc=$rc)"
      fi
    '';

  repair = "a `relock` behaviour arm stopped holding. Read WHICH arm and WHICH WAY. An arm that expected a REFUSAL and got something else means the command's refusing half has regressed — repair the command, never the arm; every one of these encodes a defect that reached a human. An arm that expected the CI-ONLY ACT and now refuses means the zero-root-input discrimination has regressed, which is `den-hoag-9jr` all over again. If an arm fails because it needed the network, it was added to the wrong cell: this one is hermetic by assertion and the acting half is exercised by running the command.";
in
pkgs.runCommand "${name}-relock-behaviour"
  {
    nativeBuildInputs = [
      pkgs.jq
      pkgs.diffutils
      # `relock` takes `nix` from the CALLER and not from its own `runtimeInputs` — it must talk to
      # the caller's daemon and write the caller's locks — so the caller has to supply one. Here
      # that caller is this builder. Supplying it is not a loosening: the only `nix` invocation any
      # arm reaches is `nix eval --file` over a fixture's own `flake.nix`.
      pkgs.nix
    ];
    passthru = { inherit arms fixtures; };
  }
  ''
    export TMP=$PWD
    fail_count=0
    armFailed=0

    fail() {
      echo "ARM FAILED: $1" >&2
      echo "  $2" >&2
      echo "  ── output ──" >&2
      sed 's/^/  | /' "$TMP/out" >&2 || true
      fail_count=$((fail_count + 1))
      armFailed=1
    }

    # ★ HERMETICITY, ASSERTED RATHER THAN ASSUMED. A build sandbox has no network; this says so out
    # loud so that a future arm which quietly needs one cannot pass by accident somewhere the
    # sandbox is relaxed. It fails the build on SUCCESS, which is the direction that matters.
    if (exec 3<>/dev/tcp/1.1.1.1/80) 2>/dev/null; then
      echo "CONTROL FAILED: this cell reached the network. Its arms are only meaningful offline;" >&2
      echo "the refusing half of relock decides before its first fetch, and that is the whole claim." >&2
      exit 2
    fi
    echo "hermetic:   no outbound TCP from this builder"

    # `relock` reads a flake's declared inputs with `nix eval --file` on the one path where there is
    # no lock to read them from. Inside a sandbox that needs the experimental command AND a state
    # directory it may write — neither changes what is evaluated, which is a plain file and a pure
    # function of it.
    export NIX_CONFIG="experimental-features = nix-command"
    export NIX_STORE_DIR=$PWD/nixstore NIX_STATE_DIR=$PWD/nixstate NIX_LOG_DIR=$PWD/nixlog

    ${lib.concatMapStringsSep "\n" (
      a:
      ''
        armFailed=0
      ''
      + mkArm a
    ) arms}

    if [ "$fail_count" -ne 0 ]; then
      echo "" >&2
      echo ${lib.escapeShellArg repair} >&2
      exit 1
    fi
    echo "all ${toString (builtins.length arms)} arms held"
    touch $out
  ''
