# `checks.root-surface`'s GREEN arms, through the published builder `lib.checks.rootSurface`.
#
# The builder's green value is `pkgs.runCommand`'s, so `pkgs` is a stub returning the derivation's
# NAME: the verdict is decided at evaluation, before anything is built, and that is the unit held
# here. The refusal arms abort, so they live on `ci/tests-error.nix`, each pinned to its message.
{ inputs, ... }:
let
  pkgs.runCommand =
    n: _: _:
    n;
  check =
    args:
    inputs.gen-harness.lib.checks.rootSurface (
      {
        inherit pkgs;
        name = "fx";
      }
      // args
    );
  fx = ./_fixtures/root-surface;
in
{
  flake.tests.root-surface = {
    # A SET root is the surface itself; calling it (`import p { }`) would abort.
    test-a-set-root-is-walked-without-being-called = {
      expr = check { root = fx + "/set-root"; };
      expected = "fx-root-surface";
    };

    # Every leaf class carries a throwing field that is not a published name: green only if the
    # walk stops at a `_type`-tagged value, a derivation and a list's elements.
    test-a-lambda-root-stops-at-typed-derivation-and-list-leaves = {
      expr = check { root = fx + "/lambda-root"; };
      expected = "fx-root-surface";
    };

    # LIVE CONTROL for the cell above: the same builder over a root whose throw sits two plain
    # namespaces down refuses. Without it the cell above is satisfied by a walk that descends nowhere.
    test-control-a-plain-namespace-is-descended-into = {
      expr =
        (builtins.tryEval (
          inputs.gen-harness.lib.checks.rootSurface {
            inherit pkgs;
            name = "fx";
            root = fx + "/nested-throw";
          }
        )).success;
      expected = false;
    };

    test-a-declared-tombstone-is-excluded = {
      expr = check {
        root = fx + "/tomb";
        retired.gone = "root-surface-fixture: `gone` is retired (use `live`).";
      };
      expected = "fx-root-surface";
    };

    test-not-owed-holds-at-a-root-with-no-default-nix = {
      expr = check {
        root = fx;
        entry = "not-owed";
      };
      expected = "fx-root-surface";
    };
  };
}
