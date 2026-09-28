# A root that fetches through a formal other than `src`: no seam a retired-name cell can close, so
# `retiredCells` must refuse it by name rather than let the cell fetch inside the sandbox.
{
  inputs ? { },
  a ? inputs.dep-a or (import (builtins.fetchTree "https://example.invalid/dep-a.tar.gz")),
}:
builtins.seq a {
  live = 1;
  gone = throw "root-surface-fixture: `gone` is retired (use `live`).";
}
