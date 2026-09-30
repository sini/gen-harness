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
      test-a-foreign-declaration-at-an-absent-path-is-refused = refuses {
        root = fx + "/foreign-root";
        foreign = {
          "engine.lib" = "x";
          "engine.nope" = "x";
        };
      } "root-surface: declared foreign but the walk never reached a namespace there: engine.nope";
      test-a-foreign-declaration-at-a-leaf-is-refused = refuses {
        root = fx + "/foreign-root";
        foreign = {
          "engine.lib" = "x";
          "own.x" = "x";
        };
      } "root-surface: declared foreign but the walk never reached a namespace there: own.x";
      test-a-foreign-declaration-under-a-declared-root-is-refused = refuses {
        root = fx + "/foreign-root";
        foreign = {
          "engine.lib" = "x";
          "engine.lib.types" = "x";
        };
      } "root-surface: declared foreign but the walk never reached a namespace there: engine.lib.types";
      # The nested path's declaration does not silence the own name `"engine.lib"`, which renders
      # the same unquoted: its throw is still reached.
      test-a-nested-path-key-does-not-declare-an-own-dotted-name = refuses {
        root = fx + "/dotted-name";
        foreign."engine.lib" = "x";
      } "root-surface-fixture: an own name containing a dot";
      test-not-owed-with-foreign-roots-is-refused =
        refuses
          {
            root = fx;
            entry = "not-owed";
            foreign."engine.lib" = "x";
          }
          "root-surface: declared not-owed but declares foreign roots (engine.lib); a not-owed root publishes no names";
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
      inputs = { };
    };
    flake.testsError.root-surface-retired-shim = (import ../root-surface.nix).retiredCells {
      inherit lib;
      root = fx + "/tomb-shim";
      retired = { inherit gone; };
      inputs.dep-a.lib = { };
    };
    flake.testsError.root-surface-retired-shim-closed = {
      test-an-absent-dependency-is-refused-not-fetched = {
        expr =
          ((import ../root-surface.nix).retiredCells {
            inherit lib;
            root = fx + "/tomb-shim";
            retired = { inherit gone; };
            inputs = { };
          }).test-retired-gone.expr;
        expectedError = {
          type = "ThrownError";
          msg = "root-surface: a retired-name cell resolves the root's dependencies from ./ci's inputs and never fetches; `dep-a` is not an input of ./ci";
        };
      };
    };

    # A root whose formals carry no `src` cannot be closed: refused by name, even with every
    # dependency in the bag, never left to fetch.
    flake.testsError.root-surface-retired-nosrc = {
      test-a-root-without-a-src-formal-is-refused = {
        expr =
          ((import ../root-surface.nix).retiredCells {
            inherit lib;
            root = fx + "/tomb-nosrc";
            retired = { inherit gone; };
            inputs.dep-a.lib = { };
          }).test-retired-gone.expr;
        expectedError = {
          type = "ThrownError";
          msg = lib.escapeRegex "root-surface: the root takes formals (a, inputs) and no `src`; a retired-name cell closes fetching through the root's `src` formal";
        };
      };
    };

    # `checks.tests-error`'s refusals under a rebind: the in-memory override refusal still reads
    # every direct edge, rebound or not, and a name with no pin in the rebind lock is named. The
    # green arms are `tests/error-plane-rebind.nix`.
    flake.testsError.error-plane-rebind =
      let
        fx = import ./tests/_fixtures/error-plane-rebind {
          inherit lib;
          inherit (inputs) gen-harness;
        };
        refusesWith = inputs': names: msg: {
          expr = fx.check inputs' names;
          expectedError = {
            type = "ThrownError";
            msg = lib.escapeRegex msg;
          };
        };
      in
      {
        test-an-unrebound-input-diverged-in-memory-is-refused = refusesWith (
          fx.coherent // { tool = fx.pin "7" "sha256-C"; }
        ) fx.names "error plane: `tool` is overridden in memory";
        # The declarer's own pin for a rebound name disagrees with the grafted file node.
        test-a-rebound-input-at-another-pin-in-memory-is-refused =
          refusesWith (fx.coherent // { gen-x = fx.pin "1" "sha256-A"; }) fx.names
            "error plane: `gen-x` is overridden in memory, and the error plane evaluates ci/flake.lock as written with its rebound root edges grafted onto the caller's rebind lock";
        test-a-name-the-rebind-lock-root-lacks-is-refused = refusesWith fx.coherent [
          "gen-x"
          "gen-q"
        ] "error plane: rebind names `gen-q`, which the rebind lock's root does not declare";
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
