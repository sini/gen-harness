# `checks.tests-error` — the error plane judged BY MESSAGE inside `nix flake check`, by the COLUMN'S
# OWN evaluator, so one output carries both planes (den-hoag-o7kjc, arm C; spec
# den-ag-design `reports/den-hoag-o7kjc-errorcells-spec-v1.md`).
#
# WHY A NESTED EVALUATOR, AND WHY IT IS BOUND FROM THE ENVIRONMENT. Pure evaluation cannot see an
# error's message on any of the three evaluators (`tryEval` yields `{ success; value; }`), so a cell
# asserting a message needs an evaluator running inside the build. The ci-locked `pkgs.nix` would be
# the SAME evaluator under all three columns — a Lix or Determinate green over it says nothing about
# Lix or Determinate (den-hoag-lbtnv, as applied in jutgv (c2)). So the column hands in its own
# binary: `GEN_EVALUATOR` is the store path of the `nix` running the check, read under `--impure`
# and bound into the sandbox by `builtins.storePath`. Only a DECLARER gets these checks
# (`flakeModule.nix`), so only a declarer's gate is impure; a pure `nix flake check` of it refuses
# LOUDLY below, never silently.
#
# ★ `--no-build` IS VACUOUS HERE: it evaluates the derivations and runs no cell, so a wrong message
# reads green at rc 0. Nothing in this file can see that flag (spec §5, §3b).
#
# ★ THE BINDING IS CHECKED, NOT TRUSTED (`tests-error-binding`). A version string cannot tell the
# columns apart — Determinate 3.22.5 reports `2.35.2`, CI's upstream pin — so the fingerprint is the
# version, the language version AND the builtin set, one expression (`fp`) evaluated by the outer
# evaluator here and by the bound binary in the sandbox. The builtin set depends on configuration
# (`fetchTree` exists only under `flakes`/`fetch-tree`), so the inner evaluator must run the OUTER'S
# config: `GEN_EVAL_CONF` is the column's own `nix config show`, read in the same step, and
# `evalKeys` below is the part of it that decides what an evaluation prints or resolves. Handed a
# config that is not the running one, the guard REFUSES a correct binding: loud, never silent.
# Residue, stated: two binaries with equal version and builtin set are indistinguishable, and a
# setting outside the builtin set (`lazy-trees`) is carried but not fingerprinted.
#
# ★ THE CONSUMER IS RE-EVALUATED OFFLINE. Every `ci/flake.lock` node is fetched by the OUTER
# evaluator (a store hit: the lock carries each `narHash`) and re-pinned as a `path` node, so the
# inner evaluator needs no network. Two construction facts (spec §2): the lock goes in as a
# derivation ATTRIBUTE, never `builtins.toFile` — under Determinate's lazy-trees a fetched tree is
# not in the store until a derivation needs it — and a re-pinned node carries no `lastModified`,
# which Lix checks against the store path's mtime and refuses. The re-pin drops `rev`,
# `lastModified` and `shortRev` from every node, `self` included: a cell reading them is not
# supported by this engine.
#
# The cells are collected and judged by `error-plane-runner.py`, the same program `ci --tests-error`
# runs: one collection rule, one pass predicate, one 0/0 refusal.
{
  pkgs,
  lib,
  name,
  # `inputs.self.sourceInfo.outPath` — the repository root, never `<root>/ci` (`readroots.nix`).
  root,
}:
let
  env =
    var:
    let
      v = builtins.getEnv var;
    in
    if v != "" then
      v
    else
      throw "gen-harness checks.tests-error: ${var} is unset. This repository declares an error plane, so its checks judge it with the column's own evaluator and run only as `nix flake check --impure` with GEN_EVALUATOR and GEN_EVAL_CONF exported (gen-harness evaluators.yml, the `flake checks` step). A pure run cannot read them.";

  evaluator = builtins.storePath (env "GEN_EVALUATOR");

  # The settings that change what an evaluation PRINTS or RESOLVES, kept from the column's full
  # `nix config show`; store, sandbox and substituter settings stay the sandbox's own.
  evalKeys = [
    "experimental-features"
    "lazy-trees"
    "eval-cores"
    "show-trace"
    "nix-path"
    "abort-on-warn"
    "allow-import-from-derivation"
    "allow-unsafe-native-code-during-evaluation"
  ];
  confLines = builtins.filter (l: builtins.elem (lib.head (lib.splitString " = " l)) evalKeys) (
    lib.splitString "\n" (env "GEN_EVAL_CONF")
  );
  evalConf =
    if lib.any (lib.hasPrefix "experimental-features = ") confLines then
      lib.concatMapStrings (l: l + "\n") confLines
    else
      throw "gen-harness checks.tests-error: GEN_EVAL_CONF carries no `experimental-features` line, so it is not the column's `nix config show` output and the inner evaluator's config cannot be derived from it.";

  fp = builtins.toFile "gen-harness-evaluator-fingerprint.nix" ''
    builtins.hashString "sha256" (builtins.toJSON {
      v = builtins.nixVersion;
      l = builtins.langVersion;
      b = builtins.attrNames builtins;
    })
  '';
  id = "${builtins.nixVersion} / ${toString (builtins.length (builtins.attrNames builtins))} builtins";

  innerEnv = ''
    export HOME=$TMPDIR NIX_STATE_DIR=$TMPDIR/state NIX_STORE_DIR=$TMPDIR/store NIX_LOG_DIR=$TMPDIR/log
    export NIX_CONF_DIR=$TMPDIR/conf XDG_CONFIG_HOME=$TMPDIR/xdg XDG_CACHE_HOME=$TMPDIR/cache
    mkdir -p "$NIX_CONF_DIR"
    printf '%s' ${lib.escapeShellArg evalConf} > "$NIX_CONF_DIR/nix.conf"
    E=${evaluator}/bin
  '';

  binding = pkgs.runCommand "${name}-tests-error-binding" { } ''
    ${innerEnv}
    inner=$("$E/nix-instantiate" --eval --strict ${fp} | tr -d '"')
    innerId=$("$E/nix-instantiate" --eval --strict --expr 'builtins.nixVersion + " / " + toString (builtins.length (builtins.attrNames builtins)) + " builtins"' | tr -d '"')
    if [ "$inner" != ${import fp} ]; then
      echo "BINDING MISMATCH: the running evaluator is ${id}; GEN_EVALUATOR ${evaluator} under GEN_EVAL_CONF is $innerId"
      exit 1
    fi
    echo "${evaluator} ($innerId)" | tee $out
  '';

  lock = builtins.fromJSON (builtins.readFile "${root}/ci/flake.lock");
  repin =
    n: node:
    if n == lock.root then
      node
    else
      node
      // {
        locked = {
          type = "path";
          path = (builtins.fetchTree node.locked).outPath;
          inherit (node.locked) narHash;
        }
        // lib.optionalAttrs (node.locked ? dir) { inherit (node.locked) dir; };
      };
in
{
  tests-error-binding = binding;

  tests-error =
    pkgs.runCommand "${name}-tests-error"
      {
        inherit binding;
        lockJson = builtins.toJSON (lock // { nodes = builtins.mapAttrs repin lock.nodes; });
        passAsFile = [ "lockJson" ];
      }
      ''
        ${innerEnv}
        echo "bound: $(cat "$binding")"
        cp -r ${root} "$TMPDIR/src"
        chmod -R u+w "$TMPDIR/src"
        cp "$lockJsonPath" "$TMPDIR/src/ci/flake.lock"
        PATH="$E:$PATH" ${pkgs.python3}/bin/python3 ${./error-plane-runner.py} "$TMPDIR/src" "path:$TMPDIR/src?dir=ci"
        touch $out
      '';
}
