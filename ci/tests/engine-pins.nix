# THE ERROR PLANE'S ENGINES ARE THE COLUMNS' PINNED EVALUATORS (den-hoag-o7kjc).
#
# `checks.tests-error` builds its family's engine from a flake input of the harness, and
# `evaluators.yml` installs each column's evaluator from a version pin. The `evaluator identity` step
# holds the running binary equal to its pin and to the engine's store path, in CI; this cell holds
# the two SOURCES equal, on every run: each `evaluators.yml` pin is its engine input's version. A pin
# bump without the input bump (or the reverse) reds here, not in a column.
{ lib, genInputs, ... }:
let
  ev = import ../../error-plane-engines.nix {
    inherit lib genInputs;
    system = "x86_64-linux";
  };
in
{
  flake.tests.engine-pins = {
    test-every-evaluator-pin-is-its-engine-inputs-version = {
      expr = ev.disagreements ev.yml;
      expected = [ ];
    };
    # CONTROL, same reader, same run: a moved pin is seen, and named.
    test-control-a-moved-pin-is-seen = {
      expr = ev.disagreements (
        builtins.replaceStrings [ ''NIX_VERSION: "'' ] [ ''NIX_VERSION: "9.'' ] ev.yml
      );
      expected = [
        "nix: evaluators.yml NIX_VERSION 9.${ev.engines.nix.pkg.version} vs engine input ${ev.engines.nix.pkg.version}"
      ];
    };
  };
}
