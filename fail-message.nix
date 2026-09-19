# The FAILURE MESSAGE of the batch asserter behind `checks.default` (`flakeModule.nix`).
#
# ★ IT RUNS ONLY ON THE FAILURE ARM, so every way it can fail is a way of LOSING the red it was
# printing. `builtins.toJSON` was such a way: it ABORTS on any value containing a function, and
# Nix reports that abort at the LAMBDA'S BIRTHPLACE rather than at the cell — so the message did
# not merely withhold the failing cell's name, it named a THIRD REPOSITORY. Measured cost:
# `den-hoag-jwtb0` was filed against gen-merge's `lib/interface` when the red cell was
# gen-schema's own `type-answer-ownership.test-refined-does-not-merge-with-its-bare-base`.
#
# THE CLASS IS WIDE AND NOT INCIDENTAL: every nixpkgs-protocol option type carries at least five
# functions — `check`, `merge`, `functor.binOp`, `getSubOptions`, `substSubModules` — so any cell
# whose subject is a type record was in it.
#
# ── THE THREE FAILURE MODES, EACH MEASURED, EACH NEEDING A DIFFERENT ANSWER ──
#
# A renderer here is not allowed to fail, so it is built from the three defences and not from one.
# All five readings below are `nix eval`, exits read UNPIPED, 2026-09-18 at this tree:
#
#   FUNCTIONS.  `toJSON { check = lib.types.int.check; name = "int"; }` ⇒ exit 1, `cannot convert
#   the built-in function 'isInt' to JSON`. `lib.generators.toPretty` renders it `<function>` ⇒
#   exit 0. That is the defect as filed, and `toPretty` alone answers it.
#
#   CYCLES, AND `toPretty` ALONE DOES NOT SURVIVE THEM. An option type is CYCLIC — `functor.type`
#   is the type itself — so `toPretty lib.types.int` ⇒ exit 1, `stack overflow; max-call-depth
#   exceeded`, 1995 duplicate `functor`/`type` frames. The filed repair shape was measured on a
#   HAND-BUILT `{ check = types.int.check; name = "int"; }`, which is not cyclic and therefore not
#   in the class the defect names. A cell holding a real `lib.types.<t>` is, and that is the
#   ordinary shape. ⇒ the value is DEPTH-CUT before it is rendered. The cut is
#   `lib.debug.traceSeqN`'s, which is also why `allowPrettyValues` exists: below the cutoff a
#   container becomes a value carrying its own renderer, and `val` is never forced.
#   Measured at this cut: `lib.types.int` ⇒ 1526 chars, `attrsOf (submodule …)` ⇒ 3102 chars,
#   both sub-second. The exponential the depth bound looks like it invites does not occur —
#   the cycle is one attribute wide per level.
#
#   THROWS. A cell's two sides are compared with `==`, which SHORT-CIRCUITS, so a throwing field
#   the comparison never reached is first forced HERE. `builtins.tryEval` holds that class — and
#   holds ONLY that class: measured, it catches `throw` (control ⇒ `CAUGHT`) and catches NEITHER
#   the toJSON conversion error NOR the stack overflow, both of which exit 1 straight through it.
#   So it is the third defence and not a substitute for the other two.
#
# PUBLISHED as `lib.failMessage` for the reason `lib.relock` is published: bound inside
# `flakeModule.nix` this was reachable only through a cell that had to FAIL to reach it, so the
# only value it was ever read at was one that had already taken the gate down. Called, it is an
# ordinary function and a cell can hold it at any value it likes.
{ lib }:
let
  inherit (builtins) isAttrs isList tryEval;

  # HOW DEEP A SIDE IS SHOWN. Not a knob: one number, stated here, because a caller choosing it
  # per call site is a second statement of a decision nobody making it has the measurements for.
  # Six is where the two readings above were taken.
  depth = 6;

  # Below the cut, a container is replaced by a value whose OWN renderer prints an ellipsis and
  # whose payload is never forced — which is what stops a cycle rather than merely delaying it.
  snip = v: {
    __pretty = _: if isList v then "[ … ]" else "{ … }";
    val = v;
  };

  cut =
    n: v:
    if n == 0 then
      (if isAttrs v || isList v then snip v else v)
    else if isList v then
      map (cut (n - 1)) v
    # A DERIVATION IS LEFT WHOLE. `toPretty` prints it as `<derivation …>`; walking its attributes
    # instead would replace that one line with its entire environment, which is the opposite of
    # what a bounded renderer is for.
    else if isAttrs v then
      (if lib.isDerivation v then v else lib.mapAttrs (_: cut (n - 1)) v)
    else
      v;

  render =
    v:
    let
      r = tryEval (lib.generators.toPretty { allowPrettyValues = true; } (cut depth v));
    in
    if r.success then r.value else "<unprintable: rendering this side threw>";
in
# THE CELL'S OWN NAME COMES FIRST AND IS PLAIN TEXT, ahead of either rendering. Should a side
# still defeat all three defences, what is lost is the VALUES — recoverable by re-running the cell
# — rather than the COORDINATE, which is the one thing the reader cannot derive from anything
# else, and whose loss is what cost `den-hoag-jwtb0`.
suite: testName: t:
"FAIL ${suite}.${testName}: got ${render t.expr}, expected ${render t.expected}"
