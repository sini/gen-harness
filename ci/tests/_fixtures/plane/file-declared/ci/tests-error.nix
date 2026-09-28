# The file-and-cells declarer, the usual shape: its cells are written in `ci/tests-error.nix`.
# The CONTROL for the cells-only fixture beside it.

{
  flake.testsError.fixture.test-throws = {
    expr = throw "fixture";
    expectedError = {
      type = "ThrownError";
      msg = "fixture";
    };
  };
}
