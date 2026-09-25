# Oracle for a library's PUBLISHED SURFACE AT ITS OWN DECLARED POINT (den-hoag-ydm94).
#
# WHY. A library that takes its substrate injected is a function f : Substrate -> Surface, and
# several roots publish f itself. A root `nix flake check` forces only f's WHNF, so a published
# member that throws — one namespace down or at the top — is green everywhere. This check applies
# the root at the point it declares and forces every name it publishes.
#
# ★ WHAT THE GREEN SAYS, AND NOTHING MORE. At this library's own declared point (`import <root> { }`,
# or the root itself when it is a set), every published name evaluates to WHNF, except the declared
# tombstones, each of which throws exactly its declared message. For a roster member the declared
# point is its root-lock pins, which is exactly what a standalone consumer receives. A root whose
# defaults are NOT root-lock pins is held at whatever those defaults are, and the green says only
# that: gen-vars' `lib ? null` point walks 19 of the 29 names its flake's `lib` publishes. It says
# nothing about the library applied at any other point; the hub's and the corpus's application (f at
# the hub's pins) is theirs to hold.
#
# ★ A PUBLISHED NAME IS A PATH THROUGH PLAIN NAMESPACES. A consumer addresses `lib.render.dot`, so
# that path is a published name at whatever depth it sits.
#   · A NAMESPACE is a plain attrset: not `_type`-tagged and not a derivation. One carrying
#     `__functor` without `_type` is descended into; its other attributes are addressable.
#   · A `_type`-TAGGED VALUE IS A LEAF. The tag declares the set is the representation of a value of
#     an abstract type (option types, `mkIf`, modules); its fields are the implementation, and they
#     are self-cyclic through `functor.type`, so descending would break the abstraction and not end.
#   · A DERIVATION IS A LEAF. Its attributes are its build interface; forcing into it instantiates.
#   · A FUNCTION IS A LEAF. The root is applied because the library declares s0 in its root lock; a
#     member function declares no point the library publishes as a namespace, so it is forced to WHNF
#     and its codomain is not walked. A member whose formals all default is an ordinary call, not a
#     namespace, and stays a leaf.
#   · Lists and scalars are values, forced to WHNF.
#
# ★ NO DEPTH BOUND (den-hoag-ydm94 Q0, arm U, defaulted-reversible; folded into sitting item R1).
# The only ceiling is the evaluator's call depth: a non-well-founded namespace (a plain cycle, or an
# infinitely generated one) reds LOUD with `max-call-depth exceeded`. Upstream and Determinate name
# the path in the trace through the error context below; Lix's default trace does not.
#
# ★ COST: ONE VISIT PER UNFOLDED NAME-PATH. Shared structure is not deduplicated, so a finite
# namespace DAG with sharing (`{ a = c; b = c; }` k levels deep) costs 2^k visits: measured at
# gen-bind, host, k = 16 / 20 / 22 => 1.4 / 3.2 / 8.6 s. No live consumer has that shape (every
# live walk <= 5.5 s upstream).
#
# ★ TOMBSTONES ARE TOP-LEVEL NAMES, DECLARED WITH THEIR EXACT MESSAGE. `retired.<name> = <msg>`
# excludes the name from the walk and refuses the declaration if the name is absent or no longer
# throws. That a tombstone throws EXACTLY its message cannot be read here — Nix exposes no thrown
# message to evaluation — so `retiredCells` below generates one error-plane cell per entry, forced at
# the root seam, and the error plane pins the message. A declaration is therefore refused where no
# error plane (`ci/tests-error.nix`) exists: the cell would be generated and never run in CI.
# A nested tombstone is not expressible; the walk reds on it and names its path.
let
  # s0: the root at its declared point. Arity dispatch because neither `import p` nor
  # `import p { }` is total over both root shapes (a set root, a lambda root).
  point =
    root:
    let
      f = import root;
    in
    if builtins.isFunction f then f { } else f;
in
{
  inherit point;

  check =
    {
      pkgs,
      name,
      # A SOURCE TREE, not a built package: `inputs.self.sourceInfo.outPath`, never `outPath`, which
      # under the `?dir=ci` layout is `<root>/ci`.
      root,
      entry ? "owed",
      retired ? { },
    }:
    let
      hasRoot = builtins.pathExists (root + "/default.nix");
      hasPlane = builtins.pathExists (root + "/ci/tests-error.nix");
      retiredNames = builtins.attrNames retired;
      green = pkgs.runCommand "${name}-root-surface" { } "touch $out";

      owed =
        let
          s = point root;
          stale = builtins.filter (n: !(s ? ${n}) || (builtins.tryEval s.${n}).success) retiredNames;
          ns = v: builtins.isAttrs v && !(v ? _type) && (v.type or null) != "derivation";
          walk =
            p: v:
            builtins.foldl' (
              acc: n:
              let
                x = v.${n};
                q = "${p}.${n}";
              in
              builtins.addErrorContext "root-surface: while forcing the published name ${q}" (
                builtins.seq x (if ns x then builtins.seq (walk q x) acc else acc)
              )
            ) null (builtins.attrNames v);
        in
        if stale != [ ] then
          throw "root-surface: declared retired but absent or no longer throwing: ${builtins.concatStringsSep ", " stale}"
        else
          builtins.seq (walk "lib" (builtins.removeAttrs s retiredNames)) green;
    in
    # Every arm below is a NAMED refusal: the direct route has no module type in front of it, and an
    # interpreter error ("path does not exist") names nothing a caller can act on.
    if entry != "owed" && entry != "not-owed" then
      throw "root-surface: `entry` must be \"owed\" or \"not-owed\"; got ${builtins.toJSON entry}"
    else if entry == "not-owed" then
      if hasRoot then
        throw "root-surface: declared not-owed but the root has a default.nix; drop the declaration, or remove the root entry"
      else if retired != { } then
        throw "root-surface: declared not-owed but declares retired names (${builtins.concatStringsSep ", " retiredNames}); a tombstone is a published name, and a not-owed root publishes none"
      else
        pkgs.runCommand "${name}-root-surface" { }
          "echo 'root-surface declared not-owed and the root has no default.nix; the declaration is the subject, and it holds.'; touch $out"
    else if !hasRoot then
      throw "root-surface: owed (the default) but the root has no default.nix; declare gen.ci.rootSurface.entry = \"not-owed\" if this repository publishes no root entry"
    else if retired != { } && !hasPlane then
      throw "root-surface: declares retired names (${builtins.concatStringsSep ", " retiredNames}) but has no ci/tests-error.nix; each tombstone's message is pinned by a generated error-plane cell, and without the plane file no CI step runs it"
    else
      owed;

  # One error-plane cell per declared tombstone, forced AT THE ROOT SEAM, asserting the exact
  # message. Merged into `flake.testsError` by the flake module.
  retiredCells =
    {
      lib,
      root,
      retired,
    }:
    lib.mapAttrs' (
      n: m:
      lib.nameValuePair "test-retired-${n}" {
        expr = (point root).${n};
        expectedError = {
          type = "ThrownError";
          msg = "^" + lib.escapeRegex m + "$";
        };
      }
    ) retired;
}
