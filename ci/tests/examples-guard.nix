# The examples guard's generated cells (`../../examples-guard.nix`), each arm held at its verdict.
#
# A GREEN arm is the generated cell itself agreeing; a RED arm is the generated cell DISAGREEING, or
# its `expr` failing under `tryEval`, read here as a value so this suite stays green while showing
# the guard fires. `clean/` carries `examples/alpha`, `examples/beta` and a plain file the totality
# cell must not count; the fixture root itself carries no `examples/`.
{ lib, ... }:
let
  guard = import ../../examples-guard.nix { inherit lib; };
  fx = ./_fixtures/examples-guard;
  clean = fx + "/clean";

  holds = c: c.expr == c.expected;
  aborts = c: !(builtins.tryEval (builtins.deepSeq c.expr null)).success;
  suite =
    declared:
    guard.cells {
      root = clean;
      inherit declared;
    };

  bad = {
    expr = 1;
    expected = 2;
  };
  good = {
    expr = 1;
    expected = 1;
  };
in
{
  flake.tests.examples-guard = {
    test-a-complete-declaration-generates-cells-that-all-hold = {
      expr = lib.mapAttrs (_: holds) (suite {
        alpha.tests.test-good = good;
        beta.out = 1;
      });
      expected = {
        test-every-example-directory-is-declared = true;
        test-alpha-forces-under-deepSeq = true;
        test-alpha-every-leaf-holds = true;
        test-beta-forces-under-deepSeq = true;
        test-beta-every-leaf-holds = true;
      };
    };

    test-an-undeclared-directory-reds-totality = {
      expr = (suite { alpha = { }; }).test-every-example-directory-is-declared;
      expected = {
        expr = [
          "alpha"
          "beta"
        ];
        expected = [ "alpha" ];
      };
    };

    test-a-declaration-with-no-directory-reds-totality = {
      expr =
        (guard.cells {
          root = fx;
          declared.alpha = { };
        }).test-every-example-directory-is-declared;
      expected = {
        expr = [ ];
        expected = [ "alpha" ];
      };
    };

    test-no-examples-and-no-declaration-is-no-suite = {
      expr = guard.cells {
        root = fx;
        declared = { };
      };
      expected = { };
    };

    # The force reaches a nested throw; the control shows `seq` does not, so the cell is not
    # asserting on the spine.
    test-a-value-that-throws-reds-force = {
      expr = aborts (suite { alpha.out.inner = throw "seeded"; }).test-alpha-forces-under-deepSeq;
      expected = true;
    };
    test-control-seq-passes-the-same-value = {
      expr = (builtins.tryEval (builtins.seq { out.inner = throw "seeded"; } true)).success;
      expected = true;
    };

    # A disagreeing leaf is a value, so `deepSeq` passes it; only the leaves cell names it.
    test-a-disagreeing-leaf-passes-force-and-reds-leaves = {
      expr =
        let
          s = suite {
            alpha.tests = {
              test-bad = bad;
              test-good = good;
            };
          };
        in
        {
          force = holds s.test-alpha-forces-under-deepSeq;
          leaves = s.test-alpha-every-leaf-holds.expr;
        };
      expected = {
        force = true;
        leaves = [ "tests.test-bad" ];
      };
    };

    # An `expectedError` leaf is a correct example whose `expr` throws: neither cell fails it.
    test-an-expectedError-leaf-that-throws-holds = {
      expr = lib.mapAttrs (_: holds) (suite {
        alpha.tests.test-throws = {
          expr = throw "an example's documented error";
          expectedError.type = "ThrownError";
        };
        beta = { };
      });
      expected = {
        test-every-example-directory-is-declared = true;
        test-alpha-forces-under-deepSeq = true;
        test-alpha-every-leaf-holds = true;
        test-beta-forces-under-deepSeq = true;
        test-beta-every-leaf-holds = true;
      };
    };

    test-an-expectedError-leaf-that-does-not-throw-reds-leaves = {
      expr =
        (suite {
          alpha.tests.test-no-throw = {
            expr = 1;
            expectedError.type = "ThrownError";
          };
        }).test-alpha-every-leaf-holds.expr;
      expected = [ "tests.test-no-throw" ];
    };

    # `mkCi` adds `examples/` to the read roots exactly when the source carries it.
    test-the-read-root-is-added-only-where-examples-exists = {
      expr = {
        present = map toString (guard.readRoot clean);
        absent = guard.readRoot fx;
      };
      expected = {
        present = [ "${toString clean}/examples" ];
        absent = [ ];
      };
    };
  };
}
