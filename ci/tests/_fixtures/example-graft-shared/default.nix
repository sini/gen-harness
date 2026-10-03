# THE SHARED-NODE GRAFT FIXTURE — a parent tree whose own lock pins repositories the examples' hub
# pins too, and the graft over it through the `fetch` seam.
#
# NOT A SUITE: under `_fixtures/`, so reached only by `ci/tests/example-graft.nix` and
# `ci/tests-error.nix`. `tree/flake.lock` pins `graft-fixture-dep`, the `flake = false`
# `graft-fixture-data` and `graft-fixture-own`, all at date 200. Each `tree/examples/<dir>` lock
# reaches the parent through a hub whose `dep` sits at another date (`lead` older, `trail` newer,
# `tie` the same date at another revision, `same-rev` the parent's own revision). In `lead` the parent
# node follows the hub's `dep` and `data` and keeps its own `own`, at a newer date on the hub's side.
# `tree-split/flake.lock` pins `graft-fixture-dep` twice. Every node is fictitious: the stub fetcher
# maps each planned revision to a source under `srcs/` and throws on any other, so a node a cell did
# not plan for is a red, never a fetch.
{ lib }:
let
  rev = c: lib.concatStrings (lib.replicate 40 c);
  srcs = {
    ${rev "9"} = "hub";
    ${rev "a"} = "dep-a";
    ${rev "b"} = "dep-b";
    ${rev "c"} = "data-a";
    ${rev "d"} = "data-b";
    ${rev "e"} = "own-a";
    ${rev "f"} = "own-b";
  };
  fetch = l: {
    outPath =
      ./srcs + "/${srcs.${l.rev} or (throw "example-graft-shared: unplanned revision ${l.rev}")}";
    inherit (l) rev;
  };
in
{
  inherit rev;
  graft =
    tree: dir:
    import ../../../../example-graft.nix {
      root = ./. + "/${tree}";
      name = "graft-fixture-parent";
      inherit dir fetch;
    };
}
