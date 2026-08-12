# The harness's `genPrelude` — ONE function, and the reason it is here rather than pinned.
#
# A test harness that pins a gen library puts that library in every consumer's lock, and every
# consumer whose own root also pins it then holds TWO builds of one library in one evaluation.
# The harness needs a single pure function, so it carries the function instead of the dependency:
# vendoring is what makes "the harness declares no gen input" true by construction rather than
# managed. gen-prelude sets the precedent it is copied from — that library is itself `builtins`
# plus vendored copies, and pulls nothing.
#
# THE SURFACE IS `hasInfix` AND NOTHING ELSE. A test suite needing any other prelude attribute
# supplies its own `genPrelude` in its ci `specialArgs`, taken from `gen-prelude` at its own root —
# where the whole library lives and where the pin is the consumer's own. Widening this file to
# meet such a suite would make the harness a library again.
#
# The duplication is instrumented, not trusted: ./ci's agreement suite pins gen-prelude in the
# harness's own test plane and asserts this copy answers as the original does.
#
# THEORY. nixpkgs `lib.hasInfix infix s` is `match ".*${escapeRegex infix}.*" s != null`; the
# leading/trailing `.*` make std::regex recurse to depth ∝ `stringLength s`, overflowing the C
# stack when scanning whole source files — which is exactly what a purity scan does, and why the
# harness hands this function to every suite. Splitting on the escaped literal carries no `.*`
# anchor and scans linearly. The result is the same boolean — with one measured exception, the
# next paragraph's — so it is a drop-in.
#
# ONE MEASURED DOMAIN LIMIT, INHERITED AND KEPT. The metacharacter set below is gen-prelude's, and
# gen-prelude's is nixpkgs' twelve plus `]`. Escaping `]` yields `\]`, which Nix's regex engine
# rejects outright — so a needle containing `]` raises `invalid regular expression` here and in
# gen-prelude, while nixpkgs (which does not escape it) returns a boolean. The copy is faithful on
# purpose: agreement with the original is the property the ci suite asserts, so a corrected
# original must turn that suite red and pull the correction through, which a copy that had already
# "fixed" itself could not do. `builtins.tryEval` does not catch this class, so the limit is
# asserted where an error can be — ./ci's second test output, `testsError`, which the batch
# asserter behind `checks.default` does not quantify over.
let
  inherit (builtins) length replaceStrings split;

  escapeRegex =
    let
      metachars = [
        "\\"
        "["
        "{"
        "("
        ")"
        "^"
        "$"
        "?"
        "*"
        "+"
        "."
        "|"
        "]"
      ];
    in
    replaceStrings metachars (map (c: "\\" + c) metachars);
in
{
  hasInfix = infix: content: infix == "" || length (split (escapeRegex infix) content) > 1;
}
