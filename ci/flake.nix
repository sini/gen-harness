{
  inputs = {
    # The harness tests itself with itself: `root` is this repository, and `root.lib.mkCi` is the
    # subject. The oracle is therefore not independent — an mkCi that cannot evaluate takes its own
    # suite down instead of reporting a red test. Known and accepted; hosting these suites in a
    # harness-free flake is a later, separate decision.
    root.url = "path:..";

    # gen-prelude ENTERS HERE AND ONLY HERE — the test plane. The agreement suite compares the
    # vendored hasInfix (../prelude.nix) against the original, so the duplication is checked rather
    # than trusted. No consumer pins this flake, so the edge fans to nobody: nothing downstream
    # gains a gen-prelude node, and no consumer can end up with two builds of it.
    gen-prelude.url = "github:sini/gen-prelude";

    # nixpkgs is the test runner's dependency (nix-unit, treefmt) and supplies the `lib` the suites
    # use. The harness root declares its own; this one is the consumer-side declaration mkCi reads.
    nixpkgs.url = "https://channels.nixos.org/nixos-unstable/nixexprs.tar.xz";
  };

  outputs =
    inputs@{ root, ... }:
    root.lib.mkCi {
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
      };
      # The `]` cells' `expr` ABORTS the moment `]` re-enters either escape set, and the batch
      # asserter behind `checks.default` cannot hold that — it forces every `expr` under
      # `flake.tests`. Those cells live on a second output instead.
      extraModules = [ ./tests-error.nix ];
    };
}
