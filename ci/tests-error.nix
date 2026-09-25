# THE SECOND TEST OUTPUT — the cells whose `expr` CAN ABORT, and the runner that reads them.
#
# `]` is the one character whose escape-set membership decides whether `hasInfix` answers at all.
# Outside a bracket expression it is already literal, so escaping it yields `\]`, which the regex
# engine rejects outright: a set carrying `]` aborts on every `]`-bearing needle, and a set without
# it returns the same boolean nixpkgs does. Neither the vendored copy (../prelude.nix) nor
# gen-prelude carries it, so both ANSWER, and the cells below assert that answer against a stated
# value. Put `]` back into either set and the corresponding call stops answering and aborts.
#
# `builtins.tryEval` does not catch that class — it catches thrown errors and failed assertions, not
# an evaluation error from a rejected regex — so nix-unit's `expectedError` is the only assertion
# that could hold such an abort, and these are the cells that would need it.
#
# ★ WHY A SECOND OUTPUT RATHER THAN CELLS IN `flake.tests`. The batch asserter behind
# `checks.default` (../flakeModule.nix) evaluates `expr == expected` unconditionally and quantifies
# over `flake.tests` and nothing else. An `expr` that aborts therefore CRASHES that gate rather than
# failing a cell — so a subject that CAN abort belongs outside that quantifier whether or not it is
# aborting today. Hosting these on `flake.testsError` keeps them live on the nix-unit path and makes
# a regression in either escape set fail a cell instead of taking the gate down. The split is
# structural, not conventional: this file is not under `./tests`, which is the whole of
# `testModules`, so nothing depends on a filter predicate or a naming habit.
#
# BOTH OUTPUTS NEED RUNNING, so both get a hook — and the shared flake module (../flakeModule.nix)
# wires both, beside each other, off the same read-roots guard. `ci` bakes `./ci#tests` into its own
# text and cannot be pointed here; `ci-error` is its counterpart and this file supplies only its
# cells. The option and the hook were stated here once, in ten repositories at once, and drifted.
#
#   nix-unit --flake ./ci#tests        # the suites
#   nix-unit --flake ./ci#testsError   # these cells
{
  lib,
  inputs,
  genPrelude,
  upstreamPrelude,
  ...
}:
let
  # `checks.root-surface`'s REFUSAL arms, each pinned to its message under the column's own
  # evaluator. The green arms are `tests/root-surface.nix`. `pkgs` is a stub: every arm here refuses
  # at evaluation, before anything would be built.
  rsCheck =
    args:
    inputs.gen-harness.lib.checks.rootSurface (
      {
        pkgs.runCommand =
          n: _: _:
          n;
        name = "fx";
      }
      // args
    );
  fx = ./tests/_fixtures/root-surface;
  refuses = args: msg: {
    expr = rsCheck args;
    expectedError = {
      type = "ThrownError";
      msg = lib.escapeRegex msg;
    };
  };
  gone = "root-surface-fixture: `gone` is retired (use `live`).";
in
{
  config = {
    flake.testsError.root-surface = {
      test-a-top-level-published-name-that-throws-reds = refuses {
        root = fx + "/top-throw";
      } "root-surface-fixture: top-level";
      test-a-name-two-namespaces-down-that-throws-reds = refuses {
        root = fx + "/nested-throw";
      } "root-surface-fixture: nested";
      test-a-functor-set-is-a-namespace = refuses {
        root = fx + "/functor-throw";
      } "root-surface-fixture: functor member";
      test-an-undeclared-tombstone-reds-with-its-own-message = refuses {
        root = fx + "/tomb";
      } gone;
      test-a-retired-name-that-is-absent-is-refused = refuses {
        root = fx + "/tomb";
        retired.noSuchMember = "x";
      } "root-surface: declared retired but absent or no longer throwing: noSuchMember";
      test-a-retired-name-that-no-longer-throws-is-refused = refuses {
        root = fx + "/tomb";
        retired = {
          inherit gone;
          live = "x";
        };
      } "root-surface: declared retired but absent or no longer throwing: live";
      # den-hoag-ydm94 G3: the tombstone's message cell would be generated and never run.
      test-a-tombstone-without-an-error-plane-is-refused = refuses {
        root = fx + "/top-throw";
        retired.broken = "root-surface-fixture: top-level";
      } "root-surface: declares retired names (broken) but has no ci/tests-error.nix";
      test-owed-without-a-root-entry-is-a-named-refusal = refuses {
        root = fx;
      } "root-surface: owed (the default) but the root has no default.nix";
      test-not-owed-over-a-root-entry-is-refused = refuses {
        root = fx + "/set-root";
        entry = "not-owed";
      } "root-surface: declared not-owed but the root has a default.nix";
      test-not-owed-with-retired-names-is-refused = refuses {
        root = fx;
        entry = "not-owed";
        retired.gone = gone;
      } "root-surface: declared not-owed but declares retired names (gone)";
      test-an-undeclared-entry-value-is-refused = refuses {
        root = fx;
        entry = "maybe";
      } "root-surface: `entry` must be \"owed\" or \"not-owed\"";
    };

    # The flake module's generated tombstone suite, over the fixture: the message is the one the
    # root throws, so the cell PASSES; resurrecting `gone` to throw anything else fails it.
    flake.testsError.root-surface-retired-fixture = (import ../root-surface.nix).retiredCells {
      inherit lib;
      root = fx + "/tomb";
      retired = { inherit gone; };
    };

    flake.testsError.escape-set = {
      # The answer is asserted, not merely the absence of an abort: `]` is passed through unescaped
      # and matched as the literal it already is, so the boolean is nixpkgs'.
      test-close-bracket-answers = {
        expr = genPrelude.hasInfix "]" "a]b";
        expected = true;
      };

      # The original answers identically, which is what makes the domain the original's rather than
      # the copy's. Put `]` into either escape set and exactly one of these two cells aborts, naming
      # which side moved.
      test-upstream-close-bracket-answers-identically = {
        expr = upstreamPrelude.hasInfix "]" "a]b";
        expected = true;
      };

      # LIVE CONTROL, same run: a `]` needle the haystack lacks answers false. Without it the two
      # cells above are satisfied by a predicate stuck at `true`, which is the vacuity an assertion
      # about a returned boolean invites and an assertion about an abort did not. A control has to
      # run in the same invocation as the thing it controls, so it stays on this output.
      test-control-a-missing-close-bracket-answers-false = {
        expr = genPrelude.hasInfix "]" "ab";
        expected = false;
      };
    };
  };
}
