# `memoryCap` — runs a command under the host's memory cap, for the commit hook's nix-unit runners
# (den-hoag-a4rdd). A git commit is not a command an author thinks of as an evaluation, so it is the
# one evaluation no caller wraps: the cap is held HERE, by construction, rather than by every
# author remembering to run `git commit` under `systemd-run`.
#
# `{ pkgs, name, memoryMax ? "12G", swapMax ? "2G" }` -> a script: `memory-cap <cmd> [args…]`.
#
#   systemd user manager reachable   the command runs in a scope of its own with MemoryMax and
#                                    MemorySwapMax set (MemoryMax alone leaves swap unbounded).
#                                    `--expand-environment=no` because systemd-run otherwise expands
#                                    `$VAR` / `${VAR}` / `$$` in the command's own arguments.
#   Darwin                           no instrument; the command runs as it is (the cap is Linux-only,
#                                    omitted on darwin, with no substitute).
#   Linux, no user manager           the command runs uncapped, and one stderr line names why. Refusing
#                                    would leave `--no-verify`, which runs no plane at all.
#
# The command's exit status is the script's in every arm. A kill at the cap is exit 137 and is
# named on stderr; it never reads as a pass.
{
  pkgs,
  name,
  memoryMax ? "12G",
  swapMax ? "2G",
}:
pkgs.writeShellScript "${name}-memory-cap" ''
  set -uo pipefail
  if [ "$(uname -s)" = Darwin ]; then exec "$@"; fi
  if ! command -v systemd-run >/dev/null; then
    echo "gen-harness: systemd-run is not on PATH, so $1 runs WITHOUT the ${memoryMax} memory cap" >&2
    exec "$@"
  fi
  if ! why=$(systemd-run --user --scope -q true 2>&1); then
    echo "gen-harness: no systemd user manager ($why), so $1 runs WITHOUT the ${memoryMax} memory cap" >&2
    exec "$@"
  fi
  rc=0
  systemd-run --user --scope -q --expand-environment=no \
    -p MemoryMax=${memoryMax} -p MemorySwapMax=${swapMax} -- "$@" || rc=$?
  if [ "$rc" -eq 137 ]; then
    echo "gen-harness: $1 was killed (exit 137), at the ${memoryMax} memory cap or by another SIGKILL: a possible memory regression, and a red" >&2
  fi
  exit "$rc"
''
