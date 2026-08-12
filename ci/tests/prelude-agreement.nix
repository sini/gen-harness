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
    # `]` is absent from this table for a structural reason rather than a domain one. Both
    # implementations exclude it from the escape set and answer as nixpkgs does — but only while it
    # stays excluded: escaping it produces `\]`, which Nix's regex engine rejects outright, so
    # re-adding it to either set turns the call into an abort. `builtins.tryEval` does not catch
    # that class, and the batch asserter behind `checks.default` forces every `expr` under
    # `flake.tests`, so a `]` case here would take the gate down instead of failing a cell. The `]`
    # cells live on ../tests-error.nix's `testsError` output for exactly that reason.
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
