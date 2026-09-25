# `ci --tests-process`: the PROCESS PLANE, judged by the evaluator the column installed.
#
# A consumer's per-process cells (`ci/tests-process.nix`) assert on an evaluator's abort channels
# — an exit status, `infinite recursion encountered`, `division by zero`, a `trace:` count, the
# ABSENCE of a named refusal — which is evaluator-implementation text and control flow, the place
# implementations differ. A verdict is evidence only for the evaluator that computed it, so the
# cells cannot run in a build sandbox: there the evaluator is a derivation input, one drvPath
# under every evaluator, one verdict substituted into every column (den-hoag-jutgv). They run as a
# PROGRAM, `apps.<system>.tests-process`, whose `nix-instantiate` is the one on PATH.
#
# The consumer's contract, stated once here:
#   - the program's closure carries NO evaluator (refused below — the guard's reason);
#   - it prints `evaluator: <line 1 of nix-instantiate --version>` from its OWN process, the binary
#     its cells call, which `evaluators.yml` compares with the column's;
#   - it runs in a fresh directory of its own (a cell that writes to the CWD finds a previous run's
#     debris otherwise — measured, gen-scope's `hctl2`).
#
# ★ RESOLUTION IS BY CLI REF, never `builtins.getFlake "git+file://…"`: CI checks out at depth 1,
# where a `git+file` ref without `&shallow=1` is refused by Determinate and Lix. And an app's
# `program` is a SUBPATH string (`…/bin/tests-process`), which `nix build` refuses under all three
# evaluators ("not the right placeholder for this derivation output"), so the build target is the
# derivation the string's context names, `<drv>^<outputs>`.
{
  pkgs,
  name,
}:
let
  inherit (pkgs) lib;
  system = pkgs.stdenv.hostPlatform.system;

  # ★ THE PREDICATE IS OVER OUTPUT PATHS, the form `nix-store -qR` prints. A predicate over `.drv`
  # basenames reads 0 on a `runtimeInputs = [ pkgs.nix ]` program and passes the input it exists to
  # refuse (gate den-hoag-jutgv F-C1). The names cover `nixVersions.*.nix-cli` and
  # `.nix-everything` (both `nix-2.x.y`) and `lix` (`lix-2.x.y`).
  evaluatorPath = "^/nix/store/[a-z0-9]{32}-(nix-2\\.[0-9.]+|lix-[0-9][^/]*|determinate-nix-[0-9][^/]*|nix-unit-[^/]*|nix-eval-jobs-[^/]*)$";

  # Refuses a program whose runtime closure carries an evaluator. Such a program shadows the
  # column's evaluator SILENTLY: under a Lix PATH, a `runtimeInputs = [ pkgs.nix ]` runner calls
  # `nix-instantiate (Nix) 2.34.8` (measured).
  #
  # `nix-store` is the one on PATH — the column's — deliberately not a runtimeInput.
  # EXIT: 0 no evaluator · 1 REFUSED, naming the paths · 2 CONTROL FAILED, the closure was not read.
  guard = pkgs.writeShellApplication {
    name = "${name}-ci-evaluator-closure";
    runtimeInputs = [
      pkgs.gnugrep
      pkgs.coreutils
    ];
    text = ''
      prog=$1
      err=$(mktemp)
      trap 'rm -f "$err"' EXIT
      rc=0
      clos=$(nix-store -qR "$prog" 2>"$err") || rc=$?
      if [ "$rc" -ne 0 ]; then
        printf 'CONTROL FAILED: the closure of %s was not read (nix-store -qR rc=%s): %s\n' "$prog" "$rc" "$(cat "$err")"
        exit 2
      fi
      # ★ EMPTY IS NOT CLEAN. A closure always contains its root, and Determinate 3.22.5 answers
      # `nix-store -qR` on an unrealised path with rc 0 and NO output (upstream 2.34.8 and Lix
      # 2.95.2 answer rc 1; measured, one run). An empty list is an unread closure.
      if [ -z "$clos" ]; then
        printf 'CONTROL FAILED: nix-store -qR %s answered rc 0 with an empty closure\n' "$prog"
        exit 2
      fi
      rc=0
      hits=$(grep -E ${lib.escapeShellArg evaluatorPath} <<<"$clos") || rc=$?
      if [ "$rc" -eq 0 ]; then
        printf 'REFUSED: the process-plane program carries an evaluator in its closure, so its cells would run under THAT evaluator and not the column'"'"'s:\n%s\n' "$hits"
        echo "Remedy: drop the evaluator from the program (no pkgs.nix / pkgs.lix in runtimeInputs or interpolated into its text); its cells call the nix-instantiate on PATH."
        exit 1
      fi
      if [ "$rc" -ne 1 ]; then
        printf 'CONTROL FAILED: the evaluator predicate did not run (grep rc=%s)\n' "$rc"
        exit 2
      fi
    '';
  };
in
pkgs.writeShellApplication {
  name = "${name}-ci-tests-process";
  runtimeInputs = [ pkgs.coreutils ];
  # `nix` is the column's, from PATH — never a runtimeInput, for the reason the guard exists.
  text = ''
    root=$1
    # `--userns-binaries`: build the program as below, then print, one per line on stdout and
    # nothing else there, every `bin/unshare` in its runtime closure — the binaries a CI step with
    # the privilege may admit to user namespaces (`evaluators.yml`, den-hoag-348bq). Everything
    # else this mode says goes to stderr. EXIT: 0 read (an empty list is a closure with no
    # unshare) · 1 REFUSED · 2 CONTROL FAILED, the closure was not read.
    mode=''${2:-}
    case "$mode" in
    "") ;;
    --userns-binaries) exec 3>&1 1>&2 ;;
    *)
      echo "CONTROL FAILED: unknown process-plane mode '$mode'" >&2
      exit 2
      ;;
    esac
    # ★ KEYED ON THE FILE NAME, as `evaluators.yml`'s step is: a process plane declared under any
    # other name is skipped silently by both (ci-plane-coverage's to learn; den-hoag-jutgv G2).
    if [ ! -e "$root/ci/tests-process.nix" ]; then
      echo "no process plane: ci/tests-process.nix is absent"
      exit 0
    fi
    ref="$root/ci#apps.${system}"
    err=$(mktemp)
    trap 'rm -f "$err"' EXIT

    rc=0
    has=$(nix eval "$ref" --apply 'a: a ? tests-process' 2>"$err") || rc=$?
    if [ "$rc" -ne 0 ]; then
      printf 'CONTROL FAILED: %s could not be evaluated (rc=%s):\n%s\n' "$ref" "$rc" "$(cat "$err")"
      exit 2
    fi
    if [ "$has" != true ]; then
      echo "REFUSED: ci/tests-process.nix is declared but apps.${system}.tests-process is not."
      echo "Remedy: expose the runner as a program, perSystem apps.tests-process (the cells run under the column's evaluator, outside the build sandbox); a checks.tests-process runs them under the ci-locked pkgs.nix in every column."
      exit 1
    fi

    rc=0
    # shellcheck disable=SC2016 # a Nix expression, not a shell one
    targets=$(nix eval --raw "$ref.tests-process.program" --apply \
      'p: builtins.concatStringsSep "\n" (map (k: let c = (builtins.getContext p).''${k}; in if c ? outputs then k + "^" + builtins.concatStringsSep "," c.outputs else k) (builtins.attrNames (builtins.getContext p)))' \
      2>"$err") || rc=$?
    if [ "$rc" -ne 0 ] || [ -z "$targets" ]; then
      printf 'CONTROL FAILED: the program'"'"'s derivation could not be read (rc=%s):\n%s\n' "$rc" "$(cat "$err")"
      exit 2
    fi
    mapfile -t tgt <<<"$targets"
    nix build --no-link "''${tgt[@]}" || { echo "CONTROL FAILED: the process-plane program did not build"; exit 2; }
    prog=$(nix eval --raw "$ref.tests-process.program")

    if [ "$mode" = --userns-binaries ]; then
      rc=0
      clos=$(nix-store -qR "$prog" 2>"$err") || rc=$?
      if [ "$rc" -ne 0 ] || [ -z "$clos" ]; then
        printf 'CONTROL FAILED: the closure of %s was not read (nix-store -qR rc=%s): %s\n' "$prog" "$rc" "$(cat "$err")"
        exit 2
      fi
      while IFS= read -r p; do
        if [ -x "$p/bin/unshare" ]; then
          # The path the kernel attaches a profile to is the RESOLVED one.
          readlink -f "$p/bin/unshare" >&3
        fi
      done <<<"$clos"
      exit 0
    fi

    "${guard}/bin/${name}-ci-evaluator-closure" "$prog" || exit $?
    exec "$prog"
  '';
  passthru = { inherit guard evaluatorPath; };
}
