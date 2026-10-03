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

  # The shared-node fixture, offline through the `fetch` seam.
  sx = import ./_fixtures/example-graft-shared { inherit lib; };
  at = dir: (sx.graft "tree" dir).flake;
  depPin = lockFile: {
    inherit ((lib.importJSON lockFile).nodes.dep.locked) rev lastModified;
  };

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
    # A repository the example lock unifies and the parent pins is ONE node, at the newer pin by
    # `lastModified`: the parent's when it leads, the hub's when the parent trails, the parent's on a
    # tie. `oneValue` holds only for one value (the dep carries a lambda).
    test-a-leading-parents-shared-dependency-is-one-node-at-the-parents-pin = {
      expr = {
        inherit (at "lead") hubDep parentDep oneValue;
      };
      expected = {
        hubDep = "a";
        parentDep = "a";
        oneValue = true;
      };
    };
    test-a-trailing-parents-shared-dependency-is-one-node-at-the-hubs-pin = {
      expr = {
        inherit (at "trail") hubDep parentDep oneValue;
      };
      expected = {
        hubDep = "b";
        parentDep = "b";
        oneValue = true;
      };
    };
    test-two-pins-at-one-date-resolve-to-the-parents = {
      expr = {
        inherit (at "tie") hubDep parentDep oneValue;
      };
      expected = {
        hubDep = "a";
        parentDep = "a";
        oneValue = true;
      };
    };
    test-two-nodes-at-one-revision-are-one-value = {
      expr = (at "same-rev").oneValue;
      expected = true;
    };
    test-control-the-example-locks-date-the-hubs-dependency-around-the-parents = {
      expr =
        lib.genAttrs [ "lead" "trail" "tie" "same-rev" ] (
          d: depPin (./_fixtures/example-graft-shared/tree/examples + "/${d}/flake.lock")
        )
        // {
          parent = depPin ./_fixtures/example-graft-shared/tree/flake.lock;
        };
      expected = {
        lead = {
          rev = sx.rev "b";
          lastModified = 100;
        };
        trail = {
          rev = sx.rev "b";
          lastModified = 300;
        };
        tie = {
          rev = sx.rev "b";
          lastModified = 200;
        };
        same-rev = {
          rev = sx.rev "a";
          lastModified = 200;
        };
        parent = {
          rev = sx.rev "a";
          lastModified = 200;
        };
      };
    };

    # A `flake = false` shared node is one source: the edge takes the chosen node's source.
    test-a-flake-false-shared-node-is-one-source = {
      expr = {
        inherit (at "lead") hubData parentData;
      };
      expected = {
        hubData = "a";
        parentData = "a";
      };
    };

    # Sharing is read off the example lock's `follows`, not the owner: `graft-fixture-data` is
    # another owner's and is shared; `graft-fixture-own`, which the parent pins but the example's
    # parent node does not follow, keeps two nodes as it will publish, though the hub's is newer.
    test-the-shared-repositories-are-the-ones-the-example-lock-follows = {
      expr = lib.sort lib.lessThan (sx.graft "tree" "lead").shared;
      expected = [
        "graft-fixture-data"
        "graft-fixture-dep"
        "graft-fixture-parent"
      ];
    };
    test-a-repository-the-example-lock-does-not-unify-keeps-two-nodes = {
      expr = {
        inherit (at "lead") hubOwn parentOwn;
      };
      expected = {
        hubOwn = "b";
        parentOwn = "a";
      };
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
