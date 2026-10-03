# Every example's outputs: each read names the hub's copy and the parent's. `oneValue` is `==` over
# flakes carrying a lambda, so it holds only when both are one value, never for two folds of one source.
inputs:
let
  inherit (inputs) hub;
in
{
  hubDep = hub.dep.marker;
  parentDep = hub.parent.dep.marker;
  oneValue = hub.dep == hub.parent.dep;
  hubData = import (hub.data + "/marker.nix");
  parentData = import (hub.parent.data + "/marker.nix");
  hubOwn = hub.own.marker;
  parentOwn = hub.parent.own.marker;
}
