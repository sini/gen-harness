# The example graft (`../../example-graft.nix`) over `_fixtures/example-graft`, whose example lock
# reaches the fixture parent four ways. No node is fetched: a parent node the graft missed would
# reach `fetchTree` for a fictitious revision and abort, so every green here also says the graft
# reached it.
{ lib, ... }:
let
  fx = ./_fixtures/example-graft;
  name = "graft-fixture-parent";
  graft =
    dir:
    import ../../example-graft.nix {
      root = fx;
      inherit name dir;
    };
  demo = graft "demo";

  # The self-input scanner's seeds, through a `pkgs` stub: `passthru.seeds` is plain data, and the
  # stub's `runCommand` returns the attributes it was given so nothing is built.
  seeds =
    (import ../../ci-self-input.nix {
      pkgs = {
        inherit lib;
        jq = null;
        writeShellApplication = _: "scanner";
        writeText = n: _: n;
        runCommand =
          _: attrs: _:
          attrs;
      };
      inherit name;
      root = fx;
    }).passthru.seeds;
in
{
  flake.tests.example-graft = {
    test-every-parent-node-is-grafted-at-any-depth = {
      expr = lib.sort lib.lessThan demo.grafted;
      expected = [
        "g"
        "p"
        "q"
        "src"
      ];
    };

    # The fixture's `marker` comes from the tree; a published copy would have been fetched.
    test-the-grafted-flake-reads-the-tree = {
      expr = {
        inherit (demo.flake) fromP fromQ fromG;
      };
      expected = {
        fromP = "the-tree";
        fromQ = "the-tree";
        fromG = "the-tree";
      };
    };

    # `q` carries an edge set of its own in the example lock; as one value folded from the parent's
    # own lock (none here), its inputs are the parent's, not the example's.
    test-two-parent-nodes-with-distinct-edge-sets-are-one-value = {
      expr = demo.flake.qInputs;
      expected = [ ];
    };
    test-control-the-example-lock-gives-q-an-edge-set = {
      expr = builtins.attrNames (lib.importJSON (fx + "/examples/demo/flake.lock")).nodes.q.inputs;
      expected = [ "x" ];
    };

    test-a-flake-false-parent-node-is-the-tree-source = {
      expr = {
        inherit (demo.flake) srcIsFlake srcReadsTheTree;
      };
      expected = {
        srcIsFlake = false;
        srcReadsTheTree = true;
      };
    };

    test-a-path-node-is-refused = {
      expr = (builtins.tryEval (builtins.deepSeq (graft "pathy").flake.near null)).success;
      expected = false;
    };

    # The graft selects exactly the nodes the scanner refuses: per seed, some node is selected iff
    # the scanner's expectation is a refusal. `clean-self-path` is not selected (a `path` node names
    # no repository) and `self-flake-false` is (it becomes a source).
    test-the-node-predicate-agrees-with-the-scanner-seeds = {
      expr = map (s: {
        inherit (s) label;
        selected = lib.any demo.isParentNode (builtins.attrValues s.nodes);
      }) seeds;
      expected = map (s: {
        inherit (s) label;
        selected = s.expect == 1;
      }) seeds;
    };
    test-control-the-seeds-hold-both-verdicts = {
      expr = lib.sort lib.lessThan (lib.unique (map (s: s.expect) seeds));
      expected = [
        0
        1
      ];
    };
  };
}
