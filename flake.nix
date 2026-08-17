{
  description = "gen-harness — the CI harness the gen ecosystem's test flakes are built from (mkCi + its flake module), with no gen library inputs";

  # THE INPUT SET IS THE HARNESS'S WHOLE DEPENDENCY SET, and every entry is a TOOL. Five of the
  # seven tools are declared by NO consumer: a library's `ci/flake.nix` typically declares only
  # `nixpkgs`, `root` and the harness, and reaches nix-unit, treefmt-nix, devshell, flake-root and
  # git-hooks-nix through `resolve`'s fallback to these declarations (mkCi.nix). Dropping one does
  # not degrade a consumer — it makes the consumer's harness fail to evaluate.
  #
  # NO gen library input appears here, and that absence is the point of this repository: a library's
  # test harness must not depend on the aggregator that pins the library. The one function the
  # harness needs from gen-prelude is vendored (./prelude.nix), so a consumer's lock gains no gen
  # node from the harness and no library is built twice in one evaluation. The agreement test that
  # keeps the vendored copy honest declares gen-prelude in ./ci — the test plane, which no consumer
  # pins.
  inputs = {
    nixpkgs.url = "https://channels.nixos.org/nixos-unstable/nixexprs.tar.xz";
    flake-parts.url = "github:hercules-ci/flake-parts";
    flake-root.url = "github:srid/flake-root";
    nix-unit.url = "github:nix-community/nix-unit";
    nix-unit.inputs.nixpkgs.follows = "nixpkgs";
    treefmt-nix.url = "github:numtide/treefmt-nix";
    treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";
    devshell.url = "github:numtide/devshell";
    devshell.inputs.nixpkgs.follows = "nixpkgs";
    import-tree.url = "github:sini/import-tree";
    git-hooks-nix.url = "github:cachix/git-hooks.nix";
    git-hooks-nix.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = inputs: {
    # The symbol every consuming test flake reaches.
    lib.mkCi = import ./mkCi.nix { inherit inputs; };

    # The check builders and the plugin set, for a consumer that is gated by this machinery
    # without being an mkCi consumer — the gen hub's own ci is the case: it exposes flake checks
    # and a perf app rather than a nix-unit `tests` output, so it cannot take the module, but the
    # repository that ships these gates must be gated by them.
    #
    # ★ THEY ARE DECLARED SURFACE RATHER THAN FILE LAYOUT ON PURPOSE. A consumer could import
    # these paths out of the store directly and need nothing from this flake; then a rename here
    # would break that consumer with this repository's own gate green, which is the silent
    # coupling the extraction exists to remove. Declared, they are refutable by this repository's
    # CI before a consumer ever bumps.
    #
    # PURE FUNCTIONS OF `pkgs` — no flake-parts module, no gen input, no evaluation of this
    # flake's own inputs.
    lib.checks.treefmtTreeRoot = import ./treefmt-tree-root.nix;
    lib.checks.mdformatPlugins = import ./mdformat-plugins-check.nix;

    # `{ names, plugins }` — the membership fact and the `programs.mdformat.plugins` value built
    # from it. Both are published because a consumer that installs the set must also be able to
    # hand its names to the guard, and deriving them at the call site would be a second
    # statement of the membership.
    lib.mdformatBasePlugins = import ./mdformat-plugins.nix;
  };
}
