# Wires the `relock` behaviour oracle into THIS repository's checks and no consumer's.
#
# It belongs here rather than in `flakeModule.nix` because its subject is the HARNESS, not the
# member: `ci-self-input` runs in all 31 consumers because it reads each consumer's own lock, while
# this one drives synthetic trees and would be the same build repeated 31 times.
#
# ★ IT REACHES THE COMMAND THROUGH THE PUBLISHED SURFACE — `lib.relock` applied to
# `lib.checks.ciSelfInput`'s `passthru.scanner` — and never through a file path. That is the third
# consumer of one definition, and it is what makes this cell possible at all: until those two names
# were published, the command was bound inside `flakeModule.nix` and a cell had nothing to name
# (`den-hoag-ecfua`). It also means a rename of either published name breaks this repository's own
# gate, which is the coupling `flake.nix`'s `lib.checks` comment asks for.
{ inputs, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      # DERIVED and synthetic: a fixture identity that cannot be a real repository, so no arm can
      # invert in some member the way `ci-self-input.nix`'s hardcoded `clean-siblings` did.
      fixtureName = "gen-harness-relock-fixture";
    in
    {
      checks.relock-behaviour = import ../relock-behaviour.nix {
        inherit pkgs fixtureName;
        name = "gen-harness";
        relock = inputs.gen-harness.lib.relock {
          inherit pkgs;
          name = fixtureName;
          inherit
            (inputs.gen-harness.lib.checks.ciSelfInput {
              inherit pkgs;
              name = fixtureName;
              root = inputs.gen-harness.sourceInfo.outPath;
            })
            scanner
            ;
        };
      };
    };
}
