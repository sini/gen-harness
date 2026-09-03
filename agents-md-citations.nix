# Oracle for the AGENTS.md CITATION-BINDING invariant.
#
# INVARIANT: inside the region a sheet DECLARES, every backticked span that claims a citation
# vocabulary must resolve against this repository's own tree. Everything outside the declaration
# is prose and is not this check's business.
#
# WHY. A capability sheet is trusted because it is code-derived, and nothing holds it there: a row
# is a measurement pinned at a rev, and when the code moves nothing re-reads it. The half that
# HIDES the falsity is the citation, not the prose — a reader who follows a drifted coordinate
# lands on code that neither confirms nor refutes the row, and concludes it is merely imprecise
# rather than false. A false claim whose citation resolves is arguable; a false claim whose
# citation dangles is undetectable by the one reader who tried to check it.
#
# ★ WHY A DECLARED REGION AND NOT THE WHOLE DOCUMENT. A sheet legitimately names artefacts that do
# not exist — an arming run over a probe that was written, left untracked and deleted; a
# deliberately broken former spelling of a cell. Those are true sentences naming absent things and
# they are SHAPE-IDENTICAL to a stale citation, so a predicate that discovers its own subject
# cannot tell them apart. Over a whole sheet the measured false-positive rate is 43-57%. The
# declaration drives it to zero, and it is the shipped exemplar's own move: `agents-md-hub-inputs`
# takes a marker-delimited window first, structural rather than line-numbered, precisely so a
# second fence cannot be picked up by accident.
#
# ★ WHAT THIS DOES NOT DO, stated so no reader assumes it: it does not decide whether a claim is
# TRUE. It decides whether the evidence the claim offers still EXISTS. Truth is carried where it
# already is — by the `Tests:` anchor, whose named cells re-verify on every run instead of resting
# on a one-time eval. This check makes that anchor load-bearing by refusing to let it dangle.
#
# ★ WHY A DERIVATION RATHER THAN A `nix-unit` CELL, since the ecosystem binds documents both ways.
# The route is not the reason; the SUBJECT is. This check's subject is a FILE TREE, not a value: it
# reads the whole tracked file list to resolve paths and count lines, and every `.nix` under `ci/`
# or `tests/` — NOT `lib/` — to resolve cell names. In a
# pure cell that whole corpus read lands at FLAKE-EVALUATION time, so every consumer's `nix flake
# show` pays for a documentation guard; in a derivation it lands when the check is BUILT, which is
# where a guard over a tree belongs. The cost of choosing this, because it is not free: the
# ecosystem's arming law — 0/0 is a false pass, a control not named `test-control-*` is never
# collected — does not reach a shell check, whose controls are `if` blocks no counter sees. What
# replaces it is the acceptance table, whose every RED was driven and read.
#
# The core predicates are ABSENCES, and an absence proves nothing without a live control: a scan
# over a missing sheet, an undeclared region or a vanished suite corpus passes exactly as loudly as
# a clean one. Each is preceded by a positive control on the same artefact in the same run.
{
  pkgs,
  name,
  # The repository root, and it is `inputs.self.sourceInfo.outPath` — NEVER `outPath`. Under the
  # `?dir=ci` layout every consumer uses, the latter is `<root>/ci`, so the sheet and the corpus
  # would both be looked for one directory down and the whole check would resolve nothing.
  # `readroots.nix` states the same ground for the same reason.
  root,
}:
let
  # The classifier lives in its own store path rather than a heredoc inside the builder: a heredoc
  # terminator's column depends on how Nix strips this file's indentation, which couples the
  # program's correctness to its formatting.
  classify = pkgs.writeText "agents-md-citations.awk" ''
    # ── the citation binding, in one pass over the declared region ──
    # Called with -v ROOT= -v NAME= -v SHEET= -v FILELIST= -v NIXLIST=. Everything happens in
    # BEGIN: the inputs are read explicitly by name, so there is no record loop to reason about.
    function die(m) { print m > "/dev/stderr"; exit 1 }

    function linecount(f,   p, l, n) {
      if (f in LC) return LC[f]
      p = ROOT "/" f; n = 0
      while ((getline l < p) > 0) n++
      close(p)
      LC[f] = n
      return n
    }

    function hasname(f, nm,   p, l, got) {
      p = ROOT "/" f; got = 0
      while ((getline l < p) > 0) if (index(l, nm) > 0) { got = 1; break }
      close(p)
      return got
    }

    # ★ A CELL NAME RESOLVES AS A WHOLE IDENTIFIER, NEVER AS A SUBSTRING. `index()` answers "does
    # this line contain these characters", which is a different question from "does this line
    # name this cell": `test-foo` is a substring of `test-foo-bar`, so a citation that is
    # truncated, renamed-by-suffix or commented out resolved against the cell that REPLACED it —
    # the exact drift this check exists to catch, surviving in the one shape it cannot announce.
    # Cell names run over the CELLRE alphabet, so an occurrence bounded on both sides by
    # something outside that alphabet is the name itself and not a fragment of a longer one. The
    # ends of the line count as boundaries, which is why the empty string is tested against IDCH
    # rather than special-cased.
    function wholeword(l, nm,   o, k, before, after) {
      o = 1
      while ((k = index(substr(l, o), nm)) > 0) {
        k += o - 1
        before = (k > 1) ? substr(l, k - 1, 1) : ""
        after = substr(l, k + length(nm), 1)
        if (before !~ IDCH && after !~ IDCH) return 1
        o = k + 1
      }
      return 0
    }

    # The suite names a file DECLARES, as a space-fenced string for membership testing. A suite is
    # an attribute under `flake.tests` or `flake.testsError`, and the corpus writes that path four
    # ways — `tests.s.test-x`, `tests.s = {`, `tests."s" = {`, `testsError.s` — which the optional
    # quote and the bounded name cover as one. The fifth spelling, `tests = { s = {`, carries the
    # suite on a line of its own and is NOT recognised; that is what the empty-set fallback at the
    # use site is for, and why this returns the set rather than a verdict.
    function suitesof(fl, n,   i, t, out) {
      out = ""
      for (i = 1; i <= n; i++)
        if (match(fl[i], DECLRE)) {
          t = substr(fl[i], RSTART, RLENGTH)
          gsub(/"/, "", t)
          out = out " " substr(t, index(t, ".") + 1) " "
        }
      return out
    }

    # ★ EXACT-FIRST, THEN SUFFIX, AND THE SUFFIX HALF IS FAIL-CLOSED. Suffix resolution is what
    # lets a bare `x.nix` resolve inside a section that names its directory, and it is NOT a
    # function: `flake.nix`, `default.nix` and `carrier.nix` routinely answer to two or three
    # tracked files. A tracked path from the root is unique by construction, so an exact hit is
    # the one the author wrote — and exact-first is what makes the rule TOTAL, because it leaves
    # every RED a spelling that resolves. Only when no tracked file has that exact path does the
    # fallback run, and then EVERY candidate must resolve or the span is red, naming each with its
    # own diagnosis. Without the fail-closed half a drifted coordinate is covered by a longer
    # namesake elsewhere in the tree, which is silence becoming access.
    function candidates(p, out,   i, n, f, j, t) {
      n = 0
      for (i in out) delete out[i]
      if (p in ISFILE) { out[1] = p; return 1 }
      for (i = 1; i <= NFILES; i++) {
        f = FILES[i]
        if (length(f) > length(p) && substr(f, length(f) - length(p)) == "/" p) out[++n] = f
      }
      for (i = 2; i <= n; i++) {          # insertion sort: candidate lists are 1-3 long
        t = out[i]
        for (j = i - 1; j >= 1 && out[j] > t; j--) out[j + 1] = out[j]
        out[j + 1] = t
      }
      return n
    }

    # A range is checked at its HIGHEST endpoint, and a LIST at the highest of every element —
    # the arm a first-endpoint check misses when a file shrinks under a citation that straddles
    # its old end.
    function maxline(spec,   parts, i, n, e, a, b, m) {
      n = split(spec, parts, /, ?/)
      m = 0
      for (i = 1; i <= n; i++) {
        e = parts[i]
        # HIGHEST, not second: `60-900` and `900-60` name the same two lines, and taking the
        # second endpoint made the reversed spelling FAIL-OPEN — exit 0, silent, on a range whose
        # forward form reds. (Three endpoints already red as unclassified, so this is the whole
        # of it.) Live incidence when it was found: 0 of 107 ranges across the 22 regions.
        if (index(e, "-") > 0) { split(e, a, "-"); b = (a[1] + 0 > a[2] + 0) ? a[1] + 0 : a[2] + 0 } else b = e + 0
        if (b > m) m = b
      }
      return m
    }

    # One candidate's verdict, as the token that goes inside the parentheses.
    function verdict(f, kind, arg,   n) {
      if (kind == "coord") {
        n = linecount(f)
        return (arg + 0 <= n) ? "ok" : ("file-has-" n "-lines")
      }
      return hasname(f, arg) ? "ok" : "no-such-binding"
    }

    # Resolve a path-bearing span. Returns "" when it resolves, else the parenthetical diagnosis.
    function resolve(p, kind, arg, cands,   n, i, v, bad, parts) {
      n = candidates(p, cands)
      if (n == 0) return "(no-such-file)"
      if (n == 1) { v = verdict(cands[1], kind, arg); return (v == "ok") ? "" : "(" v ")" }
      bad = 0; parts = ""
      for (i = 1; i <= n; i++) {
        v = verdict(cands[i], kind, arg)
        if (v != "ok") bad = 1
        parts = parts (i > 1 ? "," : "") cands[i] "(" v ")"
      }
      return bad ? "(ambiguous-suffix:" parts ")" : ""
    }

    function join(arr, n,   i, s) {
      s = ""
      for (i = 1; i <= n; i++) s = s (i > 1 ? ", " : "") arr[i]
      return s
    }

    BEGIN {
      # ── the recognisers, anchored at BOTH ends and pairwise disjoint ──
      # Anchoring is what makes the UNCLASSIFIED disposition reachable at all: an unanchored
      # coordinate arm accepts `x.nix:12.` as a valid coordinate, and the check then reports on a
      # span it never parsed.
      #
      # PATHRE is the PATH ALPHABET, and it is the only guard standing between a family and a
      # false red — so it is stated rather than left implicit. It admits no space, `*`, `…`, `{`,
      # `,` or `|`, so a family cannot match a recogniser BY CONSTRUCTION rather than by ordering.
      # (Shape 5's comma sits after the `:`, in the coordinate part, never in the path.) It ends
      # in `.nix` so a recogniser cannot fire on a prose span — `AGENTS.md`, `readDir`, `lib.fix`
      # — which is what keeps the prose disposition reachable and the check usable.
      #
      # Disjointness, span by span: a cell name may not contain `.nix`; a file path may not
      # contain `:`; the first character after a coordinate's `:` is a digit and an anchor's is
      # not; and a list needs a comma no other shape admits.
      PATHRE   = "[A-Za-z0-9_./+-]*[A-Za-z0-9_+-]\\.nix"
      CELLRE   = "^([A-Za-z0-9_-]+\\.)?test-[A-Za-z0-9_'-]+$"
      FILERE   = "^" PATHRE "$"
      COORDRE  = "^" PATHRE ":[0-9]+(-[0-9]+)?$"
      ANCHORRE = "^" PATHRE ":[A-Za-z_'][A-Za-z0-9_'-]*$"
      LISTRE   = "^" PATHRE ":[0-9]+(-[0-9]+)?(, ?[0-9]+(-[0-9]+)?)+$"
      # The cell alphabet, as a one-character class: the boundary `wholeword` reads. It is CELLRE's
      # own trailing class, and the two have to stay the same set or a legal cell name becomes
      # unresolvable at its own spelling.
      IDCH     = "[A-Za-z0-9_'-]"
      DECLRE   = "tests(Error)?\\.\"?[A-Za-z0-9_-]+"
      BEGINM   = "<!-- gen-citations:begin -->"
      ENDM     = "<!-- gen-citations:end -->"

      while ((getline l < FILELIST) > 0) { FILES[++NFILES] = l; ISFILE[l] = 1 }
      close(FILELIST)
      while ((getline l < NIXLIST) > 0) NIXF[++NNIX] = l
      close(NIXLIST)
      while ((getline l < SHEET) > 0) L[++NL] = l
      close(SHEET)

      # ── control: a region is DECLARED. A guard with no subject must not read clean ──
      for (i = 1; i <= NL; i++) {
        t = L[i]; sub(/^[ \t]+/, "", t); sub(/[ \t]+$/, "", t)
        if (t == BEGINM) { nb++; B = i }
        if (t == ENDM)   { ne++; E = i }
      }
      if (nb != 1 || ne != 1 || E <= B)
        die("CONTROL FAILED: AGENTS.md declares no well-formed " BEGINM "/" ENDM " region")

      # ── control: BOTH SEAMS ARE BOUND, so the region is a whole ATX section ──
      # Without this the cheapest way to make a red sheet green is to move the row one line past
      # a marker, and nothing says so. Binding one seam leaves the escape alive on the other.
      # Section alignment also makes the escape an ACT: to take a citation out of the guard you
      # must give it its own section, a visible structural edit rather than an invisible one-line
      # move. The predicate is heading-NAME-agnostic, because heading names differ across sheets.
      for (i = B - 1; i >= 1 && L[i] ~ /^[ \t]*$/; i--) ;
      if (i < 1)
        die("CONTROL FAILED: AGENTS.md declares no well-formed " BEGINM "/" ENDM " region")
      if (L[i] !~ /^#{1,6} /) {
        print "CONTROL FAILED: content precedes " BEGINM " after the section heading" > "/dev/stderr"
        print "  line " i ": " L[i] > "/dev/stderr"
        print "  The region is a whole ATX section. Move the line above the heading, or inside the region." > "/dev/stderr"
        exit 1
      }
      for (i = E + 1; i <= NL && L[i] ~ /^[ \t]*$/; i++) ;
      if (i <= NL && L[i] !~ /^#{1,6} /) {
        print "CONTROL FAILED: content follows " ENDM " before the next heading" > "/dev/stderr"
        print "  line " i ": " L[i] > "/dev/stderr"
        print "  The region is a whole ATX section. Move the line inside the region, or give it its own heading." > "/dev/stderr"
        exit 1
      }

      # ── control: the region is NON-EMPTY. An empty domain satisfies every universal ──
      empty = 1
      for (i = B + 1; i < E; i++) if (L[i] !~ /^[ \t]*$/) { empty = 0; break }
      if (empty)
        die("CONTROL FAILED: AGENTS.md declares no non-empty " BEGINM "/" ENDM " region")

      # ── classification, TOTAL over the region's backticked spans ──
      # Four dispositions, applied in THIS order, each carrying the negation of the ones above it,
      # so the partition is disjoint as well as total. ★ CLASSIFICATION RUNS FIRST, and the order
      # is load-bearing: a coordinate list contains a comma, so a family-first order swallows it —
      # silently, while every line it names resolves. Two outcomes on one span, exit 0 silent
      # against exit 1 named, decided by nothing but the order these tests are written in.
      #
      # ★ THE FAIL-OPEN THIS KEEPS, NAMED AND BOUNDED. A span naming an artefact WITHOUT writing
      # `test-` or `.nix` is read as prose. Widening the candidate predicate to catch it (a `/`,
      # say) sweeps in `./ci#tests` and every path-shaped prose span, which is the
      # discovered-subject failure the declared region exists to refuse.
      #
      # STRUCK, and kept legible because it was this hole's stated bound: "the guarantee is
      # therefore: every span inside the region that CLAIMS a citation vocabulary is either
      # resolved or named." That is FALSE, and on live spans — `README.md:134`,
      # `ci/perf-bench.sh:NS`, `/home/sini/.config/git/ignore:22` each name a file that EXISTS and
      # each read as a coordinate to any human, yet each is filed as prose and is therefore
      # neither resolved nor named. THE EXCLUDED AXIS IS THE ARTEFACT'S EXTENSION: the candidate
      # predicate is `test-` or `.nix`, so a citation into a non-`.nix` file is invisible to this
      # check however citation-shaped it looks.
      #
      # The guarantee ranges over CLASSIFIED CITATIONS, not over every span a reader would call
      # one: every span inside the region that names a `.nix` path or a `test-` cell is either
      # resolved or named. Not: every span is checked, and not: every citation is checked.
      for (i = B + 1; i < E; i++) {
        s = L[i]
        while (match(s, /`[^`]+`/)) {
          span = substr(s, RSTART + 1, RLENGTH - 2)
          s = substr(s, RSTART + RLENGTH)

          # ★ THE QUEUE IS KEYED ON THE SPAN, NOT THE BARE CELL. `a.test-x` and `b.test-x` are two
          # different claims, and keying on the cell collapsed them into one verdict — whichever
          # was cited first decided both.
          if (span ~ CELLRE) {
            nCells++
            if (!(span in CELLSEEN)) {
              CELLSEEN[span] = 1; CELLQ[++nCellQ] = span
              p = index(span, ".")
              CELLNAME[span] = (p > 0) ? substr(span, p + 1) : span
              CELLSUITE[span] = (p > 0) ? substr(span, 1, p - 1) : ""
            }
          }
          else if (span ~ FILERE) {
            nFiles++
            if (candidates(span, C) == 0 && !(span in SEEN)) { SEEN[span] = 1; badFiles[++nBadF] = span }
          }
          else if (span ~ COORDRE || span ~ LISTRE) {
            if (span ~ LISTRE) nList++; else nCoords++
            p = index(span, ":")
            d = resolve(substr(span, 1, p - 1), "coord", maxline(substr(span, p + 1)), C)
            if (d != "" && !((span d) in SEEN)) { SEEN[span d] = 1; badCoords[++nBadC] = span d }
          }
          else if (span ~ ANCHORRE) {
            nAnchors++
            p = index(span, ":")
            d = resolve(substr(span, 1, p - 1), "anchor", substr(span, p + 1), C)
            if (d != "" && !((span d) in SEEN)) { SEEN[span d] = 1; badAnchors[++nBadA] = span d }
          }
          else if (span ~ /[ *{,|]/ || index(span, "…") > 0) nFamily++
          else if (index(span, "test-") > 0 || index(span, ".nix") > 0) {
            if (!(span in SEEN)) { SEEN[span] = 1; unc[++nUnc] = span }
          }
          else nProse++
        }
      }

      # ── control: cells are cited, so a suite corpus must exist to resolve them against ──
      # Without this every cell reads as dangling and the count is an artefact of a missing tree.
      if (nCellQ > 0 && NNIX == 0)
        die("CONTROL FAILED: the region names test cell(s) but no suite corpus exists to resolve them")

      # One pass over the suite corpus, resolving every cited cell WHOLE and — where the citation
      # qualifies it — IN THE SUITE IT NAMES.
      #
      # ★ THE QUALIFIER IS A CLAIM, NOT DECORATION. `suite.cell` says the cell lives in THAT
      # suite, so resolving only the cell half made the suite half unfalsifiable: a citation that
      # named the wrong suite for a real cell read green, and the re-anchoring shape this construct
      # is built for — a row following a suite that moved — is exactly the drift that produces.
      #
      # ★ AND THE GATE FAILS OPEN ON A FILE THAT DECLARES NO SUITE THIS SCAN CAN SEE, which is the
      # one direction a recogniser over TEXT may take. A file whose suite name sits on a line of
      # its own (`tests = { s = {`) or which carries cells outside any `flake.tests` path is not a
      # file that CONTRADICTS the qualifier; it is a file the scan cannot speak about, and
      # refusing there would red a legitimate citation. Measured at the landing: 8 of 720 corpus
      # files carry cell definitions no suite path reaches, `gen-prelude/ci/tests/prelude.nix`
      # holding 128 of them.
      for (i = 1; i <= NNIX && nCellQ > 0; i++) {
        p = ROOT "/" NIXF[i]
        nfl = 0
        while ((getline l < p) > 0) FL[++nfl] = l
        close(p)
        SUI = suitesof(FL, nfl)
        for (k = 1; k <= nfl; k++) {
          if (index(FL[k], "test-") == 0) continue
          for (j = 1; j <= nCellQ; j++) {
            if (CELLQ[j] in FOUND) continue
            if (!wholeword(FL[k], CELLNAME[CELLQ[j]])) continue
            FOUNDANY[CELLQ[j]] = 1
            cs = CELLSUITE[CELLQ[j]]
            if (cs == "" || SUI == "" || index(SUI, " " cs " ") > 0) FOUND[CELLQ[j]] = 1
          }
        }
      }
      # Two dispositions, because they are two repairs: a cell nothing defines is a dead citation,
      # and a cell its own suite does not define is a citation that followed the code only halfway.
      for (j = 1; j <= nCellQ; j++) {
        if (CELLQ[j] in FOUND) continue
        if (CELLQ[j] in FOUNDANY) badSuites[++nBadSu] = CELLQ[j]
        else badCells[++nBadCe] = CELLQ[j]
      }

      summary = "cells=" nCells+0 " files=" nFiles+0 " coords=" nCoords+0 " anchors=" nAnchors+0 \
                " list=" nList+0 " family=" nFamily+0 " prose=" nProse+0 " unclassified=" nUnc+0

      if (nBadCe + nBadSu + nBadF + nBadC + nBadA + nUnc == 0) {
        print "── " NAME "-agents-md-citations ──"
        print "region declared; " summary
        exit 0
      }

      print "region declared; " summary > "/dev/stderr"
      for (j = 1; j <= nUnc; j++)
        print "CITATION UNCLASSIFIED -- inside the region, names test- or .nix, matches no citation shape: " unc[j] > "/dev/stderr"
      if (nBadCe) print "CITATION DRIFT -- cells no suite defines: " join(badCells, nBadCe) > "/dev/stderr"
      if (nBadSu) print "CITATION DRIFT -- cells the cited suite does not define: " join(badSuites, nBadSu) > "/dev/stderr"
      if (nBadF)  print "CITATION DRIFT -- files that do not exist: " join(badFiles, nBadF) > "/dev/stderr"
      if (nBadC)  print "CITATION DRIFT -- coordinates that do not resolve: " join(badCoords, nBadC) > "/dev/stderr"
      if (nBadA)  print "CITATION DRIFT -- binding anchors that do not resolve: " join(badAnchors, nBadA) > "/dev/stderr"
      print "Repair: fix the citation so it resolves against this repository's tree, or take the" > "/dev/stderr"
      print "span out of the region by giving it its own ATX section -- a visible structural act." > "/dev/stderr"
      print "This check reads whether the evidence a claim offers still EXISTS, never whether the" > "/dev/stderr"
      print "claim is true; truth is carried by the Tests: anchor, which this refuses to let dangle." > "/dev/stderr"
      exit 1
    }
  '';
in
pkgs.runCommand "${name}-agents-md-citations" { inherit root; } ''
  sheet="$root/AGENTS.md"

  # ── positive control: the subject exists ──
  # Shape inherited from mdformat-plugins-check.nix: a guard whose subject was removed must say
  # so rather than pass. gen-harness itself has no AGENTS.md and therefore cannot take this check.
  if [ ! -s "$sheet" ]; then
    echo "CONTROL FAILED: no non-empty AGENTS.md at $sheet; this check has no subject." >&2
    echo "If the sheet was deliberately removed, remove this check with it." >&2
    exit 1
  fi

  # The corpus is the SOURCE as the flake sees it, so it is exactly the tracked tree — no git in
  # the sandbox, and no untracked file can make a citation resolve that a fresh clone would red.
  ( cd "$root" && find . -type f | sed 's|^\./||' | sort ) > "$TMPDIR/files"
  grep -E '(^|/)(ci|tests)/' "$TMPDIR/files" | grep '\.nix$' > "$TMPDIR/nix" || true

  awk -v ROOT="$root" -v NAME="${name}" -v SHEET="$sheet" \
      -v FILELIST="$TMPDIR/files" -v NIXLIST="$TMPDIR/nix" \
      -f ${classify} < /dev/null || exit 1

  touch $out
''
