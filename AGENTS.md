# gen-harness — agent capability sheet

## Scope

The CI harness every gen ecosystem library's `ci/flake.nix` is built from: `mkCi` wires flake-parts,
nix-unit, treefmt, a devshell and pre-commit hooks into a consumer's test flake, and the flake module
it imports adds the `flake.tests` / `flake.testsError` options plus four `checks` — the batch test
gate and three oracles over generated artefacts.

## Not this repository's job

★ **IT IS TOOLING, NOT A GEN LIBRARY.** It is off the library roster, it exports no ecosystem
semantics, and nothing in it is importable as a library — a consumer reaches `lib.mkCi` from its `ci/`
flake and nothing else. **It declares no gen library input at its root**, by construction rather than
by discipline: a test harness that pinned a library would put that library in every consumer's lock,
and a consumer whose own root also pinned it would then hold two builds of one library in one
evaluation. The one prelude function the harness needs is vendored instead.

| Responsibility                                                                              | Owner                                                                                                                                                                                  |
| ------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| The test CELLS — what a library asserts about itself                                        | each library's own `ci/tests/`. The harness supplies the option they set and the runner that reads it, and knows nothing about their content                                           |
| Running the assertions                                                                      | `nix-unit` (the input). The harness bundles it into two `writeShellApplication` runners and a devshell package; it implements no runner                                                |
| The module system the consumer's ci flake evaluates under                                   | `flake-parts`. `mkCi` is a thin wrapper over `mkFlake`                                                                                                                                 |
| Importing a directory of test modules as a tree                                             | `import-tree` (the input)                                                                                                                                                              |
| Formatting — the engines and their opinions                                                 | `treefmt-nix`, and through it `nixfmt`, `mdformat`, `actionlint`. The harness owns only the tree-root DECISION and the mdformat plugin MEMBERSHIP, and gates both                      |
| Installing and running git hooks                                                            | `git-hooks.nix`. The harness declares three hooks into it                                                                                                                              |
| General pure utilities — `filter`, `foldl'`, `imap0`, `unique`, and the rest of the prelude | `gen-prelude`. Exactly ONE function is vendored here (`hasInfix`), and a suite reaching past it supplies its own `genPrelude` from gen-prelude at its own root                         |
| Pinning and aggregating the libraries                                                       | the `gen` hub. The harness is deliberately not reachable through it, which is why it is a repository                                                                                   |
| Deciding whether a documentation claim is TRUE                                              | nobody here. `checks.agents-md-citations` reads whether the EVIDENCE a claim offers still exists, never the claim                                                                      |
| The published capability REFERENCE for each library                                         | `den-ag-design`, under `gen-specs/<lib>/REFERENCE.md`. This sheet is the in-repo half and is not that document                                                                         |
| Cross-library integration suites' subject libraries                                         | the libraries. `ci/` HOSTS such a suite (the gen-dispatch × gen-select adapter pairing) because a pairing has no honest home in either library's repository — hosting is not ownership |

## Exports

`lib` is the root flake's **only** output — there is no `packages`, no `checks` and no `devShells` at
the root. The gates live in `./ci`.

**The consumer entry point**

| Export     | Signature                                                                                                                                          |
| ---------- | -------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib.mkCi` | `{ inputs, name, testModules, readRoots ? [ ], specialArgs ? { }, extraModules ? [ ] } -> flake-parts outputs` — closed attrset pattern (no `...`) |

**Check builders, for a repository gated by this machinery without being an `mkCi` consumer** — pure
functions of `pkgs`, no flake-parts module, no gen input.

| Export                         | Signature                                                                                                  |
| ------------------------------ | ---------------------------------------------------------------------------------------------------------- |
| `lib.checks.treefmtTreeRoot`   | `{ pkgs, formatter, name } -> derivation`                                                                  |
| `lib.checks.mdformatPlugins`   | `{ pkgs, formatter, name, plain ? pkgs.mdformat, expected ? <the base names> } -> derivation`              |
| `lib.checks.agentsMdCitations` | `{ pkgs, name, root } -> derivation` — `root` is a SOURCE TREE, not a built package                        |
| `lib.mdformatBasePlugins`      | `{ names = [ string ]; plugins = pkgs -> [ package ]; }` — the membership fact and the value built from it |

**What `mkCi` puts in the consumer's flake**

| Surface                                     | Value                                                                                           |
| ------------------------------------------- | ----------------------------------------------------------------------------------------------- |
| `options.flake.tests`                       | `{ <suite>.<test> = { expr; expected; }; }`                                                     |
| `options.flake.testsError`                  | same shape, for cells whose `expr` CAN ABORT: `{ expr; expected \| expectedError; }`            |
| `options.gen.ci.mdformat.extraPlugins`      | `pkgs -> [ package ]` — ADDED to the base set, never replacing it                               |
| `flake.testSingletons`                      | derived from `flake.tests`; re-nests each leaf so a single cell can be targeted                 |
| `checks.<system>`                           | `default` · `treefmt-tree-root` · `mdformat-plugins` · `agents-md-citations`                    |
| `devShells.<system>.default`                | commands `ci`, `fmt`, `repl`; nix-unit on `PATH`; `FLAKE_ROOT` set                              |
| `formatter.<system>`                        | treefmt with nixfmt + mdformat (four plugins) + actionlint                                      |
| pre-commit hooks                            | `treefmt` · `ci` · `ci-error` (the last enabled only when some `testsError` suite holds a cell) |
| module arguments every test module receives | `name`, `genInputs`, `genPrelude`, `readRootsRel`, plus the consumer's `specialArgs`            |

## Entry points by task

| Task                                                      | Reach for                                                                                          |
| --------------------------------------------------------- | -------------------------------------------------------------------------------------------------- |
| Give a library a test flake                               | `gen-harness.lib.mkCi { inherit inputs; name; testModules; specialArgs; }` from its `ci/flake.nix` |
| Declare a test suite                                      | `flake.tests.<suite>.<cell> = { expr; expected; };` in a module under `testModules`                |
| Assert something that ABORTS                              | `flake.testsError`, reached through `extraModules` — never `flake.tests`                           |
| Declare paths the suite reads outside its collection root | `readRoots = [ ./fixtures ];` — added to `testModules`, not replacing it                           |
| Run every suite                                           | `nix-unit --flake ./ci#tests`                                                                      |
| Run the abort-capable cells                               | `nix-unit --flake ./ci#testsError`                                                                 |
| Run ONE cell                                              | the devshell's `ci <suite>.<cell>`, or `--flake ./ci#testSingletons.<suite>.<cell>`                |
| Run the gates                                             | `nix flake check ./ci` — never at the repository root                                              |
| Format                                                    | `nix fmt` from `ci/`; `nix fmt -- --ci` to check without writing                                   |
| Add an mdformat plugin for one repository                 | `gen.ci.mdformat.extraPlugins = p: [ p.whatever ];`                                                |
| Change which plugins the whole ecosystem gets             | the `names` list in `mdformat-plugins.nix`, and nowhere else                                       |
| Gate a repository that has no nix-unit suite              | import the three `lib.checks.*` builders directly                                                  |
| Override a tool for one consumer                          | declare it by the same input name in the consumer's `ci/flake.nix`                                 |
| Use more of the prelude than `hasInfix`                   | not here — declare `gen-prelude` at the library's ROOT and pass `specialArgs.genPrelude`           |

## Measured traps

<!-- gen-citations:begin -->

Every row below was measured at rev `582f05d`, the tree this sheet is added to, with the commands each
row names. Suite baselines in the same run: `nix-unit --flake ./ci#tests` ⇒ `31/31` at rc 0 and
`nix-unit --flake ./ci#testsError` ⇒ `3/3` at rc 0.

| Trap                                                                                                                                                                                                                                                                                                                 | Evidence                                                                                                                                                                                                                                                                                                                             |
| -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **`nix flake check` at the repository ROOT is a green over ZERO gates.** The root flake's only output is `lib`; every check lives in the `ci` flake                                                                                                                                                                  | `nix flake check .` ⇒ `checking flake output 'lib'... all checks passed!` at rc 0, having built nothing. `nix flake check ./ci` in the same run evaluates and builds four checks. The `ci` invocation is the one the workflow runs, under `working-directory: ci`                                                                    |
| **`AGENTS.md` is GLOBALLY GITIGNORED, so a newly written sheet is absent from the flake source until it is force-added** — and `checks.agents-md-citations` then reports `CONTROL FAILED: no non-empty AGENTS.md`, which reads as "the sheet was never written" whether or not it is sitting in the worktree         | `git check-ignore -v AGENTS.md` ⇒ a hit on the user-global ignore file, not on this repository's own. `git add -f AGENTS.md` is required; a plain `git add` refuses silently at the pathspec. This sheet's own landing hit it                                                                                                        |
| **Targeting a single cell by its natural attrpath reports `🎉 0/0 successful` at rc 0 — a FALSE PASS.** nix-unit treats the attrpath ENDPOINT as a GROUP and finds tests by the `test` name-prefix of a group CHILD, so a bare `{ expr; expected; }` leaf has no test-prefixed child                                 | `--flake ./ci#tests.escape-set.test-set-has-twelve-members` ⇒ `🎉 0/0 successful`, rc 0. Same cell via `--flake ./ci#testSingletons.escape-set.test-set-has-twelve-members` ⇒ `✅` then `🎉 1/1 successful`. The re-nesting that fixes it is `flakeModule.nix:106`; the devshell `ci` command rewrites the target for you            |
| **`nix flake check` does NOT run the abort-capable cells.** Its batch gate quantifies over `flake.tests` and nothing else; `testsError` is not a check                                                                                                                                                               | the check run prints `warning: unknown flake output 'testsError'` (and the same for `tests` and `testSingletons`) and passes without evaluating a single cell of it. The workflow therefore carries a SECOND step. `flakeModule.nix:assertTests` is the quantifier                                                                   |
| **A cell whose `expr` can ABORT crashes the batch gate rather than failing it**, which is why the second output exists — and the predicate is CAN-ABORT, not carries-an-error-expectation: a cell asserting an ANSWER that holds only while some condition does belongs there too                                    | this repository's own witnesses are cells of the second kind: `test-close-bracket-answers` and its live control `test-control-a-missing-close-bracket-answers-false`, in `ci/tests-error.nix`, reached through `extraModules` at `ci/flake.nix:49`                                                                                   |
| **`genPrelude` carries EXACTLY ONE attribute and gains no others** — a suite reaching for any other prelude function gets `attribute … missing`, not a fallback                                                                                                                                                      | `builtins.attrNames (import ./prelude.nix)` ⇒ `["hasInfix"]`. The binding is `prelude.nix:hasInfix`. The conformance rule is to supply your own `genPrelude` in `specialArgs`, from gen-prelude at your ROOT flake                                                                                                                   |
| **`]` is deliberately NOT in the regex escape set, and adding it does not fail — it ABORTS, and `builtins.tryEval` does not contain the abort.** The set is the engine's metacharacter set exactly, and membership is unsound in BOTH directions                                                                     | the set is asserted as TEXT against gen-prelude's own at the pinned rev, so neither an upstream addition nor a local drop passes unnamed: `test-set-has-twelve-members`, `test-set-is-the-original-verbatim` in `ci/tests/escape-set.nix`. The abort witnesses live on the second output because they would take the batch gate down |
| **`readRoots` is CONCATENATED with `testModules`, never defaulted to it** — a Nix default is REPLACED, so `readRoots ? [ testModules ]` would let the first consumer that declares a root drop the collection root out of coverage. The derived value is re-pinned AFTER the `specialArgs` merge for the same reason | `mkCi.nix:69-71`: `// specialArgs` then `// { inherit readRootsRel; }`. Merged the other way, a consumer writing `specialArgs.readRootsRel` silently replaced the derived domain and disabled the guard. Binding: `mkCi.nix:readRootsRel`                                                                                            |
| **A misspelt `readRoots` entry throws only because the derived list is forced with `deepSeq`** — `map` is lazy in its elements, so the per-root assertions fire only for an element the consumer forces, and a consumer that touches only the SPINE gets an ordinary value from a typo                               | `readroots.nix:60` is the forcing line; the two throwing branches are `readroots.nix:strip`. Without it, `builtins.length` over a typo'd root reads `1`; with it, it throws. The failure it prevents is silent: `git ls-files` over a pathspec naming nothing exits 0 with empty output, which is indistinguishable from clean       |
| **`programs.mdformat.plugins` REPLACES**, so writing it directly to add one plugin silently drops the other four and nothing reports it. There is no way to express that mistake through the harness's own option                                                                                                    | extend with `gen.ci.mdformat.extraPlugins`; `flakeModule.nix:358` appends it to the base. `nix eval .#lib.mdformatBasePlugins.names` ⇒ `["mdformat-footnote","mdformat-frontmatter","mdformat-gfm","mdformat-simple-breaks"]`, and that list is the ONLY statement of the membership — `mdformat-plugins.nix:names`                  |
| **A plugin list written into treefmt's `package` is DISCARDED OUTRIGHT** — mdformat's `withPlugins` wraps a hardcoded plain base rather than the package it is called on, so `package` and `plugins` do not union. The damage is IDEMPOTENT, so a format-and-compare gate goes green over the wreckage               | which is why the oracle reads the BUILT wrapper instead: `mdformat-plugins-check.nix`, whose `expected` comes from the same value the module installs so it cannot lag the set it guards                                                                                                                                             |
| **`projectRootFile = null` is load-bearing, not an omission.** flake-parts otherwise `mkDefault`s it to a marker walk, and a linked worktree's `.git` is a POINTER FILE — the walk finds nothing, climbs out of the worktree, and formats the MAIN checkout while reporting success                                  | `flakeModule.nix:333` sets it null and `flakeModule.nix:345` states the tree root as a command instead. The invariant is gated over the generated artefacts by `treefmt-tree-root.nix`, not trusted to those two lines staying put                                                                                                   |
| **The read-roots guard runs at exactly THREE invocation points the harness wires** — the `ci` and `ci-error` hooks and the `ci` devshell command. A hand-typed `nix-unit --flake ./ci#tests` is NOT guarded, and neither is an invocation point a consumer adds through `extraModules`                               | one binary shared by all three, `flakeModule.nix:readRootsGuard`. What it refuses is git-UNKNOWN bytes (untracked or gitignored) under a declared root, plus tracked symlinks escaping the declared set and tracked submodules; it deliberately does not refuse tracked-modified, staged or deleted files                            |
| **`checks.agents-md-citations` is handed `inputs.self.sourceInfo.outPath` and NEVER `outPath`** — under the `?dir=ci` layout every consumer uses, the latter is `<root>/ci`, so the sheet and the whole suite corpus would be looked for one directory down and the check would resolve nothing                      | `flakeModule.nix:396`. `readroots.nix` states the same ground for the same reason, one line of its own header                                                                                                                                                                                                                        |
| **The `ci-error` hook's enable predicate quantifies at the CELL level, and `testsError != { }` does not** — the option is two levels deep, so a consumer declaring an EMPTY suite satisfies the shallower test, gets the hook, and reads `🎉 0/0 successful` at rc 0                                                 | `flakeModule.nix:310` — `lib.any (s: s != { })` over the suites. `lib.all` is wrong at both ends: vacuously true over no suites, and false for an empty suite beside a populated one, which would disable a live plane                                                                                                               |
| **The root flake declares NO gen input; `ci/flake.nix` declares THREE** — and that asymmetry is the design, not a leak. The test plane is a flake no consumer pins, so its gen edges fan to nobody                                                                                                                   | `ci/flake.nix:13`, `ci/flake.nix:20-21` pin gen-prelude, gen-dispatch and gen-select. Asserted with a live control on the same predicate: `test-root-lock-carries-no-gen-library` against `test-control-ci-lock-carries-its-cross-lib-inputs`, plus `test-root-declares-exactly-the-tool-set`, all in `ci/tests/no-gen-inputs.nix`   |
| **The harness tests itself WITH itself, so its oracle is not independent**: `ci/flake.nix:7` is `root.url = "path:.."` and the subject of every suite is `root.lib.mkCi`. An `mkCi` that stops evaluating takes its own suite down instead of reporting a red test                                                   | known and accepted, and it is why an input-NAME predicate cannot see this repository's own consumer edge. What catches that case today is indirect: every library in the ecosystem builds its suite from this repository                                                                                                             |
| **The harness declares the devshell's `repl` command for every consumer and supplies the `ci/repl.nix` it invokes to none** — each repository writes its own, and one that has not gets a command that exists and fails. gen-harness was itself that repository until `6ce8e23`                                      | `flakeModule.nix:465-468` declares it unconditionally off `$FLAKE_ROOT`; nothing generates it. Both arms at `1080508`: present ⇒ rc 0, absent ⇒ rc 1. Ruled: ship the file, not a conditional command (by construction; the harness consumes itself, `ci/flake.nix:7`). Counter-case, not taken: a conditional is the smaller diff   |

<!-- gen-citations:end -->

## Theory

**None claimed, and the absence is the honest answer.** `README.md` carries no Theoretical
Foundations table and no citation, unlike every gen library's. This repository implements no academic
result: it is the ecosystem's build and gate plumbing, and its content is measured invariants about
tools — treefmt's tree-root resolution, mdformat's `withPlugins`, git's four index modes, nix-unit's
group/test-prefix detection, `std::regex` recursion depth on `.*needle.*`.

What it does carry, and what a reader should hold it to instead, is a **construction discipline**
stated in the files themselves: every guard's predicate is an ABSENCE, and an absence proves nothing
without a live control, so each one is preceded by a positive control on the same artefact in the same
run. That is the shape shared by all three oracles, and it is the property to preserve when editing
them.

The one theory-adjacent claim is inherited rather than made: the vendored `hasInfix` is a drop-in for
nixpkgs' whose implementation avoids the `.*needle.*` anchors, and the equality is asserted rather than
argued — against gen-prelude's original, at the rev `ci/flake.lock` pins.

## Drift check

```sh
nix eval --json .#lib --apply 'l: builtins.mapAttrs (_: v: if builtins.isFunction v then builtins.attrNames (builtins.functionArgs v) else if builtins.isAttrs v then builtins.attrNames v else builtins.typeOf v) l'
```

Current output (verbatim):

```json
{"checks":["agentsMdCitations","mdformatPlugins","treefmtTreeRoot"],"mdformatBasePlugins":["names","plugins"],"mkCi":["extraModules","inputs","name","readRoots","specialArgs","testModules"]}
```

**Checks.** From the repository root; CI runs the same three with `working-directory: ci`:

```sh
nix flake check ./ci
nix-unit --flake ./ci#tests
nix-unit --flake ./ci#testsError
nix fmt -- --ci
```
