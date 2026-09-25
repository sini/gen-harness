# Oracle for the CI-PLANE COVERAGE invariant: a repository that DECLARES an error plane RUNS it,
# and cannot satisfy that by deleting the plane.
#
# INVARIANT. If `ci/tests-error.nix` exists, some workflow step invokes `testsError` — AND if some
# workflow step invokes `testsError`, `ci/tests-error.nix` exists. Both directions, because the
# implication alone is satisfied vacuously by deleting the plane file while its step lives on: the
# repository silently stops being a declarer and reads green.
#
# WHY. `nix flake check` covers `flake.tests` only; the error plane is a second output that runs
# where, and only where, a workflow step names it. The class was discharged once at "13 of 13
# declarers run it" and re-opened six days later — a repository landed the plane file with no step,
# and nothing saw it for three days. A standing per-repository check is what stands between that
# and a third silent recurrence. Spec: den-ag-design
# `specs/2026-09-13-ci-plane-coverage-checker-spec.md`; every figure below is measured there.
#
# ★ DECLARES IS THE FILE — never the flake output and never a lexical mention. Two declarers carry
# the plane and never spell `testsError` in their own text (mkCi produces the output for them), and
# the output is unreachable from every vantage but the flake's own.
#
# ★ RUNS IS LEXICAL, AND NO YAML IS PARSED. Four conditions on a single line, each named where it
# stands in `runsLine`. Both measured instances of the defect are NO STEP AT ALL, which condition 3
# catches exactly; pure-eval Nix has no YAML reader; and the sharpest holes (a shell comment inside
# the `run:` scalar) sit where a parse would leave you anyway. What the rule is wrong about is
# tabled in the spec's §1.4 residue table — 10 of 35 arms, every row at live incidence 0 — and a
# workflow that routes the flake ref through `env:`, `with:` or a line fold is reded and inlines it.
#
# ★ READER AND CLASSIFIER ARE SEPARATE. `readOf` is the only half that touches the filesystem;
# `classify` is total over a facts record and never sees a path. The split is what lets the arming
# feed SYNTHETIC facts records: no fixture directory exists anywhere, so nothing outside this file
# can move its arming, and a correct build that lands, moves or retires a real plane cannot break
# an arming green — the only cells such a build moves are the two coverage cells, which should move.
# `plane-non-vacuous` is the one cell outside the split, deliberately: its unit is `test`-prefixed
# LEAVES of the EVALUATED `testsError` (what nix-unit collects), which no text-only record carries,
# so it reads the flake's own sibling output and is armed on a nested attrset of that same type.
# Top-level `attrNames` is the wrong unit — the plane is nested `suite.cell`, so a suite declared
# with zero cells reads 1 there and `🎉 0/0` in nix-unit, the false pass this cell exists for.
#
# ★ THE SHIPPED CHECK HAS NO LIVE RED SUBJECT AT HEAD, AND THAT IS CORRECT. Every red is seeded.
# What the arming does NOT reach: it proves the classifier discriminates every state; it does not
# prove the reader reads the right tree. A root bound one directory off classifies
# `no-workflow-dir` and reds `reader-live`; a root pinned to some other real tree passes it and
# reports that tree's row everywhere, which only a live pair across two repositories tells apart.
{
  pkgs,
  name,
  # The repository root, and it is `inputs.self.sourceInfo.outPath` — NEVER `outPath`. Under the
  # `?dir=ci` layout every consumer uses, the latter is `<root>/ci`, so the workflow directory and
  # the plane file would both be looked for one directory down. `agents-md-citations.nix` and
  # `readroots.nix` state the same ground.
  root,
  # The flake's own evaluated error plane, `config.flake.testsError`: the sibling output, read from
  # inside the flake that defines it. The one input the reader cannot produce from text.
  testsError,
  # The revision of the gen-harness this check was built FROM — `genInputs.self.sourceInfo.rev`,
  # handed in by `flakeModule.nix`. A caller's `evaluators.yml@<sha>` must equal it, or the run mixes
  # two identities of the harness (the workflow at one rev, the devshell commands it calls at
  # another). `null` where the caller could not supply it (the hub's à-la-carte `lib.checks` route
  # today): then any remote call is refused, because the equality cannot be decided.
  harnessRev ? null,
}:
let
  inherit (pkgs) lib;

  # ── RUNS: the four-condition rule, spec §1.4 ──
  tokens = [
    ".#testsError"
    "./ci#testsError"
  ];
  # Both ends; `[[:space:]]` takes the CR of a CRLF file.
  trimLine =
    l:
    let
      m = builtins.match "[[:space:]]*(.*[^[:space:]])[[:space:]]*" l;
    in
    if m == null then "" else builtins.head m;
  # The YAML key at the head of a trimmed line, or null for a keyless line — a block-scalar
  # continuation of whatever key opened the block.
  keyOf =
    t:
    let
      m = builtins.match "-?[[:space:]]*([A-Za-z_][A-Za-z0-9_-]*):.*" t;
    in
    if m == null then null else builtins.head m;
  runsLine =
    l:
    let
      t = trimLine l;
      key = keyOf t;
    in
    builtins.match "#.*" t == null # 1 not a YAML comment
    && (key == null || key == "run") # 2 an executing position
    && builtins.any (
      tok:
      let
        p = lib.splitString tok t;
      in
      builtins.length p > 1 # 3 the token, either spelling
      && builtins.match ".*[[:space:]]#.*" (builtins.head p) == null # 4 not a shell comment
    ) tokens;

  # ── CALLS: the reusable three-evaluator workflow (den-hoag-lbtnv), a second RUNS predicate ──
  # A job-level `uses:` of gen-harness's `evaluators.yml` runs the error plane on the same file
  # predicate this check declares by (`hashFiles('ci/tests-error.nix')`), so for a DECLARER it counts
  # as running it. For a NON-declarer it does not count as `runs-undeclared`: the call is conditional
  # and runs nothing there. Lexical, like `runsLine`: the value is the whole `uses:` scalar, quotes
  # and a trailing comment stripped. The LOCAL form counts only in a tree that itself carries
  # `evaluators.yml` — gen-harness — because anywhere else it names a file that is not there.
  #
  # ★ WHAT THIS RULE ADMITS — lexical, like `runsLine`, and for the same reason: no YAML is parsed, so
  # the rule sees the `uses:` LINE, never the job's reachability. Four admitted shapes, none tabled in
  # an external spec: a caller job disabled with `if: false`; a caller reachable only from
  # `workflow_dispatch` and never from `push`; a `uses:` line that happens to fall inside another
  # step's `run: |` block scalar, where it never executes as a call; and a step-level `- uses:` of the
  # workflow path, which is not an action, so GitHub refuses the job at run time — a red this check
  # never has to name, because GitHub names it first (derived, not run). The LOCAL-form admission
  # (`definesEvaluators` below) is the same shape one level up, ruled at phase 1 (§2.8): any tree that
  # carries its OWN file named `.github/workflows/evaluators.yml` reads `called = true`, because the
  # proxy is "defines the file", never "the file's origin is gen-harness". Measured at gen-harness
  # `4a6d4c0` by the `den-hoag-lbtnv` phase-3 landing gate: 0 live instances of a job-level `if:`
  # across the 26 caller files (control: 7 in gen-harness's own `evaluators.yml`, 1 in the hub's
  # sibling `docs-pages.yml`) — an INCIDENCE figure, not a property of this rule, and one a later
  # caller can move.
  callOf =
    l:
    let
      t = trimLine l;
      m = builtins.match "-?[[:space:]]*uses:[[:space:]]*['\"]?([^'\"[:space:]#]+)['\"]?([[:space:]]+#.*)?" t;
      v = builtins.head m;
      remote = builtins.match "sini/gen-harness/\\.github/workflows/evaluators\\.yml@([0-9a-f]{40})" v;
    in
    if m == null then
      null
    else if remote != null then
      {
        remote = true;
        ref = builtins.head remote;
      }
    else if v == "./.github/workflows/evaluators.yml" then
      {
        remote = false;
        ref = null;
      }
    else
      null;
  definesEvaluators = f: builtins.any (w: w.file == ".github/workflows/evaluators.yml") f.wfFiles;
  # Every call line of a facts record, with its coordinate. A local call in a tree without the file
  # is not a call.
  callsOf =
    f:
    builtins.filter (c: c.remote || definesEvaluators f) (
      lib.concatMap (
        w:
        lib.concatLists (
          lib.imap1 (
            line: text:
            let
              c = callOf text;
            in
            lib.optional (c != null) (
              c
              // {
                inherit (w) file;
                inherit line;
              }
            )
          ) (lib.splitString "\n" w.text)
        )
      ) f.wfFiles
    );
  # The SKEWED calls: a remote ref other than the locked harness, and ANY remote call in a tree that
  # defines the workflow itself — that tree would run a published copy of itself against its own
  # tree, the two-identity defect `ci-self-input` exists for.
  skewOf =
    rev: f:
    builtins.filter (c: c.remote && (rev == null || c.ref != rev || definesEvaluators f)) (callsOf f);

  # ── READER: the only half that touches the filesystem ──
  # facts = { name, hasWfDir, wfFiles = [ { file, text } ], planeText | null }. Files are kept
  # SEPARATE, never joined: a witness names `file:line`, and a file exists only if nothing joined it.
  readOf =
    { name, src }:
    let
      wfDir = "${src}/.github/workflows";
      hasWfDir = builtins.pathExists wfDir;
      wfNames = lib.optionals hasWfDir (
        builtins.attrNames (
          lib.filterAttrs (f: kind: kind != "directory" && builtins.match ".*\\.ya?ml" f != null) (
            builtins.readDir wfDir
          )
        )
      );
      planePath = "${src}/ci/tests-error.nix";
    in
    {
      inherit name hasWfDir;
      wfFiles = map (f: {
        file = ".github/workflows/${f}";
        text = builtins.readFile "${wfDir}/${f}";
      }) wfNames;
      planeText = if builtins.pathExists planePath then builtins.readFile planePath else null;
    };

  # ── CLASSIFIER: total over a facts record, no path access ──
  # The state space, stated once so `arming-covers-states` can hold the seeds to it.
  states = [
    "runs"
    "declares-unrun"
    "declares-no-workflow-dir"
    "runs-undeclared"
    "no-plane"
    "no-workflow-dir"
  ];
  classify =
    f:
    let
      declares = f.planeText != null;
      lines = lib.concatMap (
        w:
        lib.imap1 (line: text: {
          inherit (w) file;
          inherit line text;
        }) (lib.splitString "\n" w.text)
      ) f.wfFiles;
      hits = builtins.filter (w: runsLine w.text) lines;
      invoked = f.hasWfDir && hits != [ ];
      calls = callsOf f;
      called = f.hasWfDir && calls != [ ];
      state =
        if declares && !f.hasWfDir then
          "declares-no-workflow-dir"
        else if declares && !invoked && !called then
          "declares-unrun"
        else if declares then
          "runs"
        else if invoked then
          "runs-undeclared"
        else if !f.hasWfDir then
          "no-workflow-dir"
        else
          "no-plane";
    in
    {
      inherit (f) name;
      inherit
        state
        declares
        invoked
        called
        ;
      # Root-relative, both halves, so a reader checks the row against the tree by `file:line`.
      witness = {
        plane = if declares then "ci/tests-error.nix" else null;
        runs =
          if invoked then
            builtins.head hits
          else if declares && called then
            builtins.head calls
          else
            null;
      };
    };

  # ── plane-non-vacuous: `test`-prefixed LEAVES, recursively — what nix-unit collects ──
  # A `test`-prefixed attr is counted and not descended into; everything else that is an attrset is
  # descended into. Names and `isAttrs` only, so no cell body is forced — a throwing body is
  # nix-unit's subject. A throwing SPINE aborts the evaluation: loud, and stated.
  leafCount =
    set:
    builtins.foldl' (
      n: a:
      if lib.hasPrefix "test" a then
        n + 1
      else if builtins.isAttrs set.${a} then
        n + leafCount set.${a}
      else
        n
    ) 0 (builtins.attrNames set);

  refusesNonCaller = f: f.hasWfDir && !(classify f).called;

  liveFacts = readOf {
    inherit name;
    src = root;
  };
  live = classify liveFacts;
  liveSkew = skewOf harnessRev liveFacts;
  liveCells = leafCount testsError;

  # ── ARMING: synthetic facts records, built here, disjoint from every live reading ──
  # Each row reads its own seed and nothing live. Editing a seed reds the gate.
  seedPlane = "{ flake.testsError.suite.testOne = { expr = 1; expected = 1; }; }\n";
  seedWf = withStep: {
    file = ".github/workflows/ci.yml";
    text =
      "jobs:\n  check:\n    steps:\n      - run: nix flake check\n"
      + lib.optionalString withStep "      - run: nix develop --command nix-unit --flake .#testsError\n";
  };
  armRev = "0123456789abcdef0123456789abcdef01234567";
  seedCaller = rev: {
    file = ".github/workflows/ci.yml";
    text = "jobs:\n  ci:\n    uses: sini/gen-harness/.github/workflows/evaluators.yml@${rev} # the locked harness\n";
  };
  seeds = {
    runs = {
      name = "seed-runs";
      hasWfDir = true;
      wfFiles = [ (seedWf true) ];
      planeText = seedPlane;
    };
    unrun = {
      name = "seed-unrun";
      hasWfDir = true;
      wfFiles = [ (seedWf false) ];
      planeText = seedPlane;
    };
    nowf = {
      name = "seed-nowf";
      hasWfDir = false;
      wfFiles = [ ];
      planeText = seedPlane;
    };
    noplane = {
      name = "seed-noplane";
      hasWfDir = true;
      wfFiles = [ (seedWf false) ];
      planeText = null;
    };
    nowf-noplane = {
      name = "seed-nowf-noplane";
      hasWfDir = false;
      wfFiles = [ ];
      planeText = null;
    };
    # The CALLER shapes. `armRev` stands for the locked harness; no real revision is written here.
    caller = {
      name = "seed-caller";
      hasWfDir = true;
      wfFiles = [ (seedCaller armRev) ];
      planeText = seedPlane;
    };
    caller-noplane = {
      name = "seed-caller-noplane";
      hasWfDir = true;
      wfFiles = [ (seedCaller armRev) ];
      planeText = null;
    };
    caller-skew = {
      name = "seed-caller-skew";
      hasWfDir = true;
      wfFiles = [ (seedCaller (builtins.replaceStrings [ "0" ] [ "f" ] armRev)) ];
      planeText = seedPlane;
    };
    # A tree that DEFINES the workflow and calls a published copy of it at the very rev it is
    # locked to: refused anyway, because the rev being right does not make it one identity.
    remote-self-call = {
      name = "seed-remote-self-call";
      hasWfDir = true;
      wfFiles = [
        (seedCaller armRev)
        {
          file = ".github/workflows/evaluators.yml";
          text = "on:\n  workflow_call: {}\n";
        }
      ];
      planeText = seedPlane;
    };
    # The obt1y cell: the step stays, the plane file is gone.
    runs-undeclared = {
      name = "seed-runs-undeclared";
      hasWfDir = true;
      wfFiles = [ (seedWf true) ];
      planeText = null;
    };
  };
  arm = builtins.mapAttrs (_: classify) seeds;
  armSkew = builtins.mapAttrs (_: skewOf armRev) seeds;
  armStates = lib.unique (map (r: r.state) (builtins.attrValues arm));
  # The leaf counter's seeds, of the same type as its live input. The real-shaped one exercises all
  # three behaviours: a prefixed leaf counts, a prefixed leaf is not descended into (`testTwo`
  # carries a `testNested` that must not count), a non-prefixed attrset is descended into.
  armPlaneEmpty = {
    suite = { };
  };
  armPlaneReal = {
    suite = {
      testOne = {
        expr = 1;
        expected = 1;
      };
      testTwo = {
        testNested = 1;
      };
    };
    other = {
      notACell = { };
      test-three = { };
    };
  };

  gate = {
    every-declared-plane-runs =
      !(builtins.elem live.state [
        "declares-unrun"
        "declares-no-workflow-dir"
      ]);
    no-undeclared-runner = live.state != "runs-undeclared";
    # With the `declares` antecedent: a non-declarer has `testsError = { }` and did nothing wrong.
    plane-non-vacuous = !live.declares || liveCells > 0;
    # The universal positive control: the one file whose absence is impossible if this check is
    # evaluating from that flake at all. A blind reader, or a root one directory off, reds here.
    reader-live = builtins.pathExists "${root}/ci/flake.nix";
    caller-ref-is-locked-harness = liveSkew == [ ];
    # The three-evaluator ruling (den-hoag-lbtnv): a tree with a workflow directory runs its CI
    # through `evaluators.yml`. `called` is the same `callsOf` reading the skew cell keys on, so a
    # `run:`-only workflow, even one that runs the error plane, is not a call.
    # ★ THE KEY'S NAME SAYS "EVERY"; THE PREDICATE IS LOOSER. One caller job anywhere under
    # `.github/workflows` satisfies the whole directory — §2.5's hub keeps a non-caller sibling,
    # `docs-pages.yml`, beside its caller `ci.yml`, and both are green. The name is kept: this is a
    # shipped gate key, and renaming it is a separate change from what it means.
    every-workflow-calls-evaluators = !refusesNonCaller liveFacts;
    # The seed's step is its fifth line; the witness coordinate is armed with the state.
    arming-runs = arm.runs.state == "runs" && arm.runs.witness.runs.line == 5;
    arming-unrun = arm.unrun.state == "declares-unrun";
    arming-nowf = arm.nowf.state == "declares-no-workflow-dir";
    arming-noplane = arm.noplane.state == "no-plane";
    arming-nowf-noplane = arm.nowf-noplane.state == "no-workflow-dir";
    arming-runs-undeclared = arm.runs-undeclared.state == "runs-undeclared";
    arming-empty-plane = leafCount armPlaneEmpty == 0 && leafCount armPlaneReal == 3;
    # A caller is `runs` for a declarer and `no-plane` for a non-declarer — never runs-undeclared.
    arming-caller = arm.caller.state == "runs" && arm.caller.witness.runs.line == 3;
    arming-caller-noplane = arm.caller-noplane.state == "no-plane";
    arming-caller-at-locked-rev = armSkew.caller == [ ];
    arming-caller-skew = builtins.length armSkew.caller-skew == 1;
    arming-remote-self-call = builtins.length armSkew.remote-self-call == 1;
    # RED: a `run:`-only workflow, with or without the error-plane step. GREEN: a caller, declarer
    # or not. CONTROL: no workflow directory at all.
    arming-workflow-calls-evaluators =
      refusesNonCaller seeds.runs
      && refusesNonCaller seeds.noplane
      && !refusesNonCaller seeds.caller
      && !refusesNonCaller seeds.caller-noplane
      && !refusesNonCaller seeds.nowf-noplane;
    arming-covers-states = lib.sort lib.lessThan armStates == lib.sort lib.lessThan states;
  };
  gateKeys = builtins.attrNames gate;
  failed = builtins.filter (k: gate.${k} != true) gateKeys;
  allOk = failed == [ ];

  repair = {
    every-declared-plane-runs = "this repository declares an error plane (ci/tests-error.nix) and no workflow step runs it. Add `- run: nix develop --command nix-unit --flake .#testsError` (`./ci#testsError` from the repository root) to a step in .github/workflows/*.yml, or retire the plane file with the cells it carries.";
    no-undeclared-runner = "a workflow step invokes testsError and ci/tests-error.nix does not exist: the plane was renamed or removed while its step stayed. Restore the file or remove the step; a plane living on under another name is undeclared.";
    plane-non-vacuous = "ci/tests-error.nix is declared and the evaluated testsError holds 0 test-prefixed leaves: nix-unit would report 0/0 and exit 0, the false pass. Give the plane a cell or retire the file.";
    reader-live = "the reader cannot see ci/flake.nix under its root: the check is bound to the wrong tree. `root` must be inputs.self.sourceInfo.outPath.";
    every-workflow-calls-evaluators = "this repository has .github/workflows and no job calls gen-harness's evaluators.yml, so its CI does not run under upstream Nix, Determinate and Lix. Replace the `run:` job with `jobs.ci.uses: sini/gen-harness/.github/workflows/evaluators.yml@<the gen-harness rev in ci/flake.lock>` (write any 40-hex sha, then `relock` rewrites it), or remove the workflow directory.";
    caller-ref-is-locked-harness = "a `uses: sini/gen-harness/.github/workflows/evaluators.yml@<sha>` line names a revision other than the gen-harness this ci is locked to (${toString harnessRev}), or this tree defines evaluators.yml itself and calls a published copy. Run `relock`, which rewrites the sha to the locked rev; gen-harness calls its own workflow locally (`uses: ./.github/workflows/evaluators.yml`).";
  };
  armingRepair = "an arming cell stopped firing: the classifier or the leaf counter no longer discriminates the state its seed encodes. A guard that can no longer refuse is not a passing guard; repair the predicate, never the seed.";

  report = builtins.toJSON {
    inherit
      allOk
      failed
      root
      gate
      ;
    row = live;
    cells = liveCells;
    inherit harnessRev;
    skew = liveSkew;
    arming = builtins.mapAttrs (_: r: r.state) arm;
    armingCells = {
      empty = leafCount armPlaneEmpty;
      real = leafCount armPlaneReal;
    };
  };
in
pkgs.runCommand "${name}-ci-plane-coverage"
  {
    inherit report;
    passAsFile = [ "report" ];
    # The halves, reachable for an instrument that wants to drive the landed predicate over its
    # own arms or another tree without a flake around it.
    passthru = {
      inherit
        readOf
        classify
        runsLine
        callOf
        skewOf
        leafCount
        gate
        gateKeys
        ;
      row = live;
    };
  }
  ''
    echo "── ${name}-ci-plane-coverage ──"
    cat "$reportPath"
    echo
    ${lib.optionalString (!allOk) ''
      echo "CI-PLANE COVERAGE — failed: ${toString failed}" >&2
      ${lib.concatMapStrings (
        k: "echo ${lib.escapeShellArg "${k}: ${repair.${k} or armingRepair}"} >&2\n"
      ) failed}
      exit 1
    ''}
    cp "$reportPath" "$out"
  ''
