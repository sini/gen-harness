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
# The duplication is instrumented, not trusted: ./ci's agreement suite holds this copy to nixpkgs
# `lib.hasInfix`, the reference it is a drop-in for (THEORY below), and gen-prelude's fidelity suite
# holds the original to the same reference on the same case classes, so copy = original is the
# composition of the two. ./ci declares no gen input to compare against directly: every member's ci
# pins this repository, so one would close a revision cycle (den-hoag-lock-currency-ruling-ez1yq).
# The composition rests on two nixpkgs pins, this ci's and gen-prelude's ci's, which nothing holds
# equal — they agree while `escapeRegex` and `hasInfix` are the same in both.
#
# THEORY. nixpkgs `lib.hasInfix infix s` is `match ".*${escapeRegex infix}.*" s != null`; the
# leading/trailing `.*` make std::regex recurse to depth ∝ `stringLength s`, overflowing the C
# stack when scanning whole source files — which is exactly what a purity scan does, and why the
# harness hands this function to every suite. Splitting on the escaped literal carries no `.*`
# anchor and scans linearly. The result is the same boolean, so it is a drop-in.
#
# THE ESCAPE SET IS THE ENGINE'S METACHARACTER SET, EXACTLY. The list below is gen-prelude's, and
# gen-prelude's is nixpkgs' `stringToCharacters "\\[{()^$?*+|."` — the same twelve characters in the
# same order, fed to the same `replaceStrings` fold. Membership is unsound in BOTH directions. A
# member left out stops being quoted, and the needle silently becomes a PATTERN answering a
# different question. A member added in emits `\c` for a `c` the grammar defines no escape for,
# which is not the literal `c` and need not be a valid regex at all: `]` is the case in point —
# already literal outside a bracket expression, and `\]` is rejected by the engine, so a set
# carrying `]` aborts on every `]`-bearing needle where nixpkgs returns a boolean.
# `builtins.tryEval` does not contain that abort.
#
# Each equality is asserted where it can be. ./ci's escape-set suite holds every member against
# nixpkgs, one cell each, and its whole-domain cell runs this copy and nixpkgs over every printable
# ASCII character, so a member dropped here or added here reds by name; holding gen-prelude's own
# set to nixpkgs' is gen-prelude's fidelity suite, not this file's. `]` is the standing witness of
# both directions, and its cells — with the whole-domain cell, which also aborts on an added
# member — live on
# ./ci's second test output, `testsError` — an `expr` that answers only while `]` stays a non-member
# would ABORT the batch asserter behind `checks.default`, which forces every `expr` under
# `flake.tests`, rather than fail a cell there.
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
        "|"
        "."
      ];
    in
    replaceStrings metachars (map (c: "\\" + c) metachars);
in
{
  hasInfix = infix: content: infix == "" || length (split (escapeRegex infix) content) > 1;
}
