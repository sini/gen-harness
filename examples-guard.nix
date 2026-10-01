# The EXAMPLES GUARD: every directory under a member's `examples/` is evaluated by that member's own
# suite, against its working tree.
#
# WHY. Each `examples/<x>/` is a flake with its own lock. Nothing that gates the member evaluates it,
# so an example rots against the library and every gate stays green: measured, gen-algebra's demo red
# at tip with its `ci` at 165/165. The member declares each example's VALUE in `gen.ci.examples` — the
# usual value is the example's `outputs` applied to `nixpkgs.lib` alone, since a library example binds
# its parent as `import ../.. { }` (den-hoag-eu9do) — so the tree under test is the tree the example
# runs on, and no example lock is read.
#
# ★ THREE CELLS, BECAUSE EACH CATCHES WHAT THE OTHER TWO PASS.
#   · TOTALITY: the directories on disk equal the declared names plus the excluded ones. The default
#     `{ }` is the invariant, so a member that says nothing about an `examples/` it carries reds.
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
#
# ★ AN EXCLUSION IS BY NAME AND CITES THE ROW THAT TRACKS IT. An example that cannot be evaluated from
# the member's own suite (its closure contains a published copy of the member) is named in `excluded`
# with `{ row; reason; }`, and gets one cell whose NAME carries the row, so every run lists it. The
# cell reds on a blank row or reason, on a directory that is not on disk (a stale exclusion cannot
# outlive its example) and on a name that is also declared.
#
# ★ AN INTEGRATION EXAMPLE IS DECLARED THROUGH `exampleAtOwnLock`, AND ITS VALUE IS FORCED AT THE
# RELOCK, NOT HERE. Its lock is NOT COMMITTED (owner, 2026-09-30): the root `.gitignore` carries
# the anchored line `/examples/<d>/flake.lock`, the relock regenerates the lock in a scratch copy
# and forces the cells `relockCells` builds, over `example-graft.nix`'s graft of that fresh lock.
# The git-filtered source this suite reads holds no such lock, so the graft cannot run here. This
# suite holds the class instead, in one cell, `test-<d>-integration-lock-is-not-committed`, which
# reds on a committed lock, on a `.gitignore` without the exact line (else the relock does not
# classify the example and nothing forces it), and on a declaration naming another directory.
{ lib }:
let
  # The declaration `exampleAtOwnLock dir select` returns.
  isIntegration = v: (v._type or null) == "gen-ci-integration-example";

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

  # The force and leaves cells of one declared value.
  valueCells = n: v: {
    "test-${n}-forces-under-deepSeq" = {
      expr = builtins.deepSeq (strip v) "forced";
      expected = "forced";
    };
    "test-${n}-every-leaf-holds" = {
      expr = map lib.showAttrPath (failing [ ] v);
      expected = [ ];
    };
  };

  readLines = f: if builtins.pathExists f then lib.splitString "\n" (builtins.readFile f) else [ ];
in
{
  inherit isIntegration;

  # `dir: select: <declaration>`, bound in `flakeModule.nix` as the module argument of that name:
  # `gen.ci.examples.<d> = exampleAtOwnLock "<d>" (flake: <the value to force>);`.
  exampleAtOwnLock = dir: select: {
    _type = "gen-ci-integration-example";
    inherit dir select;
  };

  # `{ declared, flakeOf }` -> `{ <d> = { <the force and leaves cells>; }; }` for the integration
  # declarations, read by the relock's integration step as `examplesAtRelock`. `flakeOf dir` is the
  # example's grafted flake. Keyed by directory, so the step's cross-check reads the directories.
  relockCells =
    { declared, flakeOf }:
    lib.mapAttrs (n: v: valueCells n (v.select (flakeOf v.dir))) (
      lib.filterAttrs (_: isIntegration) (if declared == null then { } else declared)
    );

  # The read root `mkCi` adds when the evaluated source carries `examples/`, so `ci`'s git-unknown
  # refusal covers it with the same semantics as every other root, gitignored files included. An
  # `examples/` that is entirely untracked is absent from the source and gets neither this root nor
  # the totality cell: a never-committed example, not a published one rotting.
  readRoot = root: lib.optional (builtins.pathExists (root + "/examples")) (root + "/examples");

  # `{ root, declared, excluded }` -> the `gen-ci-examples` suite, `{ }` when there is nothing to
  # hold. `declared = null` with nothing excluded is a consumer that has not adopted the guard: no
  # suite. Any exclusion arms it, as any declaration does.
  cells =
    {
      root,
      declared,
      excluded ? { },
    }:
    if declared == null && excluded == { } then
      { }
    else
      let
        declared' = if declared == null then { } else declared;
        dir = root + "/examples";
        present = builtins.pathExists dir;
        onDisk = lib.optionals present (
          builtins.attrNames (lib.filterAttrs (_: t: t == "directory") (builtins.readDir dir))
        );
        blank = s: builtins.match "[[:space:]]*" s != null;
      in
      lib.optionalAttrs (present || declared' != { } || excluded != { }) (
        {
          test-every-example-directory-is-declared = {
            expr = onDisk;
            expected = lib.sort lib.lessThan (builtins.attrNames declared' ++ builtins.attrNames excluded);
          };
        }
        // lib.concatMapAttrs (
          n: e:
          let
            row = e.row or "";
          in
          {
            "test-${n}-excluded-citing-${if blank row then "no-row" else row}" = {
              expr =
                lib.optional (blank row) "names no tracking row"
                ++ lib.optional (blank (e.reason or "")) "states no reason"
                ++ lib.optional (!builtins.elem n onDisk) "examples/${n} is not a directory on disk"
                ++ lib.optional (declared' ? ${n}) "is also declared in gen.ci.examples";
              expected = [ ];
            };
          }
        ) excluded
        // lib.concatMapAttrs (
          n: v:
          if isIntegration v then
            {
              "test-${n}-integration-lock-is-not-committed" = {
                expr =
                  lib.optional (builtins.pathExists (
                    dir + "/${n}/flake.lock"
                  )) "examples/${n}/flake.lock is committed"
                  ++ lib.optional (
                    !builtins.elem "/examples/${n}/flake.lock" (readLines (root + "/.gitignore"))
                  ) "the root .gitignore lacks the exact line /examples/${n}/flake.lock"
                  ++ lib.optional (v.dir != n) "declared as ${n} but grafts examples/${v.dir}";
                expected = [ ];
              };
            }
          else
            valueCells n v
        ) declared'
      );
}
