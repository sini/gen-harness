# The same consumer with one error-plane cell: its `checks` must name `tests-error`.
{
  flake.tests.fixture.test-one = {
    expr = 1;
    expected = 1;
  };
  flake.testsError.fixture.test-throws = {
    expr = throw "fixture";
    expectedError = {
      type = "ThrownError";
      msg = "fixture";
    };
  };
}
