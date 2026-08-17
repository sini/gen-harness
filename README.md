# gen-harness

The CI harness the gen ecosystem's test flakes are built from: `mkCi` and the flake module it
imports. A library's `ci/flake.nix` calls it and gets nix-unit wiring, treefmt with the tree-root
invariant, a devshell, pre-commit hooks and a `flake.tests` option.

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
    root.url = "path:..";
    nixpkgs.url = "https://channels.nixos.org/nixos-unstable/nixexprs.tar.xz";
  };

  outputs =
    inputs@{ gen-harness, root, ... }:
    gen-harness.lib.mkCi {
      inherit inputs;
      name = "gen-schema";
      testModules = ./tests;
      specialArgs = { genSchema = root.lib; };
    };
}
```

`lib.mkCi` is the only output. Its arguments:

| argument       | meaning                                                                       |
| -------------- | ----------------------------------------------------------------------------- |
| `inputs`       | the calling flake's inputs — `nixpkgs` is required, tools are optional        |
| `name`         | the library's name; labels the generated checks, devshell and hook binaries   |
| `testModules`  | a directory of test modules, imported as a tree                               |
| `specialArgs`  | extra module arguments; overrides anything the harness sets, `genPrelude` too |
| `extraModules` | flake-parts modules appended to the harness's own                             |

A test module sets `flake.tests.<suite>.<name> = { expr; expected; };` and receives `name`,
`genInputs`, `genPrelude` and whatever `specialArgs` adds. Suites run under
`nix-unit --flake ./ci#tests`.

### Tools

The harness declares eight inputs — `nixpkgs` and the seven tools `mkCi` and its flake module
resolve: `nix-unit`, `treefmt-nix`, `devshell`, `flake-root`, `git-hooks-nix`, `import-tree`,
`flake-parts`. A consumer that declares one of these by the same name gets its own; otherwise the
harness's declaration is used. Five of the seven are declared by no consumer in the ecosystem
today, so they are not optional extras — a harness missing one does not degrade, it fails to
evaluate.

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
> from `root.inputs.gen-prelude.lib`.

The rule is a class, not a patch list: a suite reaching past `hasInfix` is asking for the prelude
library, and the prelude library is one flake input away at its own root. Widening this repository
to meet such a suite would make the harness a library again, and reintroduce exactly the edge it
exists to cut. A library taking this route needs `gen-prelude` declared at its **root** flake.

## Testing the harness

`ci/` is a separate flake. It hosts the harness's own suites, and it is where the ecosystem's
cross-library integration suites — the ones whose subject is a pairing rather than a single library,
and which therefore have no honest home in either library's own repository — **will** live. None has
moved yet: `ci/tests/` holds three suites today and all three are about the harness.

It reaches `mkCi` through `root.url = "path:.."`: the harness tests itself with itself. The
consequence is stated rather than hidden — a change that stops `mkCi` evaluating takes its own
suite down instead of reporting a red test. Indirect coverage is what catches that case today:
every library in the ecosystem builds its suite from this repository.

Cells whose `expr` **can abort** cannot live in `flake.tests`: the batch asserter behind
`checks.default` forces every `expr` it finds there, so an aborting one crashes the gate rather than
failing a cell. They go on a second output, `ci/tests-error.nix`, reached through `extraModules` and
run by its own hook — whether they assert the abort itself (`expectedError`) or the answer that
holds only while it does not happen.

```
nix-unit --flake ./ci#tests          # the suites
nix-unit --flake ./ci#testsError     # the cells whose expr can abort
nix flake check                      # in ci/ — treefmt, tree-root oracle, hooks
```
