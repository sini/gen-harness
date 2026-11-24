# Wires `lockEvaluator`'s arms into THIS repository's checks (den-hoag-bqn7r).
#
# `lockEvaluator` (`process-plane.nix`, `passthru.lockEvaluator`) runs a command on the ci lock's
# engine: unchanged when PATH's `nix` and `nix-instantiate` already are that engine with CI's
# settings, else with the engine realised and put first. Here the engine is a STUB derivation, handed
# through the published `lib.processPlane`'s `lockEngines`, whose `nix` answers `config show` from a
# file and `build --out-link` by linking itself. A second stub `nix`, outside the engine, plays the
# host's. The binary is the shipped construction over those stubs.
#
# Arms, each read by exit status AND text:
#   found                         -> 0, `(found on PATH)`, the env the command sees is the caller's
#                                    but for `_`
#   found, a non-CI setting       -> 0, pinned, naming the setting (never refused)
#   found, NIX_PATH set           -> 0, pinned, naming NIX_PATH
#   no setting to check           -> 2, CONTROL FAILED, the command not run
#   `nix config show` fails       -> 2, CONTROL FAILED, the command not run
#   `nix` outside, `nix-instantiate` inside the engine -> 0, pinned
#   `nix` inside, no `nix-instantiate`                 -> 0, pinned
#   pinned                        -> 0, the engine's bin first, its conf appended after the caller's
#                                    NIX_CONFIG, NIX_PATH unset, the root linked to the engine
#   the realise fails             -> 1, REFUSED, the command not run
{ inputs, ... }:
{
  perSystem =
    { pkgs, lib, ... }:
    let
      settings = "show-trace = false\nallow-import-from-derivation = false\n";
      stubNix = ''
        #!${pkgs.runtimeShell}
        case "$1 $2" in
          "config show")
            [ -z "''${STUB_CONF_FAIL:-}" ] || { echo "stub: config show refused" >&2; exit 1; }
            v=$(${pkgs.gnused}/bin/sed -n "s/^$3 = //p" "$STUB_CONF")
            [ -n "$v" ] || exit 1
            echo "$v" ;;
          "build --out-link")
            [ -z "''${STUB_BUILD_FAIL:-}" ] || { echo "stub: build refused" >&2; exit 1; }
            [ "$4" = "$STUB_DRV^out" ] || { echo "stub: build of '$4', not '$STUB_DRV^out'" >&2; exit 3; }
            ${pkgs.coreutils}/bin/ln -sfn "$STUB_OUT" "$3" ;;
          *) echo "stub: unexpected nix $*" >&2; exit 3 ;;
        esac
      '';
      engine = pkgs.runCommand "lock-evaluator-stub-engine" { inherit stubNix; } ''
        mkdir -p $out/bin
        printf '%s' "$stubNix" > $out/bin/nix
        chmod +x $out/bin/nix
        ln -s nix $out/bin/nix-instantiate
      '';
      lockEngines = evalConf: {
        family = "nix";
        inherit evalConf;
        engines.nix = {
          pkg = engine;
          conf = "experimental-features = nix-command flakes\n";
        };
      };
      le =
        evalConf:
        (inputs.gen-harness.lib.processPlane {
          inherit pkgs;
          name = "gen-harness";
          lockEngines = lockEngines evalConf;
        }).lockEvaluator;
    in
    {
      checks.lock-evaluator =
        pkgs.runCommand "gen-harness-lock-evaluator"
          {
            inherit stubNix;
            STUB_OUT = engine;
            STUB_DRV = builtins.unsafeDiscardOutputDependency engine.drvPath;
            le = le settings;
            leEmpty = le "";
          }
          ''
            set -u
            C=${pkgs.coreutils}/bin
            G=${pkgs.gnugrep}/bin/grep
            mkdir host only root
            printf '%s' "$stubNix" > host/nix; chmod +x host/nix
            ln -s "$STUB_OUT/bin/nix" only/nix
            printf '%s' "${settings}" > ci.conf
            printf '%sshow-trace = true\n' "${settings}" | $G -v '^show-trace = false$' > bad.conf
            export STUB_CONF=$PWD/ci.conf STUB_OUT STUB_DRV
            unset NIX_PATH
            base=$PATH
            l=$le/bin/gen-harness-ci-lock-evaluator
            # run <arm> <PATH> <want-rc> <stderr-regex> [env assignments…] — the command prints its env.
            run() {
              local arm=$1 p=$2 want=$3 re=$4 rc=0
              shift 4
              $C/env "$@" PATH="$p" "$l" "$PWD/root" $C/env > "$arm.env" 2> "$arm.err" || rc=$?
              cat "$arm.err"
              [ "$rc" = "$want" ] || { echo "ARM $arm: rc $rc, wanted $want"; exit 1; }
              $G -Eq "$re" "$arm.err" || { echo "ARM $arm: stderr lacks /$re/"; exit 1; }
            }
            ran() { [ -s "$1.env" ] || { echo "ARM $1: the command did not run"; exit 1; }; }
            notRan() { [ ! -s "$1.env" ] || { echo "ARM $1: the command ran"; exit 1; }; }
            first() { $G -q "^PATH=$STUB_OUT/bin:" "$1.env" || { echo "ARM $1: the engine's bin is not first on PATH"; exit 1; }; }

            # found: the whole env, but for `_`, is the caller's.
            run found "$STUB_OUT/bin:$base" 0 '^lock evaluator: nix .* \(found on PATH\)$'
            PATH="$STUB_OUT/bin:$base" $C/env | $G -v '^_=' | $C/sort > found.want
            $G -v '^_=' found.env | $C/sort > found.got
            ${pkgs.diffutils}/bin/diff found.want found.got || { echo "ARM found: the env changed"; exit 1; }
            [ "$($C/wc -l < found.want)" -gt 3 ] || { echo "ARM found: the env compared is empty"; exit 1; }

            run setting "$STUB_OUT/bin:$base" 0 '\(pinned; PATH had .* non-CI settings: show-trace = true\)$' STUB_CONF=$PWD/bad.conf
            ran setting; first setting
            run nixpath "$STUB_OUT/bin:$base" 0 '\(pinned; PATH had .* non-CI settings: NIX_PATH set\)$' NIX_PATH=nixpkgs=/x
            ran nixpath; first nixpath

            l=$leEmpty/bin/gen-harness-ci-lock-evaluator
            run nosetting "$STUB_OUT/bin:$base" 2 '^CONTROL FAILED: no ci-lock setting to check$'
            notRan nosetting
            l=$le/bin/gen-harness-ci-lock-evaluator

            run showfails "$STUB_OUT/bin:$base" 2 "^CONTROL FAILED: .* could not report 'show-trace'" STUB_CONF_FAIL=1
            notRan showfails

            run split "$PWD/host:$STUB_OUT/bin:$base" 0 '\(pinned; PATH had nix [^,]*/host/nix, nix-instantiate '"$STUB_OUT"'/bin/nix\)$'
            ran split; first split
            run noinst "$PWD/only" 0 '\(pinned; PATH had nix '"$STUB_OUT"'/bin/nix, nix-instantiate absent\)$'
            ran noinst; first noinst

            run pinned "$PWD/host:$base" 0 '^lock evaluator: nix .* \(pinned; PATH had nix .*/host/nix, nix-instantiate absent\)$' NIX_PATH=nixpkgs=/x NIX_CONFIG='netrc-file = /n'
            ran pinned; first pinned
            if $G -q '^NIX_PATH=' pinned.env; then echo "ARM pinned: NIX_PATH survived"; exit 1; fi
            $C/tr '\n' '|' < pinned.env | $G -q 'NIX_CONFIG=netrc-file = /n|show-trace = false|allow-import-from-derivation = false|experimental-features = nix-command flakes|' \
              || { echo "ARM pinned: NIX_CONFIG is not the caller's then the engine's conf"; exit 1; }
            [ "$($C/readlink root/ci/.gcroots/evaluator-nix)" = "$STUB_OUT" ] || { echo "ARM pinned: the root does not hold the engine"; exit 1; }

            run nobuild "$PWD/host:$base" 1 '^REFUSED: the ci lock.s nix evaluator .* could not be realised; PATH had nix .*/host/nix' STUB_BUILD_FAIL=1
            notRan nobuild
            echo "lock-evaluator: 10 arms" > $out
          '';
    };
}
