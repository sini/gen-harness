# AGREEMENT — the vendored hasInfix answers as gen-prelude's does.
#
# The harness carries a copy of one function so that it can declare no gen input. A copy is a
# claim about another repository's code, and this suite is what makes that claim checkable: the
# original is pinned in the test plane and the two are run over the same cases. `genPrelude` here
# is not a local import — it is the value mkCi hands to every consuming suite, so the subject is
# what ships rather than what the file says.
#
# The metacharacter cases are the sharp half. Both implementations escape the needle before
# handing it to a regex primitive, so a broken escape is the failure mode a naive case table
# (letters only) cannot see: `.*` would then match everything and the difference would be silent.
{
  genPrelude,
  upstreamPrelude,
  lib,
  ...
}:
let
  # { needle, haystack, expected } — `expected` is stated rather than derived, so the suite is a
  # behaviour test as well as an agreement test. Agreement alone would pass if both copies were
  # wrong in the same way.
  cases = [
    {
      needle = "";
      haystack = "abc";
      expected = true;
    }
    {
      needle = "";
      haystack = "";
      expected = true;
    }
    {
      needle = "b";
      haystack = "abc";
      expected = true;
    }
    {
      needle = "z";
      haystack = "abc";
      expected = false;
    }
    {
      needle = "abc";
      haystack = "abc";
      expected = true;
    }
    {
      needle = "abcd";
      haystack = "abc";
      expected = false;
    }
    {
      needle = "a";
      haystack = "";
      expected = false;
    }
    {
      needle = "aa";
      haystack = "aaaa";
      expected = true;
    }
    {
      needle = "b\nc";
      haystack = "a\nb\nc";
      expected = true;
    }
    # ── metacharacters: the needle is a LITERAL, never a pattern ──
    {
      needle = ".*";
      haystack = "a.*b";
      expected = true;
    }
    {
      needle = ".*";
      haystack = "aXb";
      expected = false;
    }
    {
      needle = "a.c";
      haystack = "a.c";
      expected = true;
    }
    {
      needle = "a.c";
      haystack = "abc";
      expected = false;
    }
    # `]` is absent from this table because it is outside BOTH implementations' domain: the shared
    # escape produces `\]`, which Nix's regex engine rejects, so the call raises rather than
    # answering — measured, and `builtins.tryEval` does not catch that class, so it cannot be
    # asserted here. nixpkgs does not escape `]` and does answer. The divergence is gen-prelude's
    # and is recorded at ../../prelude.nix; a fix there turns the agreement assertion above red,
    # which is the instrument working.
    {
      needle = "[x";
      haystack = "y[xz";
      expected = true;
    }
    {
      needle = "[x";
      haystack = "yxz";
      expected = false;
    }
    {
      needle = "(";
      haystack = "f(x)";
      expected = true;
    }
    {
      needle = "$^";
      haystack = "a$^b";
      expected = true;
    }
    {
      needle = "|";
      haystack = "a|b";
      expected = true;
    }
    {
      needle = "+?";
      haystack = "a+?b";
      expected = true;
    }
    {
      needle = "\\";
      haystack = "a\\b";
      expected = true;
    }
    {
      needle = "\\";
      haystack = "ab";
      expected = false;
    }
  ];

  vendored = map (c: genPrelude.hasInfix c.needle c.haystack) cases;
  upstream = map (c: upstreamPrelude.hasInfix c.needle c.haystack) cases;
  stated = map (c: c.expected) cases;
in
{
  flake.tests.prelude-agreement = {
    test-vendored-agrees-with-gen-prelude = {
      expr = vendored;
      expected = upstream;
    };

    test-vendored-matches-the-stated-table = {
      expr = vendored;
      expected = stated;
    };

    # CONTROL — the table discriminates. A predicate stuck at one value would satisfy both
    # assertions above if every case shared that value.
    test-table-holds-both-answers = {
      expr = {
        anyTrue = lib.any (x: x) vendored;
        anyFalse = lib.any (x: !x) vendored;
      };
      expected = {
        anyTrue = true;
        anyFalse = true;
      };
    };

    # CONTROL — the comparison target is the real library, not a second reference to the copy.
    # Wire `upstreamPrelude` to the vendored value and the agreement assertion passes vacuously;
    # the original carries dozens of attributes and the harness's surface carries one.
    test-upstream-is-the-whole-library = {
      expr = lib.length (lib.attrNames upstreamPrelude) > 10;
      expected = true;
    };

    # The surface itself, asserted rather than documented: a suite reaching for any other prelude
    # attribute must supply its own genPrelude from gen-prelude at its own root.
    test-surface-is-hasinfix-only = {
      expr = lib.attrNames genPrelude;
      expected = [ "hasInfix" ];
    };
  };
}
