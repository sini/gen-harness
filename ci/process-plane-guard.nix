# Wires the process-plane closure guard's arms into THIS repository's checks (den-hoag-jutgv C1).
#
# The guard (`process-plane.nix`, `passthru.guard`) reads a program's closure with `nix-store -qR`
# and refuses an evaluator in it. The sandbox cannot reach the store's database, so the closures
# here are `closureInfo`'s `store-paths` — the same output-path list `-qR` prints — served by a stub
# `nix-store` first on PATH. The guard binary is the shipped one, reached through the published
# `lib.processPlane`; the fixtures are real programs over the ci-locked nixpkgs.
#
# Arms, each read by exit status AND text:
#   `runtimeInputs = [ ]`          -> 0
#   `runtimeInputs = [ pkgs.nix ]` -> 1, REFUSED naming a `nix-2.x` path
#   `runtimeInputs = [ pkgs.lix ]` -> 1, REFUSED naming a `lix-2.x` path
#   `nix-store` rc 1               -> 2, CONTROL FAILED (never a count of zero)
#   `nix-store` rc 0, no output    -> 2, CONTROL FAILED (Determinate's answer on an unrealised path)
{ inputs, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      guard =
        (inputs.gen-harness.lib.processPlane {
          inherit pkgs;
          name = "gen-harness";
        }).guard;
      fixture =
        n: inputs':
        pkgs.closureInfo {
          rootPaths = [
            (pkgs.writeShellApplication {
              name = "process-plane-fixture-${n}";
              runtimeInputs = inputs';
              text = "nix-instantiate --version";
            })
          ];
        };
    in
    {
      checks.process-plane-guard =
        pkgs.runCommand "gen-harness-process-plane-guard"
          {
            empty = fixture "empty" [ ];
            withNix = fixture "nix" [ pkgs.nix ];
            withLix = fixture "lix" [ pkgs.lix ];
          }
          ''
            mkdir bin
            cat > bin/nix-store <<'EOF'
            #!${pkgs.runtimeShell}
            [ "$1" = -qR ] || exit 3
            case "$2" in
              unreadable) echo "stub: path is not valid" >&2; exit 1 ;;
              silent) exit 0 ;;
              *) cat "$2/store-paths" ;;
            esac
            EOF
            chmod +x bin/nix-store
            export PATH=$PWD/bin:$PATH
            g=${guard}/bin/gen-harness-ci-evaluator-closure

            arm() { # <name> <arg> <want-rc> <want-text>
              rc=0
              "$g" "$2" > "$1.out" 2>&1 || rc=$?
              cat "$1.out"
              [ "$rc" = "$3" ] || { echo "ARM $1: rc $rc, wanted $3"; exit 1; }
              grep -Eq "$4" "$1.out" || { echo "ARM $1: output lacks /$4/"; exit 1; }
            }
            # The empty arm's text predicate is the ABSENCE of both verdict words.
            rc=0; "$g" "$empty" > empty.out 2>&1 || rc=$?
            [ "$rc" = 0 ] || { cat empty.out; echo "ARM empty: rc $rc, wanted 0"; exit 1; }
            if grep -Eq 'REFUSED|CONTROL FAILED' empty.out; then echo "ARM empty: a verdict fired"; exit 1; fi
            [ "$(wc -l < "$empty/store-paths")" -gt 0 ] || { echo "ARM empty: the fixture closure is empty"; exit 1; }
            arm nix "$withNix" 1 '^REFUSED: '
            grep -Eq '^/nix/store/[a-z0-9]{32}-nix-2\.[0-9.]+$' nix.out || { echo "ARM nix: no nix-2.x path named"; exit 1; }
            arm lix "$withLix" 1 '^REFUSED: '
            grep -Eq '^/nix/store/[a-z0-9]{32}-lix-2\.' lix.out || { echo "ARM lix: no lix-2.x path named"; exit 1; }
            arm unreadable unreadable 2 '^CONTROL FAILED: .*rc=1'
            arm silent silent 2 '^CONTROL FAILED: .*empty closure'
            echo "process-plane-guard: 5 arms" > $out
          '';
    };
}
