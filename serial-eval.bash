# THE SERIAL OPTIONS OF A COUNTED RUN, sourced by every runner that reads `NIX_SHOW_STATS` counters.
#
# A thunk count is defined only for a serial evaluation. An evaluator with a parallel evaluator
# (Determinate's `eval-cores`) creates thunks in an order the scheduler picks, so its counters are a
# random sample unless the run is serial. The column's own `eval-cores` stays as the column
# installed it: only an evaluation that writes stats carries these options, as argv, so correctness
# cells keep running under the parallel evaluator.
#
# DETECTION IS BY CAPABILITY, never by `--version`: the setting is asked for by name, of the `nix`
# beside the given `nix-instantiate`.
# shortcut: keys on the setting name eval-cores; a parallel evaluator under another name needs a second probe here.
#
# serialEvalOptions <nix-instantiate path>: sets the array SERIAL_EVAL to the options that make an
# evaluation by that binary serial. Resolve it once per runner, never per evaluation (three `nix`
# processes). EXIT: 0 resolved (an empty array is an evaluator with no parallel evaluator) · 2 CONTROL FAILED.
serialEvalOptions() {
  local nix=${1%/*}/nix err
  SERIAL_EVAL=()
  [ -x "$nix" ] || {
    echo "serial-eval: CONTROL FAILED: no nix beside '$1'" >&2
    return 2
  }
  # The control key: every evaluator names show-trace, so a refusal here is the probe's, never an absence.
  err=$("$nix" config show show-trace 2>&1 >/dev/null) || {
    echo "serial-eval: CONTROL FAILED: $nix config show show-trace: $err" >&2
    return 2
  }
  # An evaluator that cannot name eval-cores has no parallel evaluator: its evaluation is serial already.
  "$nix" config show eval-cores >/dev/null 2>&1 || return 0
  # The pin's own read-back: the argv must beat an `eval-cores = 0` in nix.conf or NIX_CONFIG.
  [ "$("$nix" config show eval-cores --option eval-cores 1)" = 1 ] || {
    echo "serial-eval: CONTROL FAILED: $nix does not read --option eval-cores 1 back as 1" >&2
    return 2
  }
  SERIAL_EVAL=(--option eval-cores 1)
}
