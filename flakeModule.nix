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
  # The SAME domain, UNDERIVED: the raw path list `mkCi.nix` also builds `readRootsRel` from
  # (`[ testModules ] ++ readRoots`). Passed through so `readRootsGuard` below can hand it to
  # the PUBLISHED `read-roots-guard.nix`, which derives `readRootsRel` itself — the hub's
  # non-mkCi call reaches the same guard through the same paths-in function (`den-hoag-g2glu`).
  readRootsDeclared,
  ...
}:
let
  resolve = name: if inputs ? ${name} then inputs.${name} else genInputs.${name};
in
let
  tests = config.flake.tests;
  testsError = config.flake.testsError;
  # The error-plane declaration: the cells, from the one predicate every reader takes
  # (`error-plane-declared.nix`). Flake-level, so the conditional import below cannot recurse.
  planeDeclared = import ./error-plane-declared.nix testsError;

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
  # Bound HERE for the same reason as `mdformatExtra` above: `perSystem`'s own `config` shadows.
  sheetDeclared = config.gen.ci.agentsMd.sheet;
  # Bound HERE for the same reason again, and read by the commit hook below.
  commitHookChained = config.gen.ci.commitHook.chained;
  # Bound HERE for the same reason again, and read by both the check and the generated cells.
  rootSurface = import ./root-surface.nix;
  rsEntry = config.gen.ci.rootSurface.entry;
  rsRetired = config.gen.ci.rootSurface.retired;
  rsForeign = config.gen.ci.rootSurface.foreign;
  examplesGuard = import ./examples-guard.nix { inherit lib; };
  examplesSuite = examplesGuard.cells {
    root = inputs.self.sourceInfo.outPath;
    declared = config.gen.ci.examples;
    excluded = config.gen.ci.examplesExcluded;
  };

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
  # ★ THE FAILURE MESSAGE IS ITS OWN FILE AND ITS OWN PUBLISHED NAME, because it runs ONLY on the
  # arm below where a cell has already failed — so a defect in it fires exactly when someone needs
  # the answer and is invisible every other time. `fail-message.nix` states what that cost when it
  # happened, and being callable is what lets a cell hold it at a value that used to abort.
  failMessage = import ./fail-message.nix { inherit lib; };

  assertTests = lib.mapAttrsToList (
    suite: subtests:
    lib.mapAttrsToList (
      testName: t:
      # A cell carrying `expectedError` is on the wrong plane BY ITS OWN SHAPE, so this refusal needs
      # no reasoning about whether the `expr` can abort: it names the cell and its destination before
      # the `expr` is forced, instead of dying on the subject's own text with no coordinate. The
      # reverse is NOT refused: an `expected` cell on `flake.testsError` is legitimate (a control
      # has to run in the same invocation as the thing it controls).
      if t ? expectedError then
        throw "MISPLACED ${suite}.${testName}: a cell asserting an error belongs on flake.testsError (ci/tests-error.nix), not flake.tests -- this gate forces every expr and cannot hold one that aborts"
      else if t.expr == t.expected then
        true
      else
        throw (failMessage suite testName t)
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

  # The consumer's DECLARED SHEET OBLIGATION. The default is the invariant -- a consumer that
  # says nothing owes a sheet and is refused without one -- so absence yields the refusing arm,
  # never its negation. "not-owed" is a positive declaration the check reads and holds the tree
  # to: a sheet present beside it is refused as a contradiction. "instructions" names the root
  # file's ROLE -- agent instructions, not a capability sheet -- and is refused when no such file
  # is present. There is no value that turns the check off over a tree that says nothing.
  options.gen.ci.agentsMd.sheet = lib.mkOption {
    type = lib.types.enum [
      "owed"
      "not-owed"
      "instructions"
    ];
    default = "owed";
    description = ''
      Whether this repository owes an AGENTS.md capability sheet. `owed`: a non-empty sheet
      with a passing citation region is required. `not-owed`: no entry named AGENTS.md may
      exist at the repository root, and that declaration is the check's subject. `instructions`:
      the root AGENTS.md is an agent-instructions file, not a capability sheet; it must exist
      non-empty and no citation region is read from it. Declare it in
      the same commit as the harness bump that brings this option: a declaration ahead of its
      bump is an undefined option and fails every output of this ci at evaluation, `tests` too.
    '';
  };

  options.gen.ci.commitHook.chained = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ ];
    example = [ "STATUS/handoff-gate.sh" ];
    description = ''
      Worktree-relative executables the commit hook runs before it checks the staged tree, in the
      real checkout with git's hook environment intact; a non-zero exit refuses the commit. Each
      must only read the checkout. This is where a command once prepended to
      `.git/hooks/pre-commit` by hand is declared: the hook is written whole at every devshell
      entry (`staged-commit-hook.nix`), so a hand edit does not survive. Declare it in the same
      commit as the harness bump that brings this option.
    '';
  };

  # The consumer's DECLARED ROOT-SURFACE OBLIGATION, the same declared-obligation shape as the
  # sheet above: the default is the invariant, so a consumer that says nothing owes the check.
  options.gen.ci.rootSurface.entry = lib.mkOption {
    type = lib.types.enum [
      "owed"
      "not-owed"
    ];
    default = "owed";
    description = ''
      Whether this repository's root `default.nix` is a published library surface that
      `checks.root-surface` holds. `owed`: the root is applied at its declared point
      (`import <root> { }`, or the root itself when it is a set) and every published name — a path
      through plain namespaces, with `_type`-tagged values, derivations and functions as leaves —
      must evaluate to WHNF, except the declared `retired` tombstones, and the walk does not
      descend into a declared `foreign` root. The green says that of the
      library at its OWN declared point only (for a roster member, its root-lock pins), never at
      any other. `not-owed`: no root `default.nix` may exist, and that declaration is the check's
      subject. Declare it in the same commit as the harness bump that brings this option.
    '';
  };

  options.gen.ci.rootSurface.retired = lib.mkOption {
    type = lib.types.attrsOf lib.types.str;
    default = { };
    description = ''
      Top-level tombstones: `<name> = <the EXACT message its throw carries>`. Each name is excluded
      from the walk, refused if absent or no longer throwing, and pinned to its message by one
      generated `flake.testsError.root-surface-retired.test-retired-<name>` cell forced at the root
      seam, with its dependencies from `./ci`'s inputs. That cell declares the error plane, so
      `checks.tests-error` runs it in every column.
    '';
  };

  options.gen.ci.rootSurface.foreign = lib.mkOption {
    type = lib.types.attrsOf lib.types.nonEmptyStr;
    default = { };
    example = {
      "adapter.engines.engine.lib" = "nixpkgs lib";
    };
    description = ''
      Re-exported foreign namespaces: `<name-path> = <origin>`. A namespace another eval built is
      not this library's published surface, so the walk forces each declared path to WHNF and does
      not descend into it. The key is the path as the walk's error context renders it, without the
      `lib.` prefix, a segment that is not a plain identifier quoted as nixpkgs `showAttrPath`
      quotes it. A declaration the walk never stops at (absent, a leaf, under a tombstone or under
      another declared root) is refused by name, and so is any declaration beside `entry =
      "not-owed"`. The check cannot verify that a declared path is foreign; the origin is stated
      for the reader.
    '';
  };

  # The consumer's DECLARED EXAMPLES. ★ ADOPTION WINDOW: the default `null` is "not yet adopted"
  # and generates no suite, so publishing this option reds no consumer that has not declared it;
  # any declaration, `{ }` included, arms totality. The window closes when the default becomes
  # `{ }`, the same declared-obligation shape as rootSurface above, once every roster member with
  # an `examples/` directory declares (den-hoag-qaa7o, spec §2.7).
  options.gen.ci.examples = lib.mkOption {
    type = lib.types.nullOr (lib.types.attrsOf lib.types.raw);
    default = null;
    description = ''
      One value per directory under `examples/`: `<dir> = <value>`, usually the example's `outputs`
      applied to this suite's own library values, so the example runs on the working tree and never
      on its lock. The generated `flake.tests.gen-ci-examples` suite holds that the declared names
      equal the directories on disk, that each value forces under `deepSeq`, and that every nix-unit
      leaf in it holds (`expected` equal, `expectedError` throwing). A value that emits derivations
      declares its non-derivation outputs instead. An INTEGRATION example, whose flake reaches this
      repository through another flake, is declared `exampleAtOwnLock "<dir>" (flake: <value>)`:
      its `flake.lock` is not committed, the root `.gitignore` carries the exact line
      `/examples/<dir>/flake.lock`, this suite holds both in the cell
      `test-<dir>-integration-lock-is-not-committed`, and `relock` forces the value over a fresh
      lock with every node that is this repository grafted onto the working tree
      (`examplesAtRelock`). The default `null` is a consumer that has not
      adopted the guard yet and gets no suite, so a bare harness bump reds no consumer; any
      declaration, `{ }` included, arms the suite. A later harness revision makes `{ }` the
      default and drops `null`, after which no value switches the suite off.
    '';
  };

  # The examples the guard does NOT evaluate, each by name and citing the row that tracks it
  # (den-hoag-qaa7o: the integration examples whose closure contains the member, until den-hoag-tyu25).
  options.gen.ci.examplesExcluded = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submodule {
        options = {
          row = lib.mkOption {
            type = lib.types.str;
            default = "";
            description = "The tracking row that owes this example's evaluation. Blank is refused.";
          };
          reason = lib.mkOption {
            type = lib.types.str;
            default = "";
            description = "Why the suite cannot evaluate the example. Blank is refused.";
          };
        };
      }
    );
    default = { };
    description = ''
      Directories under `examples/` the guard does not evaluate: `<dir> = { row; reason; }`. Each is
      counted by the totality cell and gets one cell, `test-<dir>-excluded-citing-<row>`, so every
      run lists it with its row. That cell reds on a blank `row` or `reason`, on a `<dir>` that is not
      a directory under `examples/`, and on a `<dir>` also declared in `gen.ci.examples`. Any entry
      arms the suite, as a declaration does.
    '';
  };

  config = {
    systems = lib.systems.flakeExposed;

    # `exampleAtOwnLock "<d>" (flake: <value>)` declares an INTEGRATION example: its lock is not
    # committed, and the relock forces `select` over the example's flake grafted onto this tree
    # (`examples-guard.nix`, `example-graft.nix`). A declaration, not a value, because the
    # git-filtered source this suite reads holds no lock to graft.
    _module.args.exampleAtOwnLock = examplesGuard.exampleAtOwnLock;

    # The repository a lock node names (`lock-node.nix`), the scanner's rule, for every entry cell.
    _module.args.lockedRepo = (import ./lock-node.nix).lockedRepo;

    # The integration examples' cells, read only by `relock`'s integration step over a scratch copy
    # that carries the fresh locks (`path:<copy>?dir=ci#examplesAtRelock`). Always present, `{ }`
    # with nothing declared, so the step's cross-check reads a missing declaration as a named
    # mismatch rather than as an evaluation error.
    flake.examplesAtRelock = examplesGuard.relockCells {
      declared = config.gen.ci.examples;
      flakeOf =
        dir:
        (import ./example-graft.nix {
          root = inputs.self.sourceInfo.outPath;
          inherit name dir;
        }).flake;
    };

    # One error-plane cell per declared tombstone (`root-surface.nix`, `retiredCells`). Only a
    # declarer of tombstones gets the suite, and the suite is itself a declaration of the plane.
    flake.testsError = lib.mkIf (rsRetired != { }) {
      root-surface-retired = rootSurface.retiredCells {
        inherit lib inputs;
        root = inputs.self.sourceInfo.outPath;
        retired = rsRetired;
      };
    };

    # The condition sits on the whole definition, as `flake.testsError` does above: `flake.tests`
    # is `lazyAttrsOf`, so an `mkIf` on the attribute's VALUE keeps the name with `{ }` behind it,
    # a phantom suite every `attrNames` reader counts.
    flake.tests = lib.mkIf (examplesSuite != { }) { gen-ci-examples = examplesSuite; };

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

    # ★ THE ERROR-PLANE DECLARATION, PUBLISHED, so a reader outside this evaluation takes the same
    # predicate `checks.tests-error` exists on rather than probing for a file (den-hoag-o7kjc).
    # `evaluators.yml`'s `evaluator identity` reads `declared` and a declarer's `engine` in ONE
    # evaluation, and gates the nix-unit step on it; relock-all's local gate reads it for that step.
    # `engine.<system>` is the binary `checks.tests-error` runs, for the family evaluating this flake,
    # and it is ABSENT for a non-declarer, whose evaluation never selects an engine.
    flake.errorPlane = {
      declared = planeDeclared;
    }
    // lib.optionalAttrs planeDeclared {
      engine = lib.genAttrs config.systems (
        system: (import ./error-plane-engines.nix { inherit lib genInputs system; }).engine.pkg
      );
    };

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

        # ★ THE READ-ROOTS GUARD, PUBLISHED (`read-roots-guard.nix`, `flake.nix`'s
        # `lib.readRootsGuard`) rather than built inline — the hub is a non-mkCi consumer that
        # must run the SAME check, not a second statement of it. `flake.nix` imports the same
        # file for the published surface; Nix caches `import` by path, so this binding and the
        # published one are the SAME value in any evaluation that reaches both, and the move
        # leaves the derivation byte-identical (gate `den-hoag-g2glu` C1-c).
        readRootsGuard = import ./read-roots-guard.nix {
          inherit pkgs name;
          sourceRoot = inputs.self.sourceInfo.outPath;
          roots = readRootsDeclared;
        };

        # ★ ONE VALUE, TWO CONSUMERS, AND THAT IS WHY IT IS BOUND HERE RATHER THAN INLINE AT
        # `checks.ci-self-input`. The self-input invariant has to be held at BOTH ends: the check
        # catches a violating lock whenever the gate runs, and `relock` catches it at the moment of
        # mutation so the state never lands. Both ends must run the SAME predicate — two statements
        # of one rule drift — so the scanner is built once, inside the check, and reached from its
        # passthru here.
        selfInput = import ./ci-self-input.nix {
          inherit pkgs name;
          root = inputs.self.sourceInfo.outPath;
        };

        # The two-act lock bump, shipped as a devshell command so every `mkCi` consumer inherits one
        # definition of an act that is repeated, mechanical, and silent in each of its failure
        # modes. `relock.nix` names the three.
        relockCmd = import ./relock.nix {
          inherit pkgs name;
          scanner = selfInput.scanner;
        };

        processPlaneCmd = import ./process-plane.nix { inherit pkgs name; };

        # The commit hook and its slot writer, PUBLISHED (`flake.nix`'s `lib.stagedCommitHook`) so
        # the hub installs the same construction. git-hooks.nix keeps generating the config
        # (`settings.install.enable = false` below) and installs nothing.
        stagedHook = import ./staged-commit-hook.nix {
          inherit pkgs;
          inherit (config.pre-commit.settings) package configFile;
          chained = commitHookChained;
        };

        # The error plane as CHECKS, judged by message by the column's own evaluator
        # (`error-plane-check.nix`). A DECLARER only — `planeDeclared`, the flake-level predicate,
        # which the `ci-error` hook below also keys on — because the check builds its evaluator
        # family's engine, and a repository that declares no plane fetches none.
        errorPlane = import ./error-plane-check.nix {
          inherit
            pkgs
            lib
            name
            inputs
            genInputs
            system
            ;
          root = inputs.self.sourceInfo.outPath;
        };
      in
      {
        # `checks.tests-error` for a DECLARER, and NO SUCH NAME for anyone else. `checks` is
        # `lazyAttrsOf`, so `checks.tests-error = mkIf false …` keeps the NAME with no value, and
        # `nix flake check` forcing it refuses every non-declarer ("accessed but has no value
        # defined"). A conditional import adds the definition or nothing; the condition reads the
        # flake-level `testsError`, never this module's own arguments, so it cannot recurse.
        imports = lib.optional planeDeclared { checks.tests-error = errorPlane.tests-error; };

        # Pre-commit hooks: format check + unit tests
        pre-commit = {
          check.enable = false;
          # The config is generated; the hook that runs it is `stagedHook`, never pre-commit's
          # stashing shim. Installing both would make the two installers fight over one slot.
          settings.install.enable = false;
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
              # populated one, which would disable a live plane. `error-plane-declared.nix` is that
              # predicate, stated once.
              enable = planeDeclared;
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
        # There is no opt-out BY SILENCE, and that is deliberate — a sheet with no region REFUSES,
        # and so does a consumer with no sheet that has not said so: it declares
        # `gen.ci.agentsMd.sheet = "not-owed"` in its own flake or is refused, and a sheet present
        # beside that declaration is refused too. A guard a writer escapes by not opting in is the
        # fail-open shape this construct exists to close, and a green from a guard with no subject
        # is invisible — the not-owed green names its subject, the declaration, in the build log.
        checks.agents-md-citations = import ./agents-md-citations.nix {
          inherit pkgs name;
          root = inputs.self.sourceInfo.outPath;
          sheet = sheetDeclared;
        };

        # A repository that DECLARES an error plane (`error-plane-declared.nix`: its cells) must
        # hold a cell, and a `ci/tests-error.nix` that declares nothing is refused. Same root
        # binding as the sheet check above, and the same refusal of
        # a SILENT opt-out:
        # a non-declarer is green by construction, so there is nothing for it to opt out of, and a
        # declarer that could opt out would be the fail-open shape the check exists to close. The
        # evaluated `testsError` is the sibling output, handed in for the one cell whose unit is
        # collected cells rather than text.
        # The published surface at the library's own declared point: `root-surface.nix` states what
        # the green says and what it does not. Same root binding as the two checks above, and the
        # same declared obligation: a repository with no root entry says `not-owed`.
        checks.root-surface = rootSurface.check {
          inherit pkgs name;
          root = inputs.self.sourceInfo.outPath;
          entry = rsEntry;
          retired = rsRetired;
          foreign = rsForeign;
        };

        checks.ci-plane-coverage = import ./ci-plane-coverage.nix {
          inherit pkgs name testsError;
          root = inputs.self.sourceInfo.outPath;
          # The harness THIS ci is built from, so a caller's `evaluators.yml@<sha>` is held to it.
          # `genInputs` is the harness flake's own inputs, whose `self` is the locked gen-harness.
          harnessRev = genInputs.self.sourceInfo.rev or null;
        };

        # A member's `ci/` never tests a PUBLISHED COPY OF ITSELF. Bound in the `let` above because
        # `relock` runs the same predicate on the tree it produces; the file holds the ruling, the
        # reason the match is on `locked.repo`, and the reason it does not assert `flake = false`.
        checks.ci-self-input = selfInput;

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
          # The commit hook's slot writer (`staged-commit-hook.nix`), which also removes the two
          # artefacts the old installer left in every checkout: a relative `core.hooksPath` and the
          # retired post-checkout provisioner.
          #
          # STDERR, never stdout: `nix develop --command X > f` would capture what it prints as X's
          # output. A CI runner is always a first entry, so the process plane's
          # `--userns-binaries > file` step read the old installer's output as a binary and refused
          # it (den-hoag-o7kjc F1).
          devshell.startup.git-hooks.text = ''
            ${stagedHook.install} 1>&2
          '';

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
              help = "Run all checks, or a specific test [ci] [ci suite] [ci suite.test] [ci --tests-error] [ci --tests-process]";
              command = ''
                # The read-roots guard runs BEFORE nix-unit at all three invocation points the
                # harness itself wires — this one and the two pre-commit hooks — because a hole at
                # any of them is one an author walks through by habit. A consumer's `extraModules`
                # may wire further ones, which run the guard only if they call it themselves.
                # `|| exit` states the exit explicitly rather than leaning on the ambient shell
                # options. It is NOT true that these scripts run without them: numtide-devshell
                # emits `set -euo pipefail` into every command it materialises — driven, and `:515`
                # already says so. A builder believing the older wording here wrote `cmd; rc=$?`
                # in a consumer and the script exited before its second arm, printing nothing.
                #
                # `cd "$FLAKE_ROOT"` because the guard resolves the tree it checks from the CWD
                # while nix-unit below is pinned to `$FLAKE_ROOT`. Run from another git worktree
                # the two disagreed: the guard scanned THAT tree, found nothing under the roots,
                # and passed at rc=0 while the suite reported a green for this one. `fmt` below
                # already states its directory for the same reason.
                cd "$FLAKE_ROOT" && "${readRootsGuard}/bin/${name}-ci-read-roots" || exit $?

                # `ci --tests-error`: the error plane judged by the `nix` on PATH, not by the
                # nix-expr nix-unit links — the evaluator-neutral runner a matrix column needs
                # (`error-plane-runner.py` states its predicate). An ARGUMENT of this command rather
                # than a command of its own, and a flag rather than a word so it can never shadow a
                # suite name. It runs AFTER the guard above, as every wired testsError invocation
                # must (den-hoag-a0ig9): an untracked cell file is as invisible to it as to nix-unit.
                if [ "''${1:-}" = "--tests-error" ]; then
                  exec ${pkgs.python3}/bin/python3 ${./error-plane-runner.py} "$FLAKE_ROOT"
                fi

                # `ci --tests-process`: the process plane (`apps.<system>.tests-process`) run under
                # the `nix` on PATH, after the same guard, for the same reason (`process-plane.nix`
                # states the consumer's contract and refuses a program carrying an evaluator).
                # `ci --tests-process --userns-binaries` lists the program's own `unshare` binaries
                # for the CI step that admits them to user namespaces, and runs no cell.
                if [ "''${1:-}" = "--tests-process" ]; then
                  exec "${processPlaneCmd}/bin/${name}-ci-tests-process" "$FLAKE_ROOT" "''${2:-}"
                fi

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
              name = "relock";
              help = "Bump this repository's locks, root then ci [relock [<input>]]";
              # A thin call and not an inline script: the command and `checks.ci-self-input` share
              # one predicate, so it is built as a derivation and reached from both. The binary
              # resolves `$FLAKE_ROOT` itself — it must work from a plain shell too, since the
              # member whose locks most need bumping is the one whose devshell is stale.
              command = ''
                "${relockCmd}/bin/${name}-relock" "$@"
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
