# THE `lib.serialEval` CELLS, run first in this repository's process plane, under the column's own
# `nix-instantiate` and its own configuration (Determinate's installer writes `eval-cores = 0`). The
# verdict is evaluator-specific, so these are not a sandboxed check, where every column would run
# the ci-locked `pkgs.nix` (den-hoag-jutgv).
#
#   a1  after resolution the evaluator is serial: `nix config show eval-cores <options>` exits
#       non-zero (no such setting) or prints 1. Its red arm, where there is a setting to pin: the
#       same read with no options under `eval-cores = 0` prints 0, and the helper's options still 1.
#   a2  a counted evaluation with the options writes no `eval-cores` text on stderr. Its red arm,
#       where the options are empty: the unconditional `--option eval-cores 1` warns.
#   a3  the refusals, each rc 2 with CONTROL FAILED: no `nix` beside the argument, a bare name, a
#       `nix` whose control key fails, and one that does not read the pin back.
#
# It prints `serial-eval: serial options: <argv, or (none)>`, the line the CI log is read for.
{ pkgs, serialEval }:
pkgs.writeShellScriptBin "serial-eval-cells" ''
  set -uo pipefail
  export PATH=${
    pkgs.lib.makeBinPath [
      pkgs.coreutils
      pkgs.gnugrep
    ]
  }:$PATH
  # shellcheck disable=SC1091
  source ${serialEval}
  t=$(mktemp -d)
  trap 'rm -rf "$t"' EXIT
  ran=0
  fail() {
    echo "serial-eval: FAILED at cell $1: $2" >&2
    exit 1
  }

  ni=$(command -v nix-instantiate) || {
    echo "serial-eval: CONTROL FAILED: no nix-instantiate on PATH" >&2
    exit 2
  }
  nix=''${ni%/*}/nix
  rc=0
  serialEvalOptions "$ni" 2>"$t/he" || rc=$?
  [ "$rc" -eq 0 ] || fail resolve "serialEvalOptions $ni exited $rc: $(cat "$t/he")"
  [ ! -s "$t/he" ] || fail resolve "serialEvalOptions $ni wrote to stderr: $(cat "$t/he")"
  echo "serial-eval: serial options: ''${SERIAL_EVAL[*]:-(none)}"
  opts=("''${SERIAL_EVAL[@]}")

  # a1
  rc=0
  v=$("$nix" config show eval-cores "''${opts[@]}" 2>"$t/e") || rc=$?
  ran=$((ran + 1))
  if [ "$rc" -ne 0 ]; then
    [ "''${#opts[@]}" -eq 0 ] || fail a1 "the options are (''${opts[*]}) but $nix cannot name eval-cores: $(cat "$t/e")"
  else
    [ "$v" = 1 ] || fail a1 "eval-cores reads '$v' under (''${opts[*]}), not 1"
    [ "''${#opts[@]}" -gt 0 ] || fail a1 "$nix names eval-cores ($v) but the options are empty"
    rc=0
    v=$(NIX_CONFIG="''${NIX_CONFIG:-}"$'\neval-cores = 0' "$nix" config show eval-cores) || rc=$?
    ran=$((ran + 1))
    [ "$rc" -eq 0 ] && [ "$v" = 0 ] || fail a1-red "with no options under eval-cores = 0 the read is '$v' (rc $rc), not 0: the cell cannot see an unpinned run"
    rc=0
    v=$(NIX_CONFIG="''${NIX_CONFIG:-}"$'\neval-cores = 0' "$nix" config show eval-cores "''${opts[@]}") || rc=$?
    ran=$((ran + 1))
    [ "$rc" -eq 0 ] && [ "$v" = 1 ] || fail a1 "under eval-cores = 0 the options read '$v' (rc $rc), not 1"
    rc=0
    NIX_CONFIG="''${NIX_CONFIG:-}"$'\neval-cores = 0' serialEvalOptions "$ni" 2>"$t/he" || rc=$?
    ran=$((ran + 1))
    [ "$rc" -eq 0 ] && [ "''${SERIAL_EVAL[*]}" = "''${opts[*]}" ] || fail a1 "under eval-cores = 0 the helper resolves (''${SERIAL_EVAL[*]}) (rc $rc), not (''${opts[*]})"
  fi

  # a2
  counted() {
    rc=0
    rm -f "$t/s"
    NIX_SHOW_STATS=1 NIX_SHOW_STATS_PATH="$t/s" "$ni" "$@" --eval --strict --json --readonly-mode \
      -E 'builtins.genList (i: { inherit i; }) 10' >"$t/o" 2>"$t/e" || rc=$?
    ran=$((ran + 1))
    [ "$rc" -eq 0 ] || fail a2 "the counted evaluation exited $rc: $(cat "$t/e")"
    [ -s "$t/s" ] || fail a2 "the counted evaluation wrote no stats file"
    mentions=$(grep -c eval-cores "$t/e" || true)
  }
  counted "''${opts[@]}"
  [ "$mentions" = 0 ] || fail a2 "the counted evaluation wrote $mentions eval-cores lines on stderr: $(cat "$t/e")"
  if [ "''${#opts[@]}" -eq 0 ]; then
    counted --option eval-cores 1
    [ "$mentions" -ge 1 ] || fail a2-red "the unconditional pin wrote no eval-cores warning on an evaluator that has no such setting: the cell cannot see one"
  fi

  # a3: refuse <cell> <argument>: the helper exits 2 with CONTROL FAILED on stderr.
  refuse() {
    rc=0
    serialEvalOptions "$2" 2>"$t/he" || rc=$?
    ran=$((ran + 1))
    [ "$rc" -eq 2 ] || fail "$1" "serialEvalOptions $2 exited $rc, not 2"
    grep -q 'CONTROL FAILED' "$t/he" || fail "$1" "no CONTROL FAILED on stderr: $(cat "$t/he")"
    [ "''${#SERIAL_EVAL[@]}" -eq 0 ] || fail "$1" "a refusal left options set: ''${SERIAL_EVAL[*]}"
  }
  mkdir "$t/lonely" "$t/no-control" "$t/no-readback"
  ln -s "$ni" "$t/lonely/nix-instantiate"
  refuse a3-no-nix-beside "$t/lonely/nix-instantiate"
  refuse a3-bare-name nix-instantiate
  # A `nix` beside that fails the control key, and one that names eval-cores but never reads the pin back.
  for d in no-control no-readback; do
    ln -s "$ni" "$t/$d/nix-instantiate"
  done
  printf '#!${pkgs.runtimeShell}\nexit 1\n' >"$t/no-control/nix"
  printf '#!${pkgs.runtimeShell}\necho 0\n' >"$t/no-readback/nix"
  chmod +x "$t/no-control/nix" "$t/no-readback/nix"
  refuse a3-control-fails "$t/no-control/nix-instantiate"
  refuse a3-no-readback "$t/no-readback/nix-instantiate"

  # a1 is 1 cell and its red arm 3 more where there is a setting; a2 is 1, and its red arm 1 more where there is none.
  if [ "''${#opts[@]}" -eq 0 ]; then want=7; else want=9; fi
  [ "$ran" = "$want" ] || {
    echo "serial-eval: CONTROL FAILED: $ran of $want cells ran" >&2
    exit 2
  }
  echo "serial-eval: $ran cells held"
''
