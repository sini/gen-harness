# THIS REPOSITORY'S PROCESS PLANE: the `relock` behaviour oracle, as `apps.<system>.tests-process`,
# and no consumer's.
#
# It belongs here rather than in `flakeModule.nix` because its subject is the HARNESS, not the
# member: `ci-self-input` runs in all 31 consumers because it reads each consumer's own lock, while
# this one drives synthetic trees and would be the same run repeated 31 times.
#
# ★ A PROGRAM, NOT A CHECK (den-hoag-348bq). Three of its arms compute their verdict through the
# caller's `nix`, so they are evidence only for the evaluator that ran them. As a flake check the
# evaluator was the ci-locked `pkgs.nix` — one drvPath, one verdict, in every `evaluators.yml`
# column. As this program they run under the `nix` on PATH, through `ci --tests-process`, which is
# the same command in each column and on the owner's host (bare `ci` runs no process plane).
# `../relock-behaviour.nix` states how the program stays hermetic out of the sandbox.
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
      apps.tests-process.meta.description = "the relock behaviour arms, under the nix on PATH, in a network namespace of their own";
      apps.tests-process.program = import ../relock-behaviour.nix {
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
