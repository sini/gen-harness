# The commit hook's memory cap (`../memory-cap.nix`, den-hoag-a4rdd) as a flake CHECK: its exit status
# is the command's in every arm, so a kill at the cap or a red never reads as a pass, and the cap's
# values reach `systemd-run`. The sandbox has no user manager, so the systemd arm runs against a stub
# that records its arguments and then runs the command; the real kill at the cap is measured outside
# the sandbox (the a4rdd spec's probe). The cell count is held with equality.
# shortcut: Linux-only cells (memory-cap.nix execs directly on Darwin); split the expectation when a darwin column builds checks.
{ ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      cells = 12;
      cap = import ../memory-cap.nix {
        inherit pkgs;
        name = "oracle";
        memoryMax = "7M";
        swapMax = "3M";
      };
    in
    {
      checks.memory-cap = pkgs.runCommand "gen-harness-memory-cap-cells" { } ''
        set -uo pipefail
        bash=${pkgs.bash}/bin/bash
        cell() { if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1: got [$2] want [$3]"; fi; }
        run() { rc=0; ${cap} "$@" > out 2> err || rc=$?; }
        mkdir stub
        # A user manager is reachable: the probe `true` succeeds, and the run records its arguments.
        printf '#!%s\nif [ "$*" = "--user --scope -q true" ]; then exit 0; fi\nprintf "%%s\\n" "$*" > %s/stub.args\nwhile [ "$1" != -- ]; do shift; done; shift; exec "$@"\n' \
          "$bash" "$PWD" > stub/systemd-run
        chmod +x stub/systemd-run
        {
          PATH=$PWD/stub:$PATH
          run true;                      cell stub-green "$rc" 0
          run false;                     cell stub-red "$rc" 1
          run "$bash" -c 'exit 75';      cell stub-75-passes-through "$rc" 75
          run "$bash" -c 'kill -9 $$';   cell stub-kill-is-137 "$rc" 137
          grep -q 'killed (exit 137)' err && k=named || k=unnamed
          cell stub-kill-named "$k" named
          cell stub-cap-values "$(cat stub.args)" "--user --scope -q --expand-environment=no -p MemoryMax=7M -p MemorySwapMax=3M -- $bash -c kill -9 \$\$"
          # The probe fails: no user manager. The command still runs, uncapped, and stderr says so.
          printf '#!%s\necho "Failed to connect to bus" >&2; exit 1\n' "$bash" > stub/systemd-run
          run "$bash" -c 'echo ran; exit 3'; cell nobus-status "$rc" 3
          cell nobus-ran "$(cat out)" ran
          grep -q 'WITHOUT the 7M memory cap' err && n=named || n=unnamed
          cell nobus-named "$n" named
          # No systemd-run on PATH at all (the sandbox as it is).
          rm stub/systemd-run
          run false;                     cell nopath-red "$rc" 1
          run "$bash" -c 'kill -9 $$';   cell nopath-kill-is-137 "$rc" 137
          grep -q 'systemd-run is not on PATH' err && n=named || n=unnamed
          cell nopath-named "$n" named
        } > cells.out
        cat cells.out
        n=$(grep -c '^PASS ' cells.out || true)
        f=$(grep -c '^FAIL ' cells.out || true)
        [ "$f" = 0 ] || { echo "memory-cap: $f cell(s) failed"; exit 1; }
        [ "$n" = ${toString cells} ] || { echo "memory-cap: collected $n cells, want exactly ${toString cells}"; exit 1; }
        echo "memory-cap: ${toString cells} cells" > $out
      '';
    };
}
