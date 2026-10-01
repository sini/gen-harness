# gen-harness

The CI harness the gen ecosystem's test flakes are built from: `mkCi` and the flake module it
imports. A library's `ci/flake.nix` calls it and gets nix-unit wiring, treefmt with the tree-root
invariant, a devshell, pre-commit hooks and the `flake.tests` and `flake.testsError` options.

**It declares no gen library input, and that is the whole point of it being a repository.**

## Why it is separate

Every gen library's `ci/flake.nix` needs the harness. While the harness lived in the `gen` hub,
reaching it meant pinning the aggregator — and the aggregator pins twenty libraries, including the
one whose suite is asking. A library's test harness depended on the aggregator that depended on the
library, and each consumer's ci lock inherited the whole fan: on the order of ninety gen nodes,
across twenty libraries, at twenty excess revisions, to reach a two-file harness.

The harness needed one function from all of that. So it carries the function and drops the
dependency: the cycle is gone by construction rather than managed, and a consumer's ci lock holds
the harness plus the tools, with no library it did not ask for.

## Using it

```nix
{
  inputs = {
    gen-harness.url = "github:sini/gen-harness";
    nixpkgs.url = "https://channels.nixos.org/nixos-unstable/nixexprs.tar.xz";
  };

  outputs =
    inputs@{ gen-harness, ... }:
    gen-harness.lib.mkCi {
      inherit inputs;
      name = "gen-schema";
      testModules = ./tests;
      specialArgs = { genSchema = import ../lib; };
    };
}
```

`lib.mkCi` is the only output. Its arguments:

| argument       | meaning                                                                       |
| -------------- | ----------------------------------------------------------------------------- |
| `inputs`       | the calling flake's inputs — `nixpkgs` is required, tools are optional        |
| `name`         | the library's name; labels the generated checks, devshell and hook binaries   |
| `testModules`  | a directory of test modules, imported as a tree                               |
| `readRoots`    | paths the suite reads BESIDES `testModules`; added to it, never replacing it  |
| `specialArgs`  | extra module arguments; overrides anything the harness sets, `genPrelude` too |
| `extraModules` | flake-parts modules appended to the harness's own                             |

A test module sets `flake.tests.<suite>.<name> = { expr; expected; };` and receives `name`,
`genInputs`, `genPrelude` and whatever `specialArgs` adds. Suites run under
`nix develop ./ci --command ci`, the guarded form of `nix-unit --flake ./ci#tests` (see the declared
read domain below). A consumer that owes no `AGENTS.md` capability sheet declares it
through `extraModules` as `{ gen.ci.agentsMd.sheet = "not-owed"; }`; the `agents-md-citations`
check then holds the tree to that declaration and refuses a sheet present beside it, while a
consumer that declares nothing owes a sheet and is refused without one.

`checks.root-surface` holds a repository's root `default.nix` the same way. By default it is owed:
the root is applied at its own declared point (`import <root> { }`, or the root itself when it is a
set) and every published name, a path through plain namespaces with `_type`-tagged values,
derivations and functions as leaves, must evaluate. A repository with no root entry declares
`{ gen.ci.rootSurface.entry = "not-owed"; }`. A top-level tombstone is declared with its exact
message, `gen.ci.rootSurface.retired.<name> = "<message>";`, which also generates the error-plane
cell `testsError.root-surface-retired.test-retired-<name>` pinning that message, with the root's
dependencies taken from `./ci`'s inputs through its `src` seam so the cell never fetches. That cell
declares the repository's error plane, so `checks.tests-error` runs it with no plane file. A
re-exported foreign namespace is not the library's published surface: it is declared with its
origin, `gen.ci.rootSurface.foreign."<name-path>" = "<origin>";`, the walk stops there, and a
declaration the walk never stops at is refused by name. The green is a statement about the library at its own
declared point only (`root-surface.nix` states the scope), and the walk has no depth bound: a
cyclic namespace reds with `max-call-depth exceeded`.

`examples/` is held the same way. Each directory under it is declared with the value the suite
should force, `gen.ci.examples.<dir> = <value>;`, usually the example's `outputs` applied to the
suite's own library values, so the example runs on the working tree and never on its own lock:

```nix
gen.ci.examples.demo = (import ../../examples/demo/flake.nix).outputs {
  gen-algebra.lib = genAlgebra;
  nixpkgs.lib = lib;
};
```

The generated suite `tests.gen-ci-examples` holds three things: the declared names equal the
directories on disk (so an undeclared example reds), each value forces under `deepSeq`, and every
nix-unit leaf inside it holds (`expected` equal, `expectedError` throwing; the error's message is
not checked). An example that cannot be evaluated from the member's own suite without reaching a
published copy of the member is excluded by name instead, citing the row that tracks it:

```nix
gen.ci.examplesExcluded.demo = {
  row = "den-hoag-tyu25";
  reason = "its flake takes the hub, which pins this repository";
};
```

The totality cell counts it, the force and leaves cells skip it, and it gets one cell of its own,
`test-demo-excluded-citing-den-hoag-tyu25`, so every run lists it with its row. That cell reds on a
blank `row` or `reason`, on a directory that is not on disk, and on a name also declared in
`gen.ci.examples`.

An **integration example** reaches the member through another flake (the gen hub, or a sibling
whose inputs pin the member), so it cannot be given the member's values directly. Its lock is not
committed, and it is declared through the module argument `exampleAtOwnLock`, with the directory and
a function from the example's flake to the value to force:

```nix
{ exampleAtOwnLock, ... }:
{
  gen.ci.examples.demo = exampleAtOwnLock "demo" (flake: { inherit (flake) docs fleet; });
}
```

The root `.gitignore` carries one anchored line per integration example, never a glob, since a
library example beside it keeps its committed lock:

```
/examples/demo/flake.lock
```

To move an example into this class, add the line and delete the lock with `git rm examples/demo/flake.lock`, not `git rm --cached`: a lock left on disk is ignored, and `ci` refuses
git-unknown bytes under `examples/`, ignored ones included. Running the example's own README
commands writes that lock again (`nix eval .#fleet` in `examples/demo` locks it), and `ci` refuses
until it is deleted.

The suite holds the class in one cell, `test-demo-integration-lock-is-not-committed`. It reds on a
committed lock, on a `.gitignore` without the exact line (without it `relock` does not classify the
example, and nothing would force it), and on a declaration naming another directory. The value is
forced by `relock`, not by this suite: the git-filtered source holds no lock to evaluate. Each
`relock` locks the example fresh in a scratch copy and forces the value over the example's flake,
evaluated at that lock with every node that is this repository (any depth, matched as the
`ci-self-input` scanner matches) replaced by the working tree, built from the tree's own root
lock. The cells are the flake output `examplesAtRelock`, and `relock` reads nothing else.

The suite is adopted per consumer. The option defaults to `null`, meaning not yet adopted, and a
consumer at that default gets no suite, so bumping the harness reds nobody. Any declaration arms
it, `gen.ci.examples = { };` or any exclusion included, and from then on every directory under `examples/` must be
declared. Once every consumer has declared, a later harness revision makes `{ }` the default and
removes `null`, so the suite can no longer be switched off; a consumer with an undeclared
`examples/` directory then reds at its harness bump.

### The declared read domain

A suite's evaluator reads a **git-filtered** copy of the repository, so a file git does not know
about — untracked, or gitignored — is absent from the source the cells are collected from and
evaluated against. The suite then reports a number that agrees with itself while being short: add
`ci/tests/new-guard.nix` carrying the cell that proves your new guard fires, forget to `git add`
it, and the run is **byte-identical** to the run without it.

So the three invocation points **the harness itself wires** — the `ci` and `ci-error` pre-commit
hooks and the `ci` devshell command — refuse before `nix-unit` is reached if anything under the
declared roots is git-unknown, or is a tracked symlink or submodule whose target the declaration
does not also cover. It does **not** refuse on tracked-modified, tracked-deleted or staged files:
those are fully visible to the evaluator with their worktree bytes, and refusing them would reject
every commit touching a test cell. A hand-typed `nix-unit --flake ./ci#tests` is not guarded, and
neither is `nix flake check ./ci`: both read the git-filtered copy and report green over the cell
they cannot see. So `nix develop ./ci --command ci` is the command to run the suites by.

The refusal covers every git-unknown byte under a root, whatever its extension or name — a file the
collector would skip, `_`-prefixed or not `.nix`, refuses too, because the root is also a read
domain. The remedy is always the same: `git add` the file, or move it out from under the root.

Those three are the harness's own, and they are not the whole set: a consumer's `extraModules` may
wire further invocation points — a runner of its own over some other output, say — and those run
the guard only if they call it themselves. That is why the count is stated as the harness's rather
than as the repository's: nothing here can enumerate what a consumer adds.

The guard itself is `lib.readRootsGuard { pkgs, name, sourceRoot, roots }`, published for a
non-mkCi consumer to run the SAME check `mkCi` wires — the gen hub, whose gate exposes flake checks
rather than a nix-unit `tests` output and so cannot take the module. `flakeModule.nix` imports the
same file for the three invocation points above, so an `mkCi` consumer's guard and the hub's are
one value, never two statements of one check.

`testModules` is covered unconditionally, so **most suites declare nothing**. A suite that reads
outside its collection root — a corpus of documents, a fixture tree beside `ci/` — lists those
paths in `readRoots`, and they are **added** to the collection root rather than replacing it.
`examples/` is added by the harness whenever the repository carries it, with the same semantics as
every other root: a gitignored file under it, such as a `result` link left by `nix build` inside an
example, is refused too.

### Tools

The harness declares eight inputs — `nixpkgs` and the seven tools `mkCi` and its flake module
resolve: `nix-unit`, `treefmt-nix`, `devshell`, `flake-root`, `git-hooks-nix`, `import-tree`,
`flake-parts`. A consumer that declares one of these by the same name gets its own; otherwise the
harness's declaration is used. Five of the seven are declared by no consumer in the ecosystem
today, so they are not optional extras — a harness missing one does not degrade, it fails to
evaluate.

### `relock`

The devshell's `relock` bumps the repository's locks, root first and then `./ci`: bare `relock`
moves every declared input to its own tip, and `relock <input>` moves one. An input that `follows`
another is refused by name, because it moves only with what it follows. Each `examples/<d>/flake.lock`
is bumped after both, unless git ignores it (an integration example, below) or it resolves to this
repository: that one is skipped and named, and a bump that would make it resolve here is restored
and named.

Last, on every run that is not refused, `relock` runs the **integration step**. Each example whose
`examples/<d>/flake.lock` git ignores is locked fresh in a scratch copy of the tracked tree (with
working-tree contents), and the cells of `ci#examplesAtRelock` are evaluated there, one by one,
from a `path:` source and with no `--impure`. The working tree is never written. Its output is a
contract, and den-ag-design's `relock-all` matches on it:

| outcome                 | output                                                                                                                                                            | exit |
| ----------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---- |
| every cell holds        | `examples/<d>: integration example, locked fresh, N cells hold over the working tree` on stdout                                                                   | 0    |
| a cell does not hold    | `examples/<d>: <cell> does not hold` and its error on stderr, then a line opening `INTEGRATION-RED:` on stderr                                                    | 4    |
| the step cannot measure | `CONTROL FAILED` on stderr: an example that cannot be locked, unreadable cells, an ignored set that differs from the declared one, or a working tree that changed | 2    |

Exit 4 is the step's own code. The locks are written and kept, and the tooling has followed: a 3
(the hook or the formatter failed) exits before the step runs. Outside a git worktree the step
cannot classify anything and prints that it did not run. `relock --help`
has the rest.

`relock --hub`, which converged both locks onto the gen hub's pins, is retired and now refused as an
unknown option. Every lock is meant to point at the latest revision, so there is nothing to converge
onto: use bare `relock` for one repository, and den-ag-design's `relock-all` to move the whole gen
graph to its tips in dependency order.

### The three-evaluator workflow

The gen libraries must work under upstream Nix, Determinate Nix and Lix (owner ruling,
2026-09-24), and the CI that holds them to it lives here, as one reusable workflow:

```yaml
name: CI
on:
  push:
    branches: [main]
  pull_request:
    branches: [main]
  workflow_dispatch:
jobs:
  evaluators:
    uses: sini/gen-harness/.github/workflows/evaluators.yml@<the gen-harness rev in ci/flake.lock>
```

Each of the three columns installs its own evaluator at a pinned version and runs the caller's
`nix flake check` lines, evaluates the ci devShell (Determinate's `flake check` does not force it),
and, for a repository that declares an error plane, `checks.tests-error` inside that flake check:
it builds the column's own evaluator release from the harness's engine input and evaluates every
`testsError` cell with it in the build sandbox, one process per cell, because nix-unit is linked
against one upstream nix-expr whatever evaluator is installed. The column's `evaluator identity`
step refuses a run whose `nix` is not that engine's store path. The check evaluates `ci/flake.lock`
as written, so an in-memory `--override-input` of a ci input is refused by name: write the lock to
test a harness change against a consumer. A caller outside the declarer's flake builds the same
check through `lib.checks.errorPlane`, and its `rebind` judges the plane with named root inputs
grafted onto another lock's pins; the refusal then reads the grafted lock. The `nix` column also
keeps the nix-unit step, which alone checks `expectedError.type`. Where
`ci/tests-process.nix` exists, the process plane runs through `ci --tests-process`: the consumer's
`apps.<system>.tests-process` program, run outside the sandbox so its cells call the column's
`nix-instantiate`, and refused if its closure carries an evaluator (`process-plane.nix`). Formatting
runs once.

A green column does not cover a check that evaluates inside its build sandbox through `pkgs.nix`:
that evaluation is the same in all three columns.

The sha is the harness the caller's `ci/flake.lock` holds, never `@main`: the workflow calls
devshell commands from the locked harness, and a mismatch would put two versions of the harness in
one run. `relock` rewrites the sha on every run it does not refuse, and `checks.ci-plane-coverage`
refuses a skewed one. This repository calls the workflow locally.

`workflow_dispatch` is on the caller so that a negative test needs no pull request: push the planted
failure to a scratch branch, run `gh workflow run ci.yml --ref <branch>`, read that run, and delete
the branch. GitHub accepts the dispatch only if the default branch's `ci.yml` declares the trigger,
so it goes in every caller on `main`. The reusable workflow stays `workflow_call` only.

The pins are each evaluator's latest release. `./evaluator-pins.sh` compares them with the upstream,
Determinate and Lix release feeds, and a pin behind is red in this repository's CI. It is a workflow
job, not a flake check, because reading the latest release needs the network.

## The `genPrelude` surface, and the conformance rule

Every suite receives `genPrelude`, and it carries **one attribute: `hasInfix`** — the
backtracking-free substring test purity scans need, because nixpkgs `lib.hasInfix` builds a
`.*needle.*` regex whose recursion depth grows with the subject and overflows the C stack on
whole-file source reads.

It is a vendored copy of gen-prelude's, not a pin. Pinning a library here would put that library in
every consumer's lock, and every consumer whose own root pins it too would then hold two builds of
one library in a single evaluation. `ci/`'s agreement suite pins the original in the harness's own
test plane and asserts the copy answers as it does, so the duplication is instrumented rather than
trusted; that pin is in the flake no consumer pins, so it reaches nobody's lock.

> **Conformance rule.** Any library whose ci tests consume a `genPrelude` attribute other than
> `hasInfix` — directly or through an alias — must supply `genPrelude` in its own ci `specialArgs`,
> from its self-reference's `inputs.gen-prelude.lib` — `gen-schema.inputs.gen-prelude.lib` for the
> example above.

The rule is a class, not a patch list: a suite reaching past `hasInfix` is asking for the prelude
library, and the prelude library is one flake input away at its own root. Widening this repository
to meet such a suite would make the harness a library again, and reintroduce exactly the edge it
exists to cut. A library taking this route needs `gen-prelude` declared at its **root** flake.

## Testing the harness

`ci/` is a separate flake. It hosts the harness's own suites, and it is where the ecosystem's
cross-library integration suites — the ones whose subject is a pairing rather than a single library,
and which therefore have no honest home in either library's own repository — live. The first has
moved: of the four suites `nix eval ./ci#tests --apply builtins.attrNames` names today, three are
about the harness and `dispatch-select-adapter` is the gen-dispatch × gen-select pairing, which
declares both siblings as this flake's own inputs rather than either library's.

It reaches `mkCi` by applying `../flake.nix`'s own `outputs` to its ci inputs, never through a
`path:..` input, which Lix refuses: the harness tests itself with itself. The
consequence is stated rather than hidden — a change that stops `mkCi` evaluating takes its own
suite down instead of reporting a red test. Indirect coverage is what catches that case today:
every library in the ecosystem builds its suite from this repository.

Cells whose `expr` **can abort** cannot live in `flake.tests`: the batch asserter behind
`checks.default` forces every `expr` it finds there, so an aborting one crashes the gate rather than
failing a cell. They go on a second output, `flake.testsError` — populated here from
`ci/tests-error.nix`, reached through `extraModules` — and run by the `ci-error` hook, which the
harness wires beside `ci` off the same guard. That holds whether they assert the abort itself
(`expectedError`) or the answer that holds only while it does not happen.

```
nix develop ./ci -c ci               # the suites, behind the read-roots guard
nix develop ./ci -c ci --tests-error # the cells whose expr can abort, under the nix on PATH, guarded
nix develop ./ci -c ci --tests-process # per-process cells (apps.<system>.tests-process), under the nix on PATH
nix flake check                      # in ci/ — treefmt, tree-root oracle, hooks; unguarded
nix-unit --flake ./ci#tests          # the suites, unguarded
nix-unit --flake ./ci#testsError     # the abort-capable cells, unguarded
```
