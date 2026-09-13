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
      state =
        if declares && !f.hasWfDir then
          "declares-no-workflow-dir"
        else if declares && !invoked then
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
      inherit state declares invoked;
      # Root-relative, both halves, so a reader checks the row against the tree by `file:line`.
      witness = {
        plane = if declares then "ci/tests-error.nix" else null;
        runs = if invoked then builtins.head hits else null;
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

  live = classify (readOf {
    inherit name;
    src = root;
  });
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
    # The obt1y cell: the step stays, the plane file is gone.
    runs-undeclared = {
      name = "seed-runs-undeclared";
      hasWfDir = true;
      wfFiles = [ (seedWf true) ];
      planeText = null;
    };
  };
  arm = builtins.mapAttrs (_: classify) seeds;
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
    # The seed's step is its fifth line; the witness coordinate is armed with the state.
    arming-runs = arm.runs.state == "runs" && arm.runs.witness.runs.line == 5;
    arming-unrun = arm.unrun.state == "declares-unrun";
    arming-nowf = arm.nowf.state == "declares-no-workflow-dir";
    arming-noplane = arm.noplane.state == "no-plane";
    arming-nowf-noplane = arm.nowf-noplane.state == "no-workflow-dir";
    arming-runs-undeclared = arm.runs-undeclared.state == "runs-undeclared";
    arming-empty-plane = leafCount armPlaneEmpty == 0 && leafCount armPlaneReal == 3;
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
