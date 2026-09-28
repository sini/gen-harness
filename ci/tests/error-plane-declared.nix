# THE ERROR PLANE IS DECLARED BY ITS CELLS, and `evaluators.yml` reads that declaration (den-hoag-o7kjc).
#
# The unit is what `evaluator identity` computes: its own `--apply` expression, read out of the workflow
# file and applied to a fixture consumer's mkCi outputs. A store path means the step asserts that
# engine; `undeclared` means it asserts nothing. So a cell reds if the predicate moves back onto a file
# name, and also if the workflow's reading of the predicate stops discriminating.
#
# cells-only is gen-prelude's shape: cells from its suite files, no `ci/tests-error.nix`. Under the file
# probe its engine was never asserted. file-and-cells is the CONTROL: the usual declarer, a store path
# under either predicate. The file with no cells is the other half: the file alone declares nothing.
{ inputs, lib, ... }:
let
  wf = builtins.readFile ../../.github/workflows/evaluators.yml;
  parts = lib.splitString "--apply '" wf;
  apply =
    if builtins.length parts != 2 then
      throw "error-plane-declared: evaluators.yml carries ${
        toString (builtins.length parts - 1)
      } `--apply '` expressions, not the one `evaluator identity` reads"
    else
      import (
        builtins.toFile "evaluator-identity-apply.nix" (
          builtins.head (lib.splitString "'" (builtins.elemAt parts 1))
        )
      );

  outputsOf =
    dir:
    inputs.gen-harness.lib.mkCi {
      inputs = {
        inherit (inputs) nixpkgs gen-harness;
        self = {
          outPath = dir;
          sourceInfo.outPath = dir;
        };
      };
      name = "fixture";
      testModules = dir;
      extraModules = [ { gen.ci.rootSurface.entry = "not-owed"; } ];
    };
  asserts = dir: lib.hasPrefix builtins.storeDir (apply (outputsOf dir));
in
{
  flake.tests.error-plane-declared = {
    test-a-cells-only-declarer-has-its-engine-asserted = {
      expr = asserts ./_fixtures/plane/declared;
      expected = true;
    };
    test-a-non-declarer-has-no-engine-asserted = {
      expr = apply (outputsOf ./_fixtures/plane/none);
      expected = "undeclared";
    };
    test-a-plane-file-with-no-cells-declares-nothing = {
      expr = apply (outputsOf ./_fixtures/plane/file-only);
      expected = "undeclared";
    };
    # CONTROL, same reader, same run: the usual declarer.
    test-control-a-file-and-cells-declarer-has-its-engine-asserted = {
      expr = asserts ./_fixtures/plane/file-declared;
      expected = true;
    };
    # A ci flake that is not mkCi's (the hub) publishes no `errorPlane`, and the step says so.
    test-a-flake-without-the-output-is-named = {
      expr = apply { };
      expected = "no-output";
    };
    # The published output is the predicate itself, not a copy of it.
    test-the-published-declaration-is-the-predicate = {
      expr = map (d: (outputsOf d).errorPlane.declared) [
        ./_fixtures/plane/declared
        ./_fixtures/plane/none
        ./_fixtures/plane/file-only
        ./_fixtures/plane/file-declared
      ];
      expected = [
        true
        false
        false
        true
      ];
    };
  };
}
