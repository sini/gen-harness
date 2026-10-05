# Wires the commit hook's gating oracle into THIS repository's checks
# (den-hoag-commit-hook-stash-shared-checkout-ddjy2). The subject is the shipped construction,
# reached through the published `lib.stagedCommitHook` — the same file `flakeModule.nix` installs —
# built over a config of two probe hooks and one declared chained command. The cells are
# `staged-commit-hook-oracle.sh`; this derivation holds their COUNT, with equality, because a run
# that silently collects fewer cells reads exactly like a green.
#
# The two closure cells are held here rather than in the script: the GC root covers the hook
# derivation, so the hook's closure must hold the pre-commit package and the config it names, or a
# collection leaves the slot exec'ing a dead path (den-hoag-z72's class).
{ inputs, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      cells = 24;
      witness = pkgs.writeShellScript "witness" ''
        sha256sum "$ORACLE_REPO/u.txt" | cut -c1-64 > "$ORACLE_WORK/in-window.sha"
        if [ -s "$ORACLE_WORK/target" ]; then echo late >> "$ORACLE_REPO/$(cat "$ORACLE_WORK/target")"; fi
      '';
      noBad = pkgs.writeShellScript "no-bad" ''! grep -l BAD "$@"'';
      config = pkgs.writeText "staged-commit-hook-oracle-config.yaml" ''
        repos:
          - repo: local
            hooks:
              - {id: no-bad, name: no-bad, entry: ${noBad}, language: unsupported, files: '^c\.txt$'}
              - {id: witness, name: witness, entry: ${witness}, language: unsupported, always_run: true, pass_filenames: false}
      '';
      package = pkgs.pre-commit;
      staged = inputs.gen-harness.lib.stagedCommitHook {
        inherit pkgs package;
        configFile = config;
        chained = [ "chain.sh" ];
      };
      closure = pkgs.closureInfo { rootPaths = [ staged.hook ]; };
    in
    {
      checks.staged-commit-hook =
        pkgs.runCommand "gen-harness-staged-commit-hook-cells"
          {
            nativeBuildInputs = [
              pkgs.git
              package
            ];
            HOOK = staged.hook;
            INSTALL = staged.install;
          }
          ''
            rc=0
            bash ${./staged-commit-hook-oracle.sh} > cells.out 2>&1 || rc=$?
            held() { if grep -qxF "$1" ${closure}/store-paths; then echo "PASS $2"; else echo "FAIL $2: $1 not in the hook's closure"; rc=1; fi; }
            held ${package} hook-closure-holds-package >> cells.out
            held ${config} hook-closure-holds-config >> cells.out
            cat cells.out
            n=$(grep -c '^PASS ' cells.out || true)
            [ "$rc" = 0 ] || { echo "staged-commit-hook: a cell failed"; exit 1; }
            [ "$n" = ${toString cells} ] || { echo "staged-commit-hook: collected $n cells, want exactly ${toString cells}"; exit 1; }
            echo "staged-commit-hook: ${toString cells} cells" > $out
          '';
    };
}
