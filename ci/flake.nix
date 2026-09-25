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

    # gen-prelude ENTERS HERE AND ONLY HERE — the test plane. The agreement suite compares the
    # vendored hasInfix (../prelude.nix) against the original, so the duplication is checked rather
    # than trusted. No consumer pins this flake, so the edge fans to nobody: nothing downstream
    # gains a gen-prelude node, and no consumer can end up with two builds of it.
    gen-prelude.url = "github:sini/gen-prelude";

    # gen-dispatch and gen-select, for the dispatch-select-adapter suite: a cross-library
    # integration suite's subject is a PAIRING, and this is that pairing's home (see README —
    # neither sibling becomes the other's declared dependency for it). Pinned directly here rather
    # than through gen-dispatch's own ci, which is what let this suite's gen-select pin go stale
    # unnoticed. Fans to nobody downstream, same as gen-prelude above.
    gen-dispatch.url = "github:sini/gen-dispatch";
    gen-select.url = "github:sini/gen-select";

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
      specialArgs = {
        upstreamPrelude = inputs.gen-prelude.lib;
        # The original's SOURCE as well as its value: the escape set is compared as text, because a
        # set has members no case table reaches.
        upstreamSrc = inputs.gen-prelude;
        # gen-dispatch's own flake wires gen-prelude into `lib` already, so this is the fully built
        # library — the same value a consumer pinning gen-dispatch directly would get.
        genDispatch = inputs.gen-dispatch.lib;
        genSelect = inputs.gen-select.lib;
      };
      # The `]` cells' `expr` ABORTS the moment `]` re-enters either escape set, and the batch
      # asserter behind `checks.default` cannot hold that — it forces every `expr` under
      # `flake.tests`. Those cells live on a second output instead.
      #
      # `tests-process.nix` adds the PROCESS PLANE and no cells at all: the `relock` behaviour arms
      # are the exit codes and messages of a built command over synthetic trees, which no
      # `expr`/`expected` pair can express, and three of them are verdicts of the column's own
      # evaluator, so they run as a program under `ci --tests-process`, never as a check.
      # `process-plane-guard.nix` adds a flake CHECK: the `ci --tests-process` closure guard's exit
      # codes and messages over real fixture closures.
      extraModules = [
        ./tests-error.nix
        ./tests-process.nix
        ./process-plane-guard.nix
      ];
    };
}
