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
# passes on rc != 0 when its `msg` matches (Python `re.search`) the INNERMOST message: the text after
# the LAST `error: ` marker, with the 7-space continuation indentation stripped from every following
# line. That strip is not cosmetic — read literally, the multi-line `^...$` messages fail 11 correct
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

LIST = r"""
let
  plane = (builtins.getFlake (builtins.getEnv "GEN_REF")).testsError or { };
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
in go [ ] plane
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
    i = err.rfind("error: ")
    if i < 0:
        return err
    lines = err[i + len("error: "):].rstrip().split("\n")
    return "\n".join([lines[0]] + [ln[7:] if ln.startswith("       ") else ln for ln in lines[1:]])


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

    env = dict(os.environ, GEN_REF=f"git+file://{root}?dir=ci")
    r = nix_eval(env, LIST)
    if r.returncode != 0:
        print("CONTROL FAILED: the error plane could not be listed:\n" + r.stderr[-2000:], file=sys.stderr)
        return 2
    cells = json.loads(r.stdout)
    declared = os.path.exists(os.path.join(root, "ci", "tests-error.nix"))
    if not cells:
        if declared:
            print("0/0 successful — REFUSED: ci/tests-error.nix is declared and collected 0 cells, the false pass.")
            return 1
        print("0/0 — no error plane: ci/tests-error.nix is absent and testsError holds no cells.")
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
