# THE LOCK WALKER — how many DISTINCT nodes a lock reaches under an input carrying a given label.
#
# NOT A SUITE. It sits under `_fixtures/` because the tree importer ignores any path containing
# `/_`, so this file is reached only by what imports it and never as a flake module.
#
# ★★★ WHAT IT COUNTS, AND WHY THE OBVIOUS INSTRUMENT IS THE WRONG ONE. The question an invariant
# about instance count asks is how many DISTINCT NODES are reached under an input labelled X, walked
# from `.root`. The obvious instrument — count lock entries whose KEY SPELLING matches X — answers a
# different question: lock keys carry nix's own `_2`/`_3` disambiguation suffixes, so that count is
# an artefact of how the lock file was written down rather than a fact about the evaluation. Node
# IDENTITY is what decides whether two `.lib` values are one value, which is what this counts.
#
# ★★ THE TWO INSTRUMENTS AGREE AT EVERY REVISION SO FAR TESTED, AND THAT IS THE TRAP RATHER THAN THE
# DEFENCE. Agreement between a correct instrument and an incidental one is what a silently wrong
# instrument looks like right up until the revision where it is not — so the ruled form is used
# because it is the question, not because the other one has been caught disagreeing.
#
# ★ THE ROOT GUARD IS NOT DEFENSIVE PROGRAMMING. A walker whose root resolves to nothing walks an
# empty graph and reports ZERO for every label, which reads as "the invariant holds" — a wrongly
# rooted walk is silently green. It therefore fails loudly instead.
{
  lib,
  lock,
}:
let
  rootKey =
    if lock.nodes or { } == { } || !(lock.nodes ? ${lock.root or ""}) then
      throw "lock-walk: `.root` names '${lock.root or "<absent>"}', which is not a node in this lock"
    else
      lock.root;

  # An input value is either a node key (a string) or a FOLLOWS PATH (a list), which is resolved
  # segment by segment from the root — never by looking a name up among the lock's keys.
  resolveInput = v: if builtins.isList v then resolvePath v else v;
  resolvePath = lib.foldl' (k: seg: resolveInput lock.nodes.${k}.inputs.${seg}) rootKey;

  labelledEdgesFrom =
    k:
    let
      inputs = lock.nodes.${k}.inputs or { };
    in
    lib.mapAttrsToList (label: v: {
      inherit label;
      node = resolveInput v;
    }) inputs;

  step =
    st:
    let
      edges = builtins.concatMap labelledEdgesFrom st.frontier;
      reached = lib.unique (map (e: e.node) edges);
    in
    {
      frontier = builtins.filter (n: !(builtins.elem n st.seen)) reached;
      seen = lib.unique (st.seen ++ reached);
      edges = st.edges ++ edges;
    };

  # One round per lock node bounds the breadth-first walk: each round adds at least one unseen node
  # or the frontier empties, so the node count is reachable-set-complete. A self-applying walk would
  # cost one evaluator frame per round and past the call-depth guard would end the evaluation, which
  # `tryEval` does not contain.
  walked =
    lib.foldl'
      (
        st: _:
        let
          next = step st;
        in
        builtins.seq (builtins.deepSeq next next) next
      )
      {
        frontier = [ rootKey ];
        seen = [ rootKey ];
        edges = [ ];
      }
      (builtins.attrNames lock.nodes);
in
{
  # The distinct nodes reached under an input carrying `label`, anywhere in the walk.
  distinctUnder =
    label: lib.unique (map (e: e.node) (builtins.filter (e: e.label == label) walked.edges));
  countUnder =
    label:
    builtins.length (lib.unique (map (e: e.node) (builtins.filter (e: e.label == label) walked.edges)));
}
