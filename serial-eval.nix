# `lib.serialEval`: the counted runs' serial options, as a sourced bash library (`serial-eval.bash`).
# `{ pkgs }` -> the library's store path. It carries no evaluator: it asks the `nix` beside the
# runner's own resolved `nix-instantiate`, so `process-plane.nix`'s closure guard passes by construction.
{ pkgs }: pkgs.writeText "serial-eval.bash" (builtins.readFile ./serial-eval.bash)
