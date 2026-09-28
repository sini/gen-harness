# A root in the roster's shim shape: `src` is the one expression that fetches (here, one that no
# sandbox can reach), `dep` reads through it, and the `inputs` bag wins over both.
{
  inputs ? { },
  src ?
    segs: builtins.fetchTree "https://example.invalid/${builtins.concatStringsSep "/" segs}.tar.gz",
  dep ? segs: import (src segs),
  a ? inputs.dep-a or (dep [ "dep-a" ]),
}:
builtins.seq a {
  live = 1;
  gone = throw "root-surface-fixture: `gone` is retired (use `live`).";
}
