{
  inputs = {
    # The harness tests itself with itself: `gen-harness` is this repository, and
    # `gen-harness.lib.mkCi` is the subject. The oracle is therefore not independent — an mkCi that
    # cannot evaluate takes its own suite down instead of reporting a red test. Known and accepted;
    # hosting these suites in a harness-free flake is a later, separate decision.
    #
    # ★ THE SUBJECT IS READ BY RELATIVE PATH, NEVER AS A `path:..` INPUT. Lix refuses a relative
    # `path` node in a lock ("mutable lock"), which took this whole plane down under Lix before a
    # cell ran; and a Lix-written `path:..?narHash=…` lock pins a stale snapshot of the tree, which
    # is a published copy of itself (den-hoag-lbtnv D1). So `outputs` below applies `../flake.nix`'s
    # own `outputs` to the inputs declared here, and the harness's TOOL inputs are declared here,
    # line for line as `../flake.nix` declares them — the majority form, the library's own
    # dependencies re-declared on its test plane. `ci/tests/tool-agreement.nix` holds the two
    # declarations and the two locks equal, because nothing else would see them drift.
    flake-parts.url = "github:hercules-ci/flake-parts";
    flake-root.url = "github:srid/flake-root";
    nix-unit.url = "github:nix-community/nix-unit";
    nix-unit.inputs.nixpkgs.follows = "nixpkgs";
    treefmt-nix.url = "github:numtide/treefmt-nix";
    treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";
    devshell.url = "github:numtide/devshell";
    devshell.inputs.nixpkgs.follows = "nixpkgs";
    import-tree.url = "github:denful/import-tree/a164a12202f58eb67559bd33b5592f20660d9baf";
    git-hooks-nix.url = "github:cachix/git-hooks.nix";
    git-hooks-nix.inputs.nixpkgs.follows = "nixpkgs";

    # NO GEN LIBRARY ENTERS HERE EITHER. Every member's ci pins this repository, so a gen input on
    # this plane is a REVISION CYCLE: relocking it moves this repository, which stales every
    # member's pin of it, and no visit order reaches a fixed point (den-hoag-lock-currency-ruling-ez1yq).
    # The vendored hasInfix is held to nixpkgs `lib.hasInfix` — the reference gen-prelude's own
    # fidelity suite holds the original to — and the gen-dispatch × gen-select pairing is tested
    # in gen-dispatch's ci, which already pins gen-select. `tests/no-gen-inputs.nix` holds it.

    # The error plane's three ENGINES (`error-plane-engines.nix`), each at the release `evaluators.yml`
    # pins for its column and with no `follows`, so the out path is the one the column installs.
    # `ci/tests/engine-pins.nix` holds each equal to its pin.
    nix-upstream.url = "github:NixOS/nix/2.35.2";
    nix-determinate.url = "github:DeterminateSystems/nix-src/v3.23.0";
    nix-lix.url = "https://git.lix.systems/lix-project/lix/archive/2.95.3.tar.gz";

    # nixpkgs is the test runner's dependency (nix-unit, treefmt) and supplies the `lib` the suites
    # use. The harness root declares its own; this one is the consumer-side declaration mkCi reads.
    nixpkgs.url = "https://channels.nixos.org/nixos-unstable/nixexprs.tar.xz";
  };

  outputs =
    ciInputs:
    let
      rootFlake = import ../flake.nix;
      # The published surface of THIS tree: ../flake.nix's own `outputs`, applied to the inputs
      # declared above. `sourceInfo` is this tree's, for the cells that read the harness's files.
      gen-harness = rootFlake.outputs ciInputs // {
        inherit (ciInputs.self) sourceInfo;
        outPath = ciInputs.self.sourceInfo.outPath;
      };
      # ★ mkCi IS HANDED THE CONSUMER SHAPE: no tool input. Every consumer ci flake but the hub's
      # and gen-flake's declares none (34 of 36 local, 2026-09-24), so they reach every tool through `resolve`'s fallback to `genInputs` (`mkCi.nix`,
      # `flakeModule.nix`). Handing mkCi the tools declared above would send this suite down the
      # other branch only, and a broken fallback would red every consumer with this repository
      # green. `nixpkgs` stays: consumers declare it and mkCi reads it directly.
      toolNames = builtins.filter (n: n != "nixpkgs") (builtins.attrNames rootFlake.inputs);
      inputs = removeAttrs ciInputs toolNames // {
        inherit gen-harness;
      };
    in
    gen-harness.lib.mkCi {
      inherit inputs;
      name = "gen-harness";
      testModules = ./tests;
      # `genPrelude` is NOT passed: mkCi supplies it, and the vendored copy it supplies is exactly
      # what the agreement suite is about — overriding it here would test a value no consumer gets.
      # The `]` cells' `expr` ABORTS the moment `]` enters the vendored escape set, and the batch
      # asserter behind `checks.default` cannot hold that — it forces every `expr` under
      # `flake.tests`. Those cells live on a second output instead.
      #
      # `tests-process.nix` adds the PROCESS PLANE and no cells at all: the `relock` behaviour arms
      # are the exit codes and messages of a built command over synthetic trees, which no
      # `expr`/`expected` pair can express, and three of them are verdicts of the column's own
      # evaluator, so they run as a program under `ci --tests-process`, never as a check.
      # `process-plane-guard.nix` adds a flake CHECK: the `ci --tests-process` closure guard's exit
      # codes and messages over real fixture closures. `agents-md-sheet-arms.nix` adds a flake CHECK
      # too: `agents-md-citations`'s declaration arms, run as the shipped builder over fixture roots.
      # `staged-commit-hook.nix` adds a flake CHECK: the published commit hook and its writer, run over
      # git fixtures in the sandbox with an exact cell count.
      extraModules = [
        ./tests-error.nix
        ./tests-process.nix
        ./process-plane-guard.nix
        ./read-roots-guard.nix
        ./staged-commit-hook.nix
        ./agents-md-sheet-arms.nix
        # The harness publishes no root `default.nix`; its surface is the flake's `lib`.
        { gen.ci.rootSurface.entry = "not-owed"; }
      ];
    };
}
