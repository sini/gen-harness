# THE TOOL-AGREEMENT INVARIANT — this test plane declares and resolves the harness's tools exactly as
# the root flake does, which is what every consumer resolves.
#
# ★★ WHY IT EXISTS. `ci/flake.nix` reads the subject by relative path (`../flake.nix`), never as a
# `path:..` input, because Lix refuses that lock node (den-hoag-lbtnv D1). So the harness's tool
# inputs are DECLARED TWICE — once in `../../flake.nix`, which consumers resolve, and once in
# `../flake.nix`, which this suite resolves — and `relock` bumps each lock on its own terms. Nothing
# else sees the pair: an edit to a root declaration (a rev in a URL, a `follows`) left unmirrored
# moves the consumers' tool and not this suite's, and every other cell stays green while testing the
# harness against a tool no consumer gets. Measured by the gate before this cell existed: the root's
# `import-tree` set to another rev, a full `nix flake update --flake ./ci` left ci at the old one.
#
# TWO QUESTIONS, because either can drift alone:
#   · DECLARATION: ci's input declarations, restricted to the root's names, equal the root's —
#     total over source-text drift (a URL, a pinned rev, a `follows`).
#   · RESOLUTION: under each of those names, the two locks resolve the same revisions. Lock-level
#     drift converges under `relock`, but only once someone runs it; this says when they have not.
#
# ★ THE WALKER IS gen-merge's `ci/tests/_fixtures/lock-walk.nix`, COPIED BYTE-FOR-BYTE, as gen-merge
# copied it from gen-link: the question is the same one, and a second implementation of it would be
# a second thing to be wrong. It counts DISTINCT NODES reached under a label from `.root`, never lock
# keys, which carry the locker's `_2` suffixes.
{ lib, ... }:
let
  walkOf = lock: import ./_fixtures/lock-walk.nix { inherit lib lock; };

  rootDecl = (import ../../flake.nix).inputs;
  ciDecl = (import ../flake.nix).inputs;
  names = lib.attrNames rootDecl;

  rootLock = builtins.fromJSON (builtins.readFile ../../flake.lock);
  ciLock = builtins.fromJSON (builtins.readFile ../flake.lock);

  # The identity of a node: its `rev` where it has one, else its `narHash` (a tarball carries both,
  # a path neither — and no tool here is a path).
  identityOf = node: node.locked.rev or node.locked.narHash or "<unlocked>";

  revsUnder =
    lock: label:
    lib.unique (
      lib.sort (a: b: a < b) (map (k: identityOf lock.nodes.${k}) ((walkOf lock).distinctUnder label))
    );
  revsOf = lock: lib.genAttrs names (revsUnder lock);

  # ── SEEDS, in memory, changing nothing on disk ──
  # The declaration drift the gate drove: one root declaration moved, ci left.
  driftedDecl = ciDecl // {
    import-tree.url = "github:denful/import-tree/0000000000000000000000000000000000000000";
  };
  # The lock drift: ci's import-tree node moved to a revision the root does not carry.
  seedRev =
    lock:
    let
      node = builtins.head ((walkOf lock).distinctUnder "import-tree");
    in
    lock
    // {
      nodes = lock.nodes // {
        ${node} = lock.nodes.${node} // {
          locked = lock.nodes.${node}.locked // {
            rev = "0000000000000000000000000000000000000000";
          };
        };
      };
    };
in
{
  flake.tests.tool-agreement = {
    test-ci-declares-every-root-input-as-the-root-does = {
      expr = lib.getAttrs names ciDecl == rootDecl;
      expected = true;
    };

    test-both-locks-resolve-the-same-tool-revisions = {
      expr = revsOf ciLock == revsOf rootLock;
      expected = true;
    };

    # ★ EACH COMPARISON IS SHOWN ABLE TO FAIL, in the same run, on the shape it exists for.
    test-control-a-drifted-declaration-is-seen = {
      expr = lib.getAttrs names driftedDecl == rootDecl;
      expected = false;
    };
    test-control-a-drifted-lock-revision-is-seen = {
      expr = revsOf (seedRev ciLock) == revsOf rootLock;
      expected = false;
    };

    # ★ The comparison is not vacuous: every root input reaches at least one node in each lock. A
    # walk that reached nothing would compare `[ ]` with `[ ]` and agree for no reason.
    test-control-every-tool-is-reached-in-both-locks = {
      expr = lib.all (n: (revsOf rootLock).${n} != [ ] && (revsOf ciLock).${n} != [ ]) names;
      expected = true;
    };
  };
}
