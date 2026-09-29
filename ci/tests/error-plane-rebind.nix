# THE REBIND GRAFTS ROOT EDGES AND NOTHING ELSE (`error-plane-rebind.nix`).
#
# The green arms, over `_fixtures/error-plane-rebind`: which edges move, what a moved edge points
# at, and which stay where the declarer's lock put them. The refusals are `ci/tests-error.nix`.
{ inputs, lib, ... }:
let
  fx = import ./_fixtures/error-plane-rebind {
    inherit lib;
    inherit (inputs) gen-harness;
  };
  grafted = fx.graft fx.names;
  rootOf = l: l.nodes.${l.root}.inputs;
in
{
  flake.tests.error-plane-rebind = {
    test-no-rebind-is-the-lock-as-written = {
      expr =
        import ../../error-plane-rebind.nix {
          inherit lib;
          lock = fx.own;
          rebind = null;
        } == fx.own;
      expected = true;
    };
    test-a-rebound-root-edge-points-at-the-rebind-locks-node = {
      expr = (rootOf grafted).gen-x;
      expected = "rebind:gen-x";
    };
    # A `follows` is a path from its own file's root; read from the declarer's root it would dangle.
    test-a-nested-follows-resolves-from-the-rebind-locks-root = {
      expr = grafted.nodes."rebind:gen-x".inputs.gen-y;
      expected = "rebind:gen-y";
    };
    test-a-root-follows-in-the-rebind-lock-resolves-to-its-node = {
      expr = (rootOf grafted).gen-z;
      expected = "rebind:gen-x";
    };
    test-an-unnamed-root-edge-keeps-the-declarers-pin = {
      expr = (rootOf grafted).tool;
      expected = "tool";
    };
    # The frozen fixture: `gen-x` is a rebound NAME, but this edge is beneath an edge that is not.
    test-an-edge-beneath-an-unrebound-node-is-left-alone = {
      expr = grafted.nodes.fixture.inputs.gen-x;
      expected = "gen-x_2";
    };
    test-a-name-the-declarer-lacks-adds-no-edge = {
      expr = (rootOf (fx.graft [ "gen-w" ])) ? gen-w;
      expected = false;
    };
    test-the-rebind-lock-root-lacking-a-name-is-catchable = {
      expr = (builtins.tryEval (builtins.deepSeq (fx.graft [ "gen-q" ]) null)).success;
      expected = false;
    };
    # The caller hands the rebind lock's pins for the rebound names: the refusal reads the graft and
    # finds nothing overridden. `pkgs.runCommand` is the fixture's stub, so the value is the name.
    test-the-rebind-locks-pins-in-memory-are-not-refused = {
      expr = fx.check fx.coherent fx.names;
      expected = "fx-tests-error";
    };
  };
}
