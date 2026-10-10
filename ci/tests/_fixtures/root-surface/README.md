# root-surface fixtures

Roots for `checks.root-surface` cells (`ci/tests/root-surface.nix`, `ci/tests-error.nix`). This
directory itself has no `default.nix`: it is the not-owed root. `tomb/` is the root carrying a
tombstone, `nested-tomb/` the root carrying one at `show.cell`, `foreign-root/` the root re-exporting a foreign namespace at `engine.lib`, and
`dotted-name/` the root whose own name `"engine.lib"` sits beside the nested path `engine.lib`.
