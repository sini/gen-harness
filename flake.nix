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
    import-tree.url = "github:denful/import-tree/a164a12202f58eb67559bd33b5592f20660d9baf";
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

    # Unlike its two neighbours this one takes a SOURCE ROOT rather than a built formatter: its
    # subject is the repository's own tree, so it re-evaluates on any source change. That is the
    # cost the derivation route buys its eval-time saving with, and it is the first thing to
    # measure if `nix flake check` gets slower.
    lib.checks.agentsMdCitations = import ./agents-md-citations.nix;

    # A source root again, plus the flake's own evaluated `testsError` — the one input the reader
    # cannot produce from text. Published for the same non-mkCi consumer as its neighbours: the
    # hub reaches the harness gates through `lib.checks` and not the flake module, so this is the
    # only route by which it can be gated like every mkCi consumer once it wires the check. Today
    # the hub carries no `ci/tests-error.nix` and this check classifies its tree `no-plane`.
    lib.checks.ciPlaneCoverage = import ./ci-plane-coverage.nix;

    # The self-input invariant, published for its SCANNER as much as for its check. The derivation
    # carries `passthru.scanner` — the predicate as a script, which `relock` below execs over a
    # lock it has just written and which any instrument can drive over a tree with no flake around
    # it. Exposing `lib.relock` without this one would publish a function no consumer could call:
    # `relock` takes the scanner rather than building its own, because the check and the command
    # must run ONE predicate and two constructions of it drift.
    lib.checks.ciSelfInput = import ./ci-self-input.nix;

    # ★ THE TWO-ACT LOCK BUMP, PUBLISHED AS A BUILDER RATHER THAN AS A DEVSHELL ENTRY. Every mkCi
    # consumer gets `relock` through `flakeModule.nix`, which is the ordinary route and is
    # unchanged. The hub is the case this exists for: it is legitimately NOT an mkCi consumer — it
    # exposes flake checks and a perf app rather than a nix-unit `tests` output, so it cannot take
    # the module — and it already wires its own devshell from `lib.checks.*` à la carte. Without a
    # published builder the one command that mutates locks in every member's repository was the
    # only harness surface the hub could not reach.
    #
    # `{ pkgs, name, scanner }` -> the command derivation. `flakeModule.nix` imports the same file
    # for its devshell entry; Nix caches `import` by path, so the module's `relock` and this one
    # are the SAME value in any evaluation that reaches both — the module cannot drift from the
    # published surface by construction rather than by discipline.
    lib.relock = import ./relock.nix;

    # ★ THE BATCH ASSERTER'S FAILURE MESSAGE, PUBLISHED BECAUSE IT IS OTHERWISE UNREACHABLE EXCEPT
    # BY FAILING. `flakeModule.nix` calls it on one arm — the arm where a cell has already failed
    # — so the only value it was ever read at was a value that had already taken `checks.default`
    # down, and a defect in it was invisible to every green. It HAD one, and the cost is recorded
    # in `fail-message.nix`. Called, it is `{ lib }` -> suite -> testName -> cell -> string, and
    # this repository's own suite holds it at the value class that used to abort it.
    lib.failMessage = import ./fail-message.nix;

    # `{ names, plugins }` — the membership fact and the `programs.mdformat.plugins` value built
    # from it. Both are published because a consumer that installs the set must also be able to
    # hand its names to the guard, and deriving them at the call site would be a second
    # statement of the membership.
    lib.mdformatBasePlugins = import ./mdformat-plugins.nix;
  };
}
