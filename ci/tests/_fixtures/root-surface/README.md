# root-surface fixtures

Roots for `checks.root-surface` cells (`ci/tests/root-surface.nix`, `ci/tests-error.nix`). This
directory itself has no `default.nix`: it is the not-owed root. `tomb/` alone carries
`ci/tests-error.nix`, so it is the one root whose tombstone declaration is admitted.
