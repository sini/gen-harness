# mkCi — the CI flake every gen ecosystem library's test suite is built from.
#
# Called from this repository's root flake as:
#   lib.mkCi = import ./mkCi.nix { inherit inputs; };
#
# Consumers call it as:
#   gen-harness.lib.mkCi {
#     inherit inputs;
#     name = "gen-schema";
#     testModules = ./tests;
#     specialArgs = { inherit genSchema genAlgebra; };
#   };
{ inputs }:
let
  # The harness's own inputs — the tool declarations `resolve` falls back to, and the value
  # suites reach as `genInputs` (gen-graph's error-runner takes nix-unit from it). The name is
  # the established specialArgs contract and is kept for that reason.
  genInputs = inputs;
in
{
  inputs,
  name,
  testModules,
  # The paths this suite reads BESIDES its collection root, declared as data so the runner can
  # check them. A suite whose cells only read modules under `testModules` declares nothing:
  # the collection root is covered unconditionally.
  #
  # ★ CONCATENATED WITH `testModules`, NEVER DEFAULTED TO IT. Written `readRoots ? [ testModules ]`
  # this would be a Nix default, and a Nix default is REPLACED rather than extended — so the first
  # consumer to declare a root would drop the collection root out of the guard's coverage and
  # restore the very defect the guard exists for. Under the concatenation below there is no
  # declaration a consumer can write that removes it — but only because `readRootsRel` is
  # re-pinned AFTER `// specialArgs` in the specialArgs merge. Merged before it, a consumer
  # writing `specialArgs.readRootsRel` silently replaced the derived domain and disabled the
  # guard, which is this comment's own claim failing at a route the README documents.
  readRoots ? [ ],
  specialArgs ? { },
  extraModules ? [ ],
}:
let
  inherit (inputs.nixpkgs) lib;
  # Resolve a TOOL: prefer the consumer's if present, fall back to the harness's. A consumer
  # overriding nix-unit or treefmt-nix is a real and harmless case, so the branch stays for the
  # tools. There is no gen branch to fall back to — the harness declares no gen input, and the
  # one prelude function it needs is vendored below.
  resolve = name: if inputs ? ${name} then inputs.${name} else genInputs.${name};
  import-tree = import (resolve "import-tree");

  # The declared read domain, as worktree-relative pathspecs for the shell half of the guard.
  # Derived HERE, once, from the same values the harness hands `import-tree` and the cells —
  # a root the guard does not cover is then a root the suite cannot read.
  readRootsRel = import ./readroots.nix {
    inherit lib;
    sourceRoot = inputs.self.sourceInfo.outPath;
  } ([ testModules ] ++ readRoots);
in
(resolve "flake-parts").lib.mkFlake
  {
    inherit inputs;
    specialArgs = {
      inherit name genInputs readRootsRel;
      # Every test suite gets `genPrelude.hasInfix` — the backtracking-free substring test the
      # purity scans use (nixpkgs `lib.hasInfix` overflows the C stack on whole-file source
      # scans). THAT IS THE WHOLE SURFACE: this value carries one attribute and gains no others.
      # A suite needing more of the prelude supplies its own `genPrelude` here, from gen-prelude
      # at its own root, which is also how a consumer overrides this one.
      genPrelude = import ./prelude.nix;
    }
    // specialArgs
    // {
      inherit readRootsRel;
    };
  }
  {
    imports = [
      (resolve "treefmt-nix").flakeModule
      (resolve "devshell").flakeModule
      (resolve "flake-root").flakeModule
      (resolve "git-hooks-nix").flakeModule
      ./flakeModule.nix
      (import-tree testModules)
    ]
    ++ extraModules;
  }
