# gen-harness REPL — the harness's published surface in scope. Run: nix repl --impure --file ci/repl.nix
#
# `getFlake` on the repo root rather than a hand-wired import of the individual files: `mkCi` closes
# over this flake's `inputs` (mkCi.nix), so a hand-wired copy would be a different value from the one
# every consumer reaches through `root.lib.mkCi`. The same call supplies `pkgs`, which the three
# `lib.checks.*` builders take as their only argument — without it they are in scope but not callable,
# and the harness's own affordance is the ability to build one interactively.
let
  self = builtins.getFlake (toString ../.);
in
{
  genHarness = self.lib;
  inherit (self.inputs.nixpkgs) lib;
  pkgs = self.inputs.nixpkgs.legacyPackages.${builtins.currentSystem};
}
// self.lib
