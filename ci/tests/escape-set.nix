# ESCAPE-SET COVERAGE — one cell per member of the escape set, and a guard on the set's size.
#
# `hasInfix` is a literal substring test built on a regex primitive, so every metacharacter the
# needle may contain has to be escaped first. A member missing from the escape set does not break
# loudly: it turns the needle into a PATTERN, and the call then answers a different question while
# still answering. The `{` cell below is that case exactly — with `{` unescaped, `a{2}` stops being
# three literal characters and becomes "two a's", so a haystack that plainly contains `a{2}` is
# reported not to. A table of representative cases cannot see this, because which member is missing
# decides which needle notices; the coverage has to be per member.
#
# Each cell states, in its comment, what the pattern would MEAN with that member unescaped — that is
# the reason the pair discriminates, and it is what makes the cell a test rather than a sample.
# Measured over the twelve: eight flip a boolean and four raise (an unbalanced group or an
# unterminated bracket is not a valid regex); both redden, and which of the two a member produces
# is a property of the character, not a choice.
#
# `]` is a NON-member, and its non-membership is asserted rather than assumed: outside a bracket
# expression it is already literal, so escaping it would yield `\]`, which the engine rejects — a
# set carrying it aborts on every `]`-bearing needle instead of answering. That cell cannot live
# here, because an `expr` that aborts the moment `]` is re-added would crash the batch asserter
# behind `checks.default` rather than fail. It is on `../tests-error.nix`'s `testsError` output.
{
  genPrelude,
  upstreamPrelude,
  upstreamSrc,
  lib,
  ...
}:
let
  # Each cell answers twice: the vendored copy and the original, which must agree with each other
  # and with the stated answer. Agreement alone would accept two copies broken the same way; a
  # stated answer alone would not notice the copy drifting from what it is a copy OF.
  agree = needle: haystack: answer: {
    expr = {
      vendored = genPrelude.hasInfix needle haystack;
      upstream = upstreamPrelude.hasInfix needle haystack;
    };
    expected = {
      vendored = answer;
      upstream = answer;
    };
  };

  # The set read from source, so that a member added later without a cell below is caught here
  # rather than left quietly uncovered. Entries contribute exactly two quotes each, so the count is
  # quote-based rather than line-based: it survives reformatting, which a line count would not.
  # The terminator searched for is `];` rather than `]` — a two-character sequence no
  # single-character entry can produce, whatever the set's membership becomes.
  escapeBlock = src: lib.head (lib.splitString "];" (lib.last (lib.splitString "metachars = [" src)));
  quoteCount = s: (lib.length (lib.splitString "\"" s)) - 1;
  squeeze = s: lib.replaceStrings [ " " "\n" ] [ "" "" ] s;

  vendoredBlock = escapeBlock (builtins.readFile ../../prelude.nix);
  upstreamBlock = escapeBlock (builtins.readFile "${upstreamSrc}/lib/default.nix");
in
{
  flake.tests.escape-set = {
    # ── one cell per member ──

    # `\` unescaped leaves a lone backslash as the whole pattern: not a valid regex.
    test-backslash = agree "\\" "a\\b" true;

    # `[` unescaped opens a bracket expression that nothing closes.
    test-open-bracket = agree "[a" "x[ay" true;

    # `{` unescaped makes `a{2}` an interval — "two a's" — which "ba{2}c" does not contain.
    # This is the silent one: a wrong boolean, no error.
    test-open-brace = agree "a{2}" "ba{2}c" true;

    # `(` unescaped opens a group whose closing paren is escaped: unbalanced.
    test-open-paren = agree "(a" "f(a)" true;

    # `)` unescaped closes a group that was never opened.
    test-close-paren = agree "a)" "f(a)" true;

    # `^` unescaped anchors at the start, so it matches "ab" where the literal "^a" does not occur.
    test-caret = agree "^a" "ab" false;

    # `$` unescaped anchors at the end, so it matches "ba" where the literal "a$" does not occur.
    test-dollar = agree "a$" "ba" false;

    # `?` unescaped makes the preceding character optional, so `ba?` matches a bare "b".
    test-question = agree "ba?" "b" false;

    # `*` unescaped makes the preceding character repeatable-from-zero, so `ba*` matches "b".
    test-star = agree "ba*" "b" false;

    # `+` unescaped makes the preceding character repeatable-from-one, so `ba+` matches "ba".
    test-plus = agree "ba+" "ba" false;

    # `.` unescaped matches any character, so `a.c` matches "abc".
    test-dot = agree "a.c" "abc" false;

    # `|` unescaped makes the needle an alternation, so `a|b` matches a bare "a".
    test-pipe = agree "a|b" "a" false;

    # ── the set itself ──

    # Twelve cells above, one per member, and the set is twelve. If this count moves, either a
    # member arrived without a cell or `]` came back — both stale the coverage claim above.
    test-set-has-twelve-members = {
      expr = {
        vendored = (quoteCount vendoredBlock) / 2;
        upstream = (quoteCount upstreamBlock) / 2;
      };
      expected = {
        vendored = 12;
        upstream = 12;
      };
    };

    # The copy is faithful at the source level too, not only where a case table happens to look.
    # A member the original adds or drops shows up here as a text difference, naming itself.
    test-set-is-the-original-verbatim = {
      expr = squeeze vendoredBlock;
      expected = squeeze upstreamBlock;
    };
  };
}
