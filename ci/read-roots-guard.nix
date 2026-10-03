# Wires the read-roots guard's PUBLICATION mode into THIS repository's checks (den-hoag-g2glu).
#
# The guard binaries are the shipped ones, reached through the published `lib.readRootsGuard`,
# run over a git fixture in the sandbox. Arms, each read by exit status AND text:
#   publication mode (the hub's: `roots = [ ]`, `publicationRoots = [ <source root> ]`)
#     clean                                                -> 0
#     untracked root `.md` / `ci/tests-error.nix` /
#       `.github/workflows/*.yml`                          -> 1, the file named; removed -> 0
#     a `result-*` symlink the fixture's .gitignore names  -> 0
#     a file matched ONLY by the host's global excludes    -> 1 (the verdict is the repository's)
#   worktree mode (a library's: `roots = [ <ci> ]`) — the control that the mode is per root
#     a gitignored file under the root                     -> 1, where publication mode gives 0
#   a string where a path is owed                          -> a CATCHABLE named throw
{ inputs, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      src = inputs.gen-harness.sourceInfo.outPath;
      guard =
        args:
        inputs.gen-harness.lib.readRootsGuard (
          {
            inherit pkgs;
            name = "gen-harness";
            sourceRoot = src;
          }
          // args
        );
      pub = guard {
        roots = [ ];
        publicationRoots = [ src ];
      };
      lib' = guard { roots = [ "${src}/ci" ]; };
      door = builtins.tryEval (guard { roots = [ "ci/tests" ]; }).drvPath;
    in
    {
      checks.read-roots-guard =
        assert door.success == false;
        pkgs.runCommand "gen-harness-read-roots-guard" { nativeBuildInputs = [ pkgs.git ]; } ''
          export HOME=$PWD/home XDG_CONFIG_HOME=$PWD/home/.config
          mkdir -p $HOME/.config/git repo
          printf 'globalonly*\n' > $HOME/.config/git/ignore
          printf '[core]\n\texcludesFile = %s/.config/git/ignore\n' "$HOME" > $HOME/.gitconfig
          cd repo
          git init -q
          git config user.email a@b; git config user.name n
          mkdir -p ci/tests
          echo '{ }' > ci/tests/a.nix
          printf 'result-*\nci/tests/ignored.nix\n' > .gitignore
          git add -A; git commit -qm base

          P=${pub}/bin/gen-harness-ci-read-roots
          L=${lib'}/bin/gen-harness-ci-read-roots
          arm() { # <name> <guard> <want-rc> <want-text-or-empty>
            rc=0
            "$2" > "../$1.out" 2>&1 || rc=$?
            cat "../$1.out"
            [ "$rc" = "$3" ] || { echo "ARM $1: rc $rc, wanted $3"; exit 1; }
            if [ -n "$4" ]; then grep -Fq -- "$4" "../$1.out" || { echo "ARM $1: output lacks $4"; exit 1; }; fi
          }
          plant() { # <class> <path>
            mkdir -p "$(dirname "$2")"; echo x > "$2"
            arm "$1" "$P" 1 "$2"
            rm "$2"
            arm "$1-removed" "$P" 0 ""
          }
          arm clean "$P" 0 ""
          plant root-md FRESH.md
          plant error-plane ci/tests-error.nix
          plant workflow .github/workflows/fresh.yml
          ln -s /nonexistent result-1
          arm result-link "$P" 0 ""
          rm result-1
          # The control that the env is armed: the host-standard predicate DOES hide this file.
          echo x > globalonly.txt
          [ -z "$(git ls-files --others --exclude-standard)" ] || { echo "CONTROL: the global excludes file is not in effect"; exit 1; }
          arm global-only "$P" 1 globalonly.txt
          rm globalonly.txt
          echo '{ }' > ci/tests/ignored.nix
          arm worktree-mode "$L" 1 ci/tests/ignored.nix
          arm publication-mode-same-file "$P" 0 ""
          echo "read-roots-guard: 11 arms + string-root door" > $out
        '';
    };
}
