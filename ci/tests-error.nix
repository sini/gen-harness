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
  genPrelude,
  upstreamPrelude,
  ...
}:
{
  config = {
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
