# Shared CI module for all gen ecosystem libraries.
# Provides treefmt, checks.default, devshell, and a flake.tests option.
#
# Expects `name` in specialArgs (set by mkCi).
# Expects `inputs` to include nix-unit (available via mkFlake specialArgs).
{
  config,
  lib,
  inputs,
  genInputs,
  name,
  # The suite's DECLARED READ DOMAIN, as worktree-relative pathspecs. Derived in `mkCi.nix`
  # from the same paths the harness hands `import-tree` and the cells; see `readroots.nix`.
  readRootsRel,
  ...
}:
let
  resolve = name: if inputs ? ${name} then inputs.${name} else genInputs.${name};
in
let
  tests = config.flake.tests;
  testsError = config.flake.testsError;

  # The base mdformat plugin set, from the one file that states which plugins are members.
  # What each member defends, and why beautysh is not one, are documented there beside the
  # names — so this module holds no second statement of the membership to go stale.
  #
  # ★ NAMED so a consumer can EXTEND it, and deliberately NOT reachable for removal:
  # `programs.mdformat.plugins` REPLACES, so a consumer writing `plugins = p: [ p.mdformat-gfm ]`
  # meaning to add one plugin would silently drop the others and nothing would report it. A
  # consumer cannot express that mistake through `extraPlugins` — absence yields the invariant,
  # not its negation.
  mdformatBase = import ./mdformat-plugins.nix;
  mdformatBasePlugins = mdformatBase.plugins;
  # Bound HERE rather than inside `perSystem`, whose own `config` argument shadows this one.
  mdformatExtra = config.gen.ci.mdformat.extraPlugins;

  # KNOWN LIMIT, and it belongs to this gate rather than to the suites it reads: `expr` is forced
  # for every cell unconditionally, so a cell whose `expr` ABORTS crashes the check instead of
  # failing it. The nix-unit runner holds such cells natively, so the two runners disagree about
  # what a suite may contain — and a guard whose whole purpose is to abort for a named reason
  # cannot be tested for its own firing through this path.
  #
  # The predicate for the separate output is CAN-ABORT, not carries-an-error-expectation. A cell
  # asserting an error is the clearest case but not the only one: a cell asserting an ANSWER that
  # holds only while some condition does belongs there too, because the abort returns the moment
  # the condition stops holding, and it would then take this gate down rather than fail a cell.
  # Until the asserter learns to skip them, those cells go on a separate output, outside the
  # `flake.tests` quantifier below; this repository's own ci does exactly that, with cells of the
  # second kind.
  assertTests = lib.mapAttrsToList (
    suite: subtests:
    lib.mapAttrsToList (
      testName: t:
      if t.expr == t.expected then
        true
      else
        throw "FAIL ${suite}.${testName}: got ${builtins.toJSON t.expr}, expected ${builtins.toJSON t.expected}"
    ) subtests
  ) tests;
in
{
  options.flake.tests = lib.mkOption {
    type = lib.types.lazyAttrsOf (lib.types.lazyAttrsOf lib.types.raw);
    default = { };
    description = "Test suites: { suite-name.test-name = { expr; expected; }; }";
  };

  # The second output, declared HERE rather than in each consumer's `ci/tests-error.nix`, for the
  # reason `readRootsGuard` below is one binary: ten repositories each stating one option is ten
  # statements that drift, and they had — five carried a description narrowed to
  # `expectedError`, which is the predicate the `assertTests` comment above says is the wrong one.
  options.flake.testsError = lib.mkOption {
    type = lib.types.lazyAttrsOf (lib.types.lazyAttrsOf lib.types.raw);
    default = { };
    description = "Test suites whose cells' `expr` CAN ABORT: { suite.test = { expr; expected | expectedError; }; }. Read by `nix-unit --flake ./ci#testsError`; deliberately outside `flake.tests`, which the batch asserter forces every `expr` of and would crash on rather than fail.";
  };

  # The EXTENSION point, and it is an extension rather than an override on purpose. The base set
  # defends representational invariants of markdown, which are uniform across every repository
  # that writes markdown and are therefore not a per-corpus preference. A genuinely per-corpus
  # plugin arrives here, added to the base rather than replacing it.
  options.gen.ci.mdformat.extraPlugins = lib.mkOption {
    type = lib.types.functionTo (lib.types.listOf lib.types.package);
    default = _: [ ];
    description = ''
      Plugins ADDED to mkCi's base mdformat set. The base set is not reachable for removal
      through this option, by construction: `programs.mdformat.plugins` replaces rather than
      extends, so a consumer setting it directly would silently drop every base member and
      nothing would report it. Which plugins are in the base set, and what each one defends,
      is stated in `mdformat-plugins.nix` and nowhere else.
    '';
  };

  config = {
    systems = lib.systems.flakeExposed;

    # testSingletons.<suite>.<test> = { <test> = leaf; } — re-nests each leaf under a group keyed by its
    # OWN (test-prefixed) name, so `--flake .#testSingletons.<suite>.<test>` makes that singleton the
    # group root → nix-unit runs exactly one test. nix-unit treats the target attrpath ENDPOINT as a
    # GROUP and detects a test by the `test` NAME-PREFIX of a group child (verified on 2.35.0: a
    # `{expr;expected;}` child named `only` runs 0/0, `test-only` runs 1/1). Pointing it at a bare
    # `{expr;expected;}` leaf (`#tests.<suite>.<test>`) makes that leaf the group and finds no
    # test-prefixed child, so it silently reports `0/0 successful` — a false pass. The wrap works because
    # `${tn}` reuses the original test-prefixed name as the singleton child. This view is the fix.
    flake.testSingletons = lib.mapAttrs (
      _suite: subtests: lib.mapAttrs (tn: t: { ${tn} = t; }) subtests
    ) config.flake.tests;

    perSystem =
      {
        self',
        config,
        pkgs,
        system,
        ...
      }:
      let
        # nix-unit as a binary: the pre-commit framework execs `entry` directly (shlex split, no
        # shell), so it needs an executable that bundles the `--flake ./ci#tests` ref, not a bare
        # command string. No stack raise — the pure gen module system (gen-merge's evalModuleTree)
        # recurses per nesting level, not per module count, so every gen library's suite evaluates
        # within the default 8 MB stack. (A prior `ulimit -s unlimited` here masked a regex bug,
        # not eval depth: purity scans called nixpkgs lib.hasInfix, whose `.*needle.*` recurses to
        # depth ∝ string length on whole-file source reads. Fixed by genPrelude.hasInfix.)
        ciNixUnit = pkgs.writeShellApplication {
          name = "${name}-ci-nix-unit";
          runtimeInputs = [ (resolve "nix-unit").packages.${system}.default ];
          text = ''
            "${readRootsGuard}/bin/${name}-ci-read-roots" || exit $?
            exec nix-unit --flake ./ci#tests "$@"
          '';
        };

        # The same runner for the second output. It differs from `ciNixUnit` in the flake
        # attribute and nothing else — same guard derivation, not a second copy of the check —
        # because the two planes share one collection root (`ci/tests`), so the SAME untracked
        # file blinds both and a guard on only one of them reports a green it did not compute.
        ciNixUnitError = pkgs.writeShellApplication {
          name = "${name}-ci-nix-unit-error";
          runtimeInputs = [ (resolve "nix-unit").packages.${system}.default ];
          text = ''
            "${readRootsGuard}/bin/${name}-ci-read-roots" || exit $?
            exec nix-unit --flake ./ci#testsError "$@"
          '';
        };

        # ★ THE READ-ROOTS GUARD. A suite's evaluator reads a GIT-FILTERED copy of this
        # repository, so a file git does not know about — untracked, or gitignored — is simply
        # absent from the source the cells are collected from and evaluated against. The suite
        # then reports a number that agrees with itself while being short: an author who writes
        # the cell proving their new guard fires, and forgets to `git add` it, reads a green that
        # was computed over a tree without it. The run must yield NO VERDICT in that state, which
        # is why this refuses rather than warns.
        #
        # It is ONE BINARY rather than a copy per caller because all three wired invocation
        # points below need it, and two statements of one check drift — the guard would then fall
        # behind the thing it guards, which is the same argument `mdformat-plugins-check.nix`
        # takes its `expected` from the installed value for.
        readRootsGuard = pkgs.writeShellApplication {
          name = "${name}-ci-read-roots";
          # DECLARED, not ambient. `writeShellApplication` PREPENDS runtimeInputs to an inherited
          # PATH, so an undeclared `git` resolves to whatever the caller happens to carry and the
          # check stops being hermetic. `coreutils` is `realpath`, the symlink containment test.
          runtimeInputs = [
            pkgs.git
            pkgs.coreutils
          ];
          text = ''
            # The worktree, NAMED rather than assumed: the three call sites the harness wires run
            # from different working directories, and a linked worktree must resolve to ITSELF
            # rather than climb into the main checkout. Same reason treefmt's tree root is a
            # stated command below.
            if ! wt=$(git rev-parse --show-toplevel 2>&1); then
              printf 'CONTROL FAILED: the read-roots guard is not inside a git worktree: %s\n' "$wt"
              exit 2
            fi
            roots=(${lib.escapeShellArgs readRootsRel})

            err=$(mktemp)
            trap 'rm -f "$err"' EXIT

            # ★★★ THE DISCRIMINATOR IS THE OUTPUT BEING EMPTY, AND `rc` IS A SEPARATE, THIRD
            # OUTCOME. Measured: `git ls-files` exits 0 in every worktree state this guard cares
            # about, refuse and pass alike, so `if ! git ls-files …` is a silent no-op that passes
            # everything. A non-zero rc means the instrument did not RUN — a misderived root that
            # leaked a store path reads rc=128 — and that is an abort, not a verdict about the tree.
            #
            # `--others` is the whole predicate over the CONTENT modes: exactly the files the index
            # does not know. `--exclude-standard` is deliberately NOT passed — omitting it is what
            # keeps the GITIGNORED half in domain, and it is the half that cannot be repaired by
            # staging. It cannot name a tracked-modified, tracked-deleted or staged file, and it
            # must not: those are fully visible to the evaluator with their worktree bytes, and
            # refusing them would reject every commit that touches a test cell.
            rc=0
            out=$(git -C "$wt" ls-files --others -- "''${roots[@]}" 2>"$err") || rc=$?
            if [ "$rc" -ne 0 ]; then
              printf 'CONTROL FAILED: the read-roots guard did not run (rc=%s): %s\n' "$rc" "$(cat "$err")"
              exit 2
            fi

            # ---- the REFERENCE-MODE half: one rule over a closed enumeration, not a list of cases.
            #
            # The two consumers of a declared root interpret it by different functions. The GUARD
            # hands it to git as a PATHSPEC, which matches index and worktree entries by NAME and
            # traverses nothing. The EVALUATOR hands it to Nix as a PATH, which resolves against the
            # materialised source: symlinks are followed, and objects with no NAR representation are
            # simply absent. They coincide over the modes whose object IS the bytes at that path.
            #
            # Git's index admits exactly four modes, and they split on that question:
            #   100644 / 100755  CONTENT   — the two extents are the same bytes; `--others` above
            #                                is the whole predicate.
            #   120000 SYMLINK   a reference to ANOTHER PATH. Git will not follow it; Nix will.
            #   160000 GITLINK   a reference to a COMMIT. It has no NAR representation, so the
            #                    source carries NONE of its bytes.
            # ⇒ REFUSE at the two REFERENCE modes unless the reference resolves INSIDE the declared
            # root set. For a gitlink that condition is unsatisfiable — a commit is never a path —
            # so its refusal is unconditional and falls out of the same rule. Because the mode
            # enumeration is CLOSED, the rule is total: a third reference mode cannot arrive
            # without git growing one.
            #
            # It is a REFUSAL in its own right and not a filter over the first command's output, so
            # the bad state cannot form. `--stage` names the ROOT ITSELF when the root is the
            # symlink, which is why the at-root and under-root cases are one loop.
            rc=0
            stage=$(git -C "$wt" ls-files --stage -- "''${roots[@]}" 2>"$err") || rc=$?
            if [ "$rc" -ne 0 ]; then
              printf 'CONTROL FAILED: the reference-mode half did not run (rc=%s): %s\n' "$rc" "$(cat "$err")"
              exit 2
            fi

            gitlinks=()
            escapes=()
            # `--stage` prints `<mode> <sha> <stage>\t<path>`, so a TAB split puts the path in
            # field 2 and a path containing spaces survives intact.
            while IFS=$'\t' read -r meta p; do
              [ -n "$p" ] || continue
              case "$meta" in
              "160000 "*)
                gitlinks+=("$p")
                continue
                ;;
              "120000 "*) ;;
              *) continue ;;
              esac
              # `-m` because a link may dangle. The worktree resolution is the right one to read:
              # the source copy materialises the same link text, so relative resolution is
              # identical, and where the two could differ — a target absent from the source — the
              # divergence is toward REFUSING.
              if ! tgt=$(realpath -m --relative-to="$wt" "$wt/$p" 2>"$err"); then
                printf 'CONTROL FAILED: could not resolve the symlink %s: %s\n' "$p" "$(cat "$err")"
                exit 2
              fi
              inside=no
              for r in "''${roots[@]}"; do
                case "$tgt" in "$r" | "$r"/*)
                  inside=yes
                  break
                  ;;
                esac
              done
              [ "$inside" = yes ] || escapes+=("$p -> $tgt")
            done <<<"$stage"

            st=0
            if [ -n "$out" ]; then
              echo "REFUSE: git-unknown bytes under a declared read root — the evaluator cannot see them, so the suite would report a verdict it did not compute:"
              echo "$out"
              st=1
            fi
            if [ ''${#gitlinks[@]} -gt 0 ]; then
              echo "REFUSE: a tracked SUBMODULE (gitlink) at or under a declared read root — the evaluated source carries none of its bytes:"
              printf '%s\n' "''${gitlinks[@]}"
              st=1
            fi
            if [ ''${#escapes[@]} -gt 0 ]; then
              echo "REFUSE: a tracked SYMLINK at or under a declared read root resolves outside the declared set — git matches the NAME, the evaluator resolves the LINK:"
              printf '%s\n' "''${escapes[@]}"
              st=1
            fi
            exit "$st"
          '';
        };
      in
      {
        # Pre-commit hooks: format check + unit tests
        pre-commit = {
          check.enable = false;
          settings.hooks = {
            treefmt = {
              enable = true;
              package = self'.formatter;
            };
            ci = {
              enable = true;
              name = "ci";
              description = "Run nix-unit tests";
              entry = "${ciNixUnit}/bin/${name}-ci-nix-unit";
              files = "\\.nix$";
              pass_filenames = false;
            };
            ci-error = {
              # ★ THE PREDICATE QUANTIFIES AT THE CELL LEVEL, and `testsError != { }` does not.
              # `flake.testsError` is two levels — `suite.cell` — so a consumer declaring a suite
              # that holds no cells satisfies the shallower test, gets the hook, and reads
              # `🎉 0/0 successful` at rc=0: the standing false pass, which is the same defect one
              # layer out from the one the guard above removes. `lib.all` is wrong at BOTH ends —
              # vacuously true over no suites, and false for an empty suite sitting beside a
              # populated one, which would disable a live plane.
              enable = lib.any (s: s != { }) (lib.attrValues testsError);
              name = "ci-error";
              description = "Run nix-unit error-assertion tests";
              entry = "${ciNixUnitError}/bin/${name}-ci-nix-unit-error";
              files = "\\.nix$";
              pass_filenames = false;
            };
          };
        };

        treefmt = {
          # TREE ROOT — the two settings below are one decision; `checks.treefmt-tree-root`
          # is its oracle. A marker-file walk cannot serve here: a linked worktree's `.git` is
          # a gitdir-POINTER FILE rather than a directory, so a `.git/config` search finds
          # nothing in the worktree and climbs UP, crossing the worktree boundary into the main
          # checkout. treefmt then reads and writes THAT tree — a run invoked in a worktree
          # reformats the main checkout and leaves the worktree's own files untouched while
          # reporting success. The pre-commit hook above shares this wrapper
          # (`package = self'.formatter`), so it formats one tree while the commit carries another.
          #
          # `null` rather than omission: flake-parts' treefmt module supplies
          # `mkDefault "flake.nix"`, which walking up from `ci/` resolves to `ci/` itself — the
          # right worktree, the wrong scope. `null` suppresses the `--tree-root-file` flag.
          projectRootFile = null;
          flakeCheck = false;
          enableDefaultExcludes = true;
          settings.on-unmatched = "info";
          # STATED, not inherited. With no tree root declared treefmt falls back to its own
          # detection, which is `git rev-parse --show-toplevel` today — correct, but a default
          # this invariant does not control, and one whose non-git branch resolves the CONFIG
          # FILE'S STORE DIRECTORY rather than failing. Naming the command makes the worktree
          # the tree root by construction and turns the non-git case into a loud error.
          #
          # Residual, unaddressed: `TREEFMT_TREE_ROOT` in the environment still overrides both
          # (flags and env outrank the config file), and the generated wrapper unsets neither.
          settings.tree-root-cmd = "git rev-parse --show-toplevel";
          programs = {
            actionlint.enable = true;
            nixfmt.enable = true;
            mdformat = {
              enable = true;
              # ★ THE SET GOES THROUGH `plugins`, AND THERE IS NO `package` LINE TO GUARD.
              # treefmt-nix builds its final package as `cfg.package.withPlugins cfg.plugins`,
              # and mdformat's `withPlugins` wraps a HARDCODED plain base rather than the package
              # it is called on. So `package` and `plugins` do not union: a list written into
              # `package` is discarded outright and the formatter that ships is plain mdformat,
              # store-path-identical to it. Setting both would encode a union that does not
              # exist, which is why the line is deleted rather than supplemented.
              plugins = p: mdformatBasePlugins p ++ mdformatExtra p;
              # Ordered lists renumber rather than repeating `1.`, so a reordered list reads
              # correctly in plain text as well as rendered.
              settings.number = true;
            };
          };
        };

        # The tree-root invariant is a property of the GENERATED artefacts, so it is gated
        # where they are built rather than trusted to the settings above staying put.
        checks.treefmt-tree-root = import ./treefmt-tree-root.nix {
          inherit pkgs name;
          formatter = self'.formatter;
        };

        # The plugin set is a property of the GENERATED formatter, not of the expression above:
        # the defect this guards was a list that was written and then discarded. Gated where the
        # artefact is built, for the same reason the tree root is.
        #
        # `expected` comes from the same value installed above, so the guard cannot fall behind
        # the set it guards — it did exactly that the last time a member was added, and passed
        # while that member went unchecked.
        checks.mdformat-plugins = import ./mdformat-plugins-check.nix {
          inherit pkgs name;
          formatter = self'.formatter;
          expected = mdformatBase.names;
        };

        # The sheet's CITATIONS are a property of the tree they point into, so the guard is given
        # the tree rather than a value read out of it. `sourceInfo.outPath` and NOT `outPath`:
        # under the `?dir=ci` layout every consumer uses, the latter is `<root>/ci`, and the check
        # would then look for the sheet and the whole suite corpus one directory down.
        #
        # There is no opt-out and that is deliberate — a sheet with no region REFUSES. A guard a
        # writer escapes by not opting in is the fail-open shape this construct exists to close,
        # and a green from a guard with no subject is invisible.
        checks.agents-md-citations = import ./agents-md-citations.nix {
          inherit pkgs name;
          root = inputs.self.sourceInfo.outPath;
        };

        # The batch gate, built from the asserter above. Its quantifier is `flake.tests` and
        # nothing else, which is the structural reason a cell whose `expr` can abort has to live on
        # another output — a cell asserting an error is the clearest such cell, and one asserting an
        # answer that only holds while it does not abort is the same problem: there is no cell shape
        # this check can hold and skip.
        checks.default = pkgs.runCommand "${name}-tests" { } ''
          echo "${toString (builtins.length (lib.flatten assertTests))} tests passed"
          touch $out
        '';

        devshells.default = {
          devshell.startup.git-hooks.text = config.pre-commit.installationScript;

          packages = [
            (resolve "nix-unit").packages.${system}.default
          ];

          env = [
            {
              name = "FLAKE_ROOT";
              eval = "$PRJ_ROOT";
            }
          ];

          commands = [
            {
              name = "ci";
              help = "Run all checks, or a specific test [ci] [ci suite] [ci suite.test]";
              command = ''
                # The read-roots guard runs BEFORE nix-unit at all three invocation points the
                # harness itself wires — this one and the two pre-commit hooks — because a hole at
                # any of them is one an author walks through by habit. A consumer's `extraModules`
                # may wire further ones, which run the guard only if they call it themselves.
                # `|| exit` rather than relying on `set -e`: this command is not a
                # `writeShellApplication` and does not inherit its error handling.
                #
                # `cd "$FLAKE_ROOT"` because the guard resolves the tree it checks from the CWD
                # while nix-unit below is pinned to `$FLAKE_ROOT`. Run from another git worktree
                # the two disagreed: the guard scanned THAT tree, found nothing under the roots,
                # and passed at rc=0 while the suite reported a green for this one. `fmt` below
                # already states its directory for the same reason.
                cd "$FLAKE_ROOT" && "${readRootsGuard}/bin/${name}-ci-read-roots" || exit $?

                # A `suite.test` arg must target the `testSingletons` view: nix-unit treats the attrpath
                # endpoint as a GROUP and detects tests by the `test` name-prefix of a group child, so
                # `#tests.<suite>.<test>` (a bare leaf, no test-prefixed child) reports a silent
                # `0/0 successful`. `testSingletons.<suite>.<test>` re-nests the leaf under a child keyed
                # by its own test-prefixed name, so the singleton runs 1/1. Bare suite / no arg → `tests`.
                if [ -n "''${1:-}" ] && [ "''${1#*.}" != "''$1" ]; then
                  target="testSingletons.$1"
                else
                  target="tests''${1:+.$1}"
                fi
                nix-unit \
                  --flake "$FLAKE_ROOT/ci#$target" \
                  --gc-roots-dir "$FLAKE_ROOT/ci/.gcroots" "''${@:2}"
              '';
            }
            {
              name = "fmt";
              help = "Format all files";
              command = ''
                cd "$FLAKE_ROOT/ci" && nix fmt
              '';
            }
            {
              name = "repl";
              help = "Interactive REPL";
              command = ''
                nix repl --impure --file "$FLAKE_ROOT/ci/repl.nix"
              '';
            }
          ];
        };
      };
  };
}
