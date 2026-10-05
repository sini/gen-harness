# The EVALUATOR-NEUTRAL runner for `flake.testsError`, reached as `ci --tests-error`.
#
# WHY IT EXISTS. nix-unit is linked against one upstream nix-expr, so the cells it runs are evaluated
# by THAT library whatever `nix` the job installed: a divergence under Lix or Determinate is
# invisible to it. This runner evaluates every cell with the `nix` found on PATH — the evaluator
# the column installed — so the error plane is judged by the evaluator the column names
# (den-hoag-lbtnv, spec §2.4).
#
# ★ COLLECTION IS nix-unit's RULE, not "a node carrying `expr`": a `test`-prefixed attribute is a
# cell and is not descended into; any other attrset is descended into. That is
# `ci-plane-coverage.nix`'s `leafCount`, so the two count the same unit by construction.
#
# ★ ONE PROCESS PER CELL, because `builtins.tryEval` cannot catch four of Nix's error classes, so no
# batching expression can hold a cell that aborts.
#
# ★ THE PASS PREDICATE. An `expected` cell passes on rc 0 printing `true`. An `expectedError` cell
# passes on rc != 0 when its `msg` matches (Python `re.search`) the INNERMOST message: with the 7-space
# continuation indentation stripped from every line, the text from the LAST line that BEGINS `error: `.
# A marker inside a message is not a boundary: a refusal reading `…: unexpected validation error: "s"`
# is read whole, never cut to its tail (den-hoag-25dd7). That strip is not cosmetic — read literally, the multi-line `^...$` messages fail 11 correct
# gen-merge cells (145 -> 134; gate den-hoag-lbtnv C4). `expectedError.type` is NOT checked: the CLI
# does not print the error class. The `nix` column keeps nix-unit for that.
#
# EXIT: 0 all cells pass · 1 a cell failed, or a declared plane collected 0 cells (the 0/0 false
# pass) · 2 the runner could not measure (the listing failed). Never a zero for "could not measure".
import json
import os
import re
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor

ANSI = re.compile(r"\x1b\[[0-9;]*[A-Za-z]")

# The listing and the declaration in ONE evaluation. `errorPlane.declared` is read without `or`: a flake
# that does not publish it cannot say whether its plane is declared, and the listing refuses (rc 2).
LIST = r"""
let
  flake = builtins.getFlake (builtins.getEnv "GEN_REF");
  plane = flake.testsError or { };
  hasPrefix = p: s: builtins.substring 0 (builtins.stringLength p) s == p;
  go = pre: set: builtins.concatMap (a:
    let v = set.${a}; in
    if hasPrefix "test" a then [ {
      path = pre ++ [ a ];
      error = v ? expectedError;
      msg = if v ? expectedError then v.expectedError.msg or "" else "";
    } ]
    else if builtins.isAttrs v then go (pre ++ [ a ]) v
    else [ ]) (builtins.attrNames set);
in { declared = flake.errorPlane.declared; cells = go [ ] plane; }
"""

# An `expectedError` cell returns "NOERROR" only if its expr forces deeply without error; an
# `expected` cell returns `expr == expected`, both forced deeply first, as nix-unit does.
CELL = r"""
let
  c = builtins.foldl' (v: n: v.${n}) (builtins.getFlake (builtins.getEnv "GEN_REF")).testsError
    (builtins.fromJSON (builtins.getEnv "GEN_CELL"));
in
if c ? expectedError then builtins.deepSeq c.expr "NOERROR"
else builtins.deepSeq c.expr (builtins.deepSeq c.expected (c.expr == c.expected))
"""


def errmsg(err):
    lines = [ln[7:] if ln.startswith("       ") else ln for ln in err.rstrip().split("\n")]
    starts = [i for i, ln in enumerate(lines) if ln.startswith("error: ")]
    if not starts:
        return err
    i = starts[-1]
    return "\n".join([lines[i][len("error: "):]] + lines[i + 1:])


def nix_eval(env, expr):
    return subprocess.run(
        ["nix", "eval", "--impure", "--json", "--expr", expr],
        capture_output=True, text=True, env=env,
    )


def main():
    root = sys.argv[1]
    try:
        ver = subprocess.run(["nix", "--version"], capture_output=True, text=True, check=True)
    except (OSError, subprocess.CalledProcessError) as e:
        print(f"CONTROL FAILED: no runnable `nix` on PATH: {e}", file=sys.stderr)
        return 2
    # Line 1 only: Lix prints several lines, upstream and Determinate one.
    print("evaluator: " + ver.stdout.splitlines()[0])

    # `shallow=1` because CI checks out at depth 1, and the three evaluators DIVERGE on a shallow
    # `git+file` ref without it: upstream accepts it, Determinate refuses ("'revCount' is not
    # available") and Lix refuses ("shallow repositories are only allowed when `shallow = true;`").
    # With it all three read the same tree, shallow or not (measured, gen-harness b60292b CI run
    # 36045352952 and a local depth-1 clone).
    # The second argument overrides the ref: `checks.tests-error` (`error-plane-check.nix`) runs this
    # program in a build sandbox over an offline `path:` copy of the tree.
    ref = sys.argv[2] if len(sys.argv) > 2 else f"git+file://{root}?dir=ci&shallow=1"
    env = dict(os.environ, GEN_REF=ref)
    r = nix_eval(env, LIST)
    if r.returncode != 0:
        print("CONTROL FAILED: the error plane could not be listed:\n" + r.stderr[-2000:], file=sys.stderr)
        return 2
    listing = json.loads(r.stdout)
    # The declaration is the CELLS (`error-plane-declared.nix`), never a file name (den-hoag-o7kjc).
    cells, declared = listing["cells"], listing["declared"]
    if not cells:
        if declared:
            print("0/0 successful — REFUSED: an error plane is declared (errorPlane.declared) and collected 0 cells, the false pass.")
            return 1
        print("0/0 — no error plane: errorPlane.declared is false and testsError holds no cells.")
        return 0

    def run(c):
        name = ".".join(c["path"])
        q = nix_eval(dict(env, GEN_CELL=json.dumps(c["path"])), CELL)
        err = ANSI.sub("", q.stderr)
        if not c["error"]:
            if q.returncode == 0 and q.stdout.strip() == "true":
                return name, None
            return name, "false" if q.returncode == 0 else "error: " + err.strip()[-800:]
        if q.returncode == 0:
            return name, "NOERROR: the expr evaluated without error"
        if c["msg"] and not re.search(c["msg"], errmsg(err)):
            return name, f"MSGMISS /{c['msg']}/ in: " + errmsg(err)[-800:]
        return name, None

    with ThreadPoolExecutor(os.cpu_count() or 4) as ex:
        res = list(ex.map(run, cells))
    bad = [(n, why) for n, why in res if why is not None]
    for n, why in res:
        print(("❌ " if why else "✅ ") + n)
    for n, why in bad:
        print(f"\nFAIL {n}\n  {why}")
    print(f"\n{len(cells) - len(bad)}/{len(cells)} successful")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
