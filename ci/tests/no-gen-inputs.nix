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

  # Repositories, not input names: an input may be called anything, so the scan reads what was
  # actually FETCHED, whatever the fetcher. A forge node (`github`, `gitlab`, `sourcehut`) names it
  # in `locked.repo`; a `tarball`, `git`, `file` or `path` node only in `locked.url` / `locked.path`,
  # where the repository is a path segment (`…/sini/gen-x/archive/<rev>.tar.gz`,
  # `https://github.com/sini/gen-x.git`). The hub is `gen` itself, so the name test is `gen` OR
  # `gen-*`, never the prefix alone. The `root` node carries no `locked` at all.
  isGen = r: r == "gen" || lib.hasPrefix "gen-" r;
  fetched =
    locked:
    if locked ? repo then
      [ locked.repo ]
    else
      map (lib.removeSuffix ".git") (
        lib.splitString "/" (lib.head (lib.splitString "?" (locked.url or locked.path or "")))
      );
  genRepos =
    lock:
    lib.sort (a: b: a < b) (
      lib.concatMap (node: lib.take 1 (lib.filter isGen (fetched (node.locked or { })))) (
        lib.attrValues lock.nodes
      )
    );

  # A lock-shaped fixture for the scan's live control. Neither real lock may carry a gen node any
  # more, so the control cannot read one; this holds a row per source form the scan claims to see,
  # and rows it must not.
  fixtureLock = {
    root = "root";
    nodes = {
      root.inputs = { };
      # the same library twice, under a mangled label — counted per node, not deduped
      gen-x.locked = {
        type = "github";
        owner = "sini";
        repo = "gen-x";
      };
      gen-x_2.locked = {
        type = "github";
        owner = "sini";
        repo = "gen-x";
      };
      # the hub: `gen`, which a `gen-` prefix test misses — and the hub's ci pins this repository
      hub.locked = {
        type = "github";
        owner = "sini";
        repo = "gen";
      };
      hub-tarball.locked = {
        type = "tarball";
        url = "https://github.com/sini/gen/archive/0123456789abcdef.tar.gz";
      };
      tarball.locked = {
        type = "tarball";
        url = "https://api.flakehub.com/f/pinned/sini/gen-y/0.1.1%2Brev-0123/0123.tar.gz";
      };
      git.locked = {
        type = "git";
        url = "https://github.com/sini/gen-z.git?ref=main";
      };
      # not gen: a forge repo that only STARTS with "gen", and a tarball with no gen segment
      genx.locked = {
        type = "github";
        owner = "x";
        repo = "genx";
      };
      nixpkgs.locked = {
        type = "tarball";
        url = "https://releases.nixos.org/nixos/unstable/nixos-26.11pre1/nixexprs.tar.xz";
      };
    };
  };

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

    # ci's lock too: a gen input on the test plane is a REVISION CYCLE, because every member's ci
    # pins this repository (den-hoag-lock-currency-ruling-ez1yq).
    test-ci-lock-carries-no-gen-library = {
      expr = genRepos ciLock;
      expected = [ ];
    };

    # CONTROL, same predicate, same run — the scan can fire, on every source form it claims to see.
    test-control-the-scan-finds-gen-nodes = {
      expr = genRepos fixtureLock;
      expected = [
        "gen"
        "gen"
        "gen-x"
        "gen-x"
        "gen-y"
        "gen-z"
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
        "nix-determinate"
        "nix-lix"
        "nix-unit"
        "nix-upstream"
        "nixpkgs"
        "treefmt-nix"
      ];
    };
  };
}
