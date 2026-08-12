# THE SECOND TEST OUTPUT — the cell whose subject is a RAISE, and the runner that reads it.
#
# The vendored escape set carries `]`, which nixpkgs' does not. Escaping it yields `\]`, and the
# regex engine rejects that outright, so `hasInfix` with a `]` anywhere in the needle raises instead
# of answering — for the copy and for the original alike. That deviation is not a gap in the copy,
# it IS the copy being faithful, and it stays measured rather than skipped: if the original is ever
# corrected, this cell is what notices, because a call that starts answering stops raising.
#
# `builtins.tryEval` does not catch this class — it catches thrown errors and failed assertions, not
# an evaluation error from a rejected regex — so the only assertion available is nix-unit's
# `expectedError`.
#
# ★ WHY A SECOND OUTPUT RATHER THAN A CELL IN `flake.tests`. The batch asserter behind
# `checks.default` (../flakeModule.nix) evaluates `expr == expected` unconditionally and quantifies
# over `flake.tests` and nothing else. A cell with no `expected` and a raising `expr` therefore
# CRASHES that gate rather than failing a cell. Hosting it on `flake.testsError` puts it outside
# that quantifier while keeping it live on the nix-unit path. The split is structural, not
# conventional: this file is not under `./tests`, which is the whole of `testModules`, so nothing
# depends on a filter predicate or a naming habit.
#
# BOTH OUTPUTS NEED RUNNING, so both get a hook. The `ci` hook the shared flake module builds bakes
# `./ci#tests` into its own text and cannot be pointed here; `ci-error` below is its counterpart.
#
#   nix-unit --flake ./ci#tests        # the suites
#   nix-unit --flake ./ci#testsError   # this cell
{
  lib,
  genPrelude,
  upstreamPrelude,
  genInputs,
  ...
}:
{
  # Same type as `flake.tests`: the same kind of thing, read by the same runner — only the
  # assertion the cells carry differs.
  options.flake.testsError = lib.mkOption {
    type = lib.types.lazyAttrsOf (lib.types.lazyAttrsOf lib.types.raw);
    default = { };
    description = "Test suites whose cells assert an ERROR: { suite.test = { expr; expectedError; }; }. Read by `nix-unit --flake ./ci#testsError`; deliberately outside `flake.tests`, which the batch asserter quantifies over.";
  };

  config = {
    flake.testsError.escape-set = {
      # The message is asserted, not merely the failure: a raise from some other cause would be a
      # different fact about the copy.
      test-close-bracket-raises = {
        expr = genPrelude.hasInfix "]" "a]b";
        expectedError = {
          type = "EvalError";
          msg = ".*invalid regular expression.*";
        };
      };

      # The original raises identically, which is what makes the deviation the original's rather
      # than the copy's. Drop `]` from either escape set and the corresponding cell stops raising.
      test-upstream-close-bracket-raises-identically = {
        expr = upstreamPrelude.hasInfix "]" "a]b";
        expectedError = {
          type = "EvalError";
          msg = ".*invalid regular expression.*";
        };
      };

      # LIVE CONTROL, same run: a needle without `]` answers rather than raising. Without it the
      # two cells above are consistent with a function that raises on everything. It is an
      # `expected` cell on an `expectedError` output deliberately — a control has to run in the
      # same invocation as the thing it controls.
      test-control-a-needle-without-it-answers = {
        expr = genPrelude.hasInfix "[a" "x[ay";
        expected = true;
      };
    };

    perSystem =
      { pkgs, system, ... }:
      {
        pre-commit.settings.hooks.ci-error = {
          enable = true;
          name = "ci-error";
          description = "Run nix-unit error-assertion tests";
          entry = "${
            pkgs.writeShellApplication {
              name = "gen-harness-ci-nix-unit-error";
              runtimeInputs = [ genInputs.nix-unit.packages.${system}.default ];
              text = ''
                exec nix-unit --flake ./ci#testsError "$@"
              '';
            }
          }/bin/gen-harness-ci-nix-unit-error";
          files = "\\.nix$";
          pass_filenames = false;
        };
      };
  };
}
