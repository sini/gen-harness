# The EXAMPLES GUARD: every directory under a member's `examples/` is evaluated by that member's own
# suite, against its working tree.
#
# WHY. Each `examples/<x>/` is a flake with its own lock, pinning a published copy of the library it
# documents. Nothing that gates the member evaluates it, so an example rots against the library and
# every gate stays green: measured, gen-algebra's demo red at tip with its `ci` at 165/165. The member
# declares each example's VALUE in `gen.ci.examples` — the usual value is the example's `outputs`
# applied to the suite's own library values — so the tree under test is the tree the example runs on,
# and no example lock is read.
#
# ★ THREE CELLS, BECAUSE EACH CATCHES WHAT THE OTHER TWO PASS.
#   · TOTALITY: the directories on disk equal the declared names. The default `{ }` is the invariant,
#     so a member that says nothing about an `examples/` it carries reds; there is no exclusion arm.
#   · FORCE: `deepSeq` of the declared value. `attrNames` reads a full spine over cells that throw.
#   · LEAVES: every nix-unit leaf `{ expr; expected; }` holds. `deepSeq` passes a leaf that
#     disagrees without throwing — an error returned as a value is still a value.
#
# ★ AN `expectedError` LEAF IS A CORRECT EXAMPLE WHOSE `expr` THROWS. The force cell does not force
# that `expr`, and the leaves cell requires it to fail under `tryEval`.
# ponytail: the thrown MESSAGE is not asserted — Nix exposes no message to evaluation, and error-plane
# cells would need names derived by walking the value, which an uncatchable error in any output would
# turn into an abort of every output. Upgrade path: the member declares such cells on
# `flake.testsError` itself.
#
# ★ CELL NAMES DEPEND ON THE DECLARED NAMES ONLY, never on the values, so an example that aborts takes
# down its own cells and nothing else.
{ lib }:
let
  isLeaf = v: builtins.isAttrs v && v ? expr && (v ? expected || v ? expectedError);

  # The value with every `expectedError` leaf's `expr` removed, so `deepSeq` forces the rest.
  strip =
    v:
    if isLeaf v && v ? expectedError then
      removeAttrs v [ "expr" ]
    else if builtins.isAttrs v && !isLeaf v then
      builtins.mapAttrs (_: strip) v
    else
      v;

  # The attribute paths of the leaves that do not hold.
  failing =
    path: v:
    if isLeaf v then
      if v ? expectedError then
        lib.optional (builtins.tryEval (builtins.deepSeq v.expr null)).success path
      else
        lib.optional (v.expr != v.expected) path
    else if builtins.isAttrs v then
      lib.concatLists (lib.mapAttrsToList (n: failing (path ++ [ n ])) v)
    else
      [ ];
in
{
  # The read root `mkCi` adds when the evaluated source carries `examples/`, so `ci`'s git-unknown
  # refusal covers it with the same semantics as every other root, gitignored files included. An
  # `examples/` that is entirely untracked is absent from the source and gets neither this root nor
  # the totality cell: a never-committed example, not a published one rotting.
  readRoot = root: lib.optional (builtins.pathExists (root + "/examples")) (root + "/examples");

  # `{ root, declared }` -> the `gen-ci-examples` suite, `{ }` when there is nothing to hold.
  cells =
    { root, declared }:
    let
      dir = root + "/examples";
      present = builtins.pathExists dir;
      onDisk = lib.optionals present (
        builtins.attrNames (lib.filterAttrs (_: t: t == "directory") (builtins.readDir dir))
      );
    in
    lib.optionalAttrs (present || declared != { }) (
      {
        test-every-example-directory-is-declared = {
          expr = onDisk;
          expected = builtins.attrNames declared;
        };
      }
      // lib.concatMapAttrs (n: v: {
        "test-${n}-forces-under-deepSeq" = {
          expr = builtins.deepSeq (strip v) "forced";
          expected = "forced";
        };
        "test-${n}-every-leaf-holds" = {
          expr = map lib.showAttrPath (failing [ ] v);
          expected = [ ];
        };
      }) declared
    );
}
