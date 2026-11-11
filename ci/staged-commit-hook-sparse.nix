# The commit hook's SPARSE export, as a gating oracle. The subject is the published
# `lib.stagedCommitHook`, built with `wholeTree` (staged-commit-hook.nix, "WHY THE EXPORT IS
# SPARSE"). The config holds two hooks:
# - a files-scoped `lister`, which records which files exist in the export and refuses a staged
#   `BAD`;
# - a whole-tree `wt` on `^w\.nix$`, which records that it ran.
# The cells are `staged-commit-hook-sparse-oracle.sh`. This derivation holds their COUNT, with
# equality, as `staged-commit-hook.nix` does, because a run that collects fewer cells reads as a
# green.
{ inputs, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      cells = 5;
      lister = pkgs.writeShellScript "lister" ''
        find . -path ./.git -prune -o -type f -print | sed 's|^\./||' | sort | tr '\n' ' ' > "$ORACLE_WORK/listing"
        ! grep -l BAD "$@"
      '';
      wt = pkgs.writeShellScript "wt" ''echo ran > "$ORACLE_WORK/wt-ran"'';
      config = pkgs.writeText "staged-commit-hook-sparse-config.yaml" ''
        repos:
          - repo: local
            hooks:
              - {id: lister, name: lister, entry: ${lister}, language: unsupported}
              - {id: wt, name: wt, entry: ${wt}, language: unsupported, files: '^w\.nix$', pass_filenames: false}
      '';
      package = pkgs.pre-commit;
      staged = inputs.gen-harness.lib.stagedCommitHook {
        inherit pkgs package;
        configFile = config;
        wholeTree = [ "^w\\.nix$" ];
      };
    in
    {
      checks.staged-commit-hook-sparse =
        pkgs.runCommand "gen-harness-staged-commit-hook-sparse-cells"
          {
            nativeBuildInputs = [
              pkgs.git
              package
            ];
            HOOK = staged.hook;
          }
          ''
            rc=0
            bash ${./staged-commit-hook-sparse-oracle.sh} > cells.out 2>&1 || rc=$?
            cat cells.out
            n=$(grep -c '^PASS ' cells.out || true)
            [ "$rc" = 0 ] || { echo "staged-commit-hook-sparse: a cell failed"; exit 1; }
            [ "$n" = ${toString cells} ] || { echo "staged-commit-hook-sparse: collected $n cells, want exactly ${toString cells}"; exit 1; }
            echo "staged-commit-hook-sparse: ${toString cells} cells" > $out
          '';
    };
}
