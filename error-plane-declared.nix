# THE error-plane DECLARATION predicate, and its only statement (den-hoag-o7kjc): a repository declares
# an error plane iff its evaluated `flake.testsError` holds a non-empty suite. The CELLS are the
# declaration, never a file name — gen-prelude declares cells from its suite files and has no
# `ci/tests-error.nix`, so a file probe read it as a non-declarer and its CI never asserted the engine.
#
# Every reader takes it from here: the flake module (`checks.tests-error` and the published
# `errorPlane.declared`, which `evaluators.yml` and relock-all read) and `ci-plane-coverage.nix`
# (handed `testsError`, so the hub's `lib.checks` route reads the same predicate).
#
# Names only: a suite's cells are never forced, so a throwing cell body is the plane's subject, not
# this predicate's. A declared plane that collects 0 `test`-prefixed cells is the 0/0 false pass,
# refused by `ci-plane-coverage`'s `plane-non-vacuous` and by `error-plane-runner.py`.
testsError: builtins.any (s: s != { }) (builtins.attrValues testsError)
