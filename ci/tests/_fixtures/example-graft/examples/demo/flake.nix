# Reaches the fixture parent four ways (see flake.lock): a root `github` edge, a `github` node with
# an edge set of its own, a `git` URL, and a `flake = false` source. No node is fetched: every one
# of them is the parent, and the graft replaces each.
{
  inputs = {
    p.url = "github:sini/graft-fixture-parent";
    q.url = "github:sini/graft-fixture-parent/other";
    g.url = "git+https://example.org/x/graft-fixture-parent.git";
    src = {
      url = "github:sini/graft-fixture-parent";
      flake = false;
    };
  };
  outputs = i: {
    fromP = i.p.marker;
    fromQ = i.q.marker;
    fromG = i.g.marker;
    qInputs = builtins.attrNames i.q.inputs;
    srcIsFlake = i.src ? outputs;
    srcReadsTheTree = builtins.pathExists (i.src + "/examples/demo/flake.nix");
  };
}
