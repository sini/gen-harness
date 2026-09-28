# A consumer with suites and NO error plane: its `checks` must not name `tests-error`.
{
  flake.tests.fixture.test-one = {
    expr = 1;
    expected = 1;
  };
}
