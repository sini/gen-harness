# THE HARNESS DECLARES NO GEN LIBRARY INPUT.
#
# This is the property the repository exists to hold: a library's test harness must not pull the
# aggregator that pins the library, and it must not pull a library its consumer also pins, or the
# consumer evaluates two builds of one library.
#
# TWO SUBJECTS HERE, AND THEY TAKE DIFFERENT SOURCES. The closure cells ask what a consumer's copy
# of this dependency set CONTAINS; an input reached transitively appears in no `.url` line, so only
# a lock expresses that and the lock is properly their subject. The tool-set cell asks what this
# repository DECLARES, which is a fact about `flake.nix` — a lock records what resolution PRODUCED,
# and the two can differ. Reading the lock for it let a CI artefact set the population of a check
# on the library; ci exists in service of the libraries, so that one reads the declaration.
#
# Both are read by relative path rather than through the `root` input: the input's copy is a
# snapshot taken when ci's lock was last updated, so an input added to the root flake today would
# be invisible to a suite reading the snapshot until someone advanced the pin. The scan must see
# the tree it is run on.
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

  # The header's second subject: what the root flake DECLARES. `import` rather than a text scan —
  # the declaration is an expression, and `attrNames` over it is the whole statement.
  toolInputs = lib.sort (a: b: a < b) (lib.attrNames (import ../../flake.nix).inputs);
in
{
  flake.tests.no-gen-inputs = {
    test-root-lock-carries-no-gen-library = {
      expr = genRepos rootLock;
      expected = [ ];
    };

    # CONTROL, same predicate, same run — the scan can fire. ci's own lock holds the agreement
    # test's gen-prelude pin plus the cross-library integration suites' own siblings (gen-dispatch,
    # gen-select) and whatever those siblings pin transitively (gen-select's gen-algebra,
    # gen-dispatch's own gen-prelude — a second node with the same `repo`, not deduped here for
    # that reason). None of this lives anywhere consumers pin: it is in the flake they do not pin,
    # so no consumer's lock inherits it.
    test-control-ci-lock-carries-its-cross-lib-inputs = {
      expr = genRepos ciLock;
      expected = [
        "gen-algebra"
        "gen-dispatch"
        "gen-prelude"
        "gen-prelude"
        "gen-select"
      ];
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
