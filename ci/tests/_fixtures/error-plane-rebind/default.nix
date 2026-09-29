# THE REBIND FIXTURE — a declarer (`ci/flake.lock` here) and a rebind lock to graft it onto.
#
# NOT A SUITE: under `_fixtures/`, so reached only by `ci/tests/error-plane-rebind.nix` and
# `ci/tests-error.nix`. The declarer's `fixture` node pins its own `gen-x` (`gen-x_2`) under a
# name that is not rebound, the frozen-fixture shape. The rebind lock declares `gen-z` as a root
# `follows` and `gen-x`'s `gen-y` as a nested one. Every `github` node is fictitious: nothing here
# may reach a fetch, and `pkgs.runCommand` is a stub returning the check's name.
{ lib, gen-harness }:
rec {
  root = ./.;
  own = builtins.fromJSON (builtins.readFile ./ci/flake.lock);
  hub = {
    version = 7;
    root = "root";
    nodes = {
      root.inputs = {
        gen-x = "gen-x";
        gen-y = "gen-y";
        gen-w = "gen-y";
        gen-z = [ "gen-x" ];
      };
      gen-x = {
        locked = {
          type = "github";
          owner = "o";
          repo = "gen-x";
          rev = "9";
          narHash = "sha256-Z";
        };
        inputs.gen-y = [ "gen-y" ];
      };
      gen-y.locked = {
        type = "github";
        owner = "o";
        repo = "gen-y";
        rev = "8";
        narHash = "sha256-Y";
      };
    };
  };
  names = [
    "gen-x"
    "gen-y"
    "gen-z"
  ];
  graft =
    names:
    import ../../../../error-plane-rebind.nix {
      inherit lib;
      lock = own;
      rebind = {
        lock = hub;
        inherit names;
      };
    };
  pin = rev: narHash: { inherit rev narHash; };
  # The hub's pins for the rebound names, the declarer's own for the rest: the caller's shape.
  coherent = {
    gen-x = pin "9" "sha256-Z";
    gen-y = pin "8" "sha256-Y";
    gen-z = pin "9" "sha256-Z";
    tool = pin "3" "sha256-C";
    fixture = pin "4" "sha256-D";
  };
  check =
    inputs: names:
    gen-harness.lib.checks.errorPlane {
      pkgs.runCommand =
        n: _: _:
        n;
      inherit lib root inputs;
      name = "fx";
      system = "x86_64-linux";
      rebind = {
        lock = hub;
        inherit names;
      };
    };
}
