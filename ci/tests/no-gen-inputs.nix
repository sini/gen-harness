# THE HARNESS DECLARES NO GEN LIBRARY INPUT — read from the lock, which is where a consumer's
# copy of this dependency set comes from.
#
# This is the property the repository exists to hold: a library's test harness must not pull the
# aggregator that pins the library, and it must not pull a library its consumer also pins, or the
# consumer evaluates two builds of one library. Flake text would be the weaker instrument — an
# input reached transitively appears in no `.url` line — so the subject is `flake.lock`'s node set.
#
# The locks are read by relative path rather than through the `root` input: the input's copy is a
# snapshot taken when ci's lock was last updated, so a gen input added to the root flake today
# would be invisible to a suite reading the snapshot until someone advanced the pin. The scan must
# see the tree it is run on.
{ lib, ... }:
let
  rootLock = builtins.fromJSON (builtins.readFile ../../flake.lock);
  ciLock = builtins.fromJSON (builtins.readFile ../flake.lock);

  # Repositories, not input names: an input may be called anything, and `locked.repo` is what was
  # actually fetched. The `root` node carries no `locked` at all.
  genRepos =
    lock:
    lib.sort (a: b: a < b) (
      lib.filter (r: lib.hasPrefix "gen-" r) (
        map (node: node.locked.repo or "") (lib.attrValues lock.nodes)
      )
    );

  toolInputs = lib.sort (a: b: a < b) (lib.attrNames rootLock.nodes.root.inputs);
in
{
  flake.tests.no-gen-inputs = {
    test-root-lock-carries-no-gen-library = {
      expr = genRepos rootLock;
      expected = [ ];
    };

    # CONTROL, same predicate, same run — the scan can fire. ci's own lock holds the agreement
    # test's gen-prelude pin, and that pin lives here and nowhere else: it is in the flake
    # consumers do not pin, so no consumer's lock inherits it.
    test-control-ci-lock-carries-gen-prelude = {
      expr = genRepos ciLock;
      expected = [ "gen-prelude" ];
    };

    # The tool set is enumerated because five of these are declared by NO consumer and reach every
    # consuming harness through mkCi's fallback. Dropping one does not degrade a consumer's suite;
    # it stops the suite evaluating. A new input added here without a reason is caught by the same
    # assertion.
    test-root-declares-exactly-the-tool-set = {
      expr = toolInputs;
      expected = [
        "devshell"
        "flake-parts"
        "flake-root"
        "git-hooks-nix"
        "import-tree"
        "nix-unit"
        "nixpkgs"
        "treefmt-nix"
      ];
    };
  };
}
