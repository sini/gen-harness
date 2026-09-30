# `checks.tests-error` — the error plane judged BY MESSAGE inside `nix flake check`, PURELY, by the
# evaluator of the column running it (den-hoag-o7kjc; spec den-ag-design
# `reports/den-hoag-o7kjc-errorcells-spec-v3.md`).
#
# ★ THE ENGINE is the column's own release, built from the harness's input for the family that is
# evaluating this flake (`error-plane-engines.nix`). It runs `error-plane-runner.py` in the build
# sandbox over an offline `path:` copy of the declarer's tree, so every cell is evaluated by that
# binary and not by whatever nix-expr the ci lock's nixpkgs links. `passthru.engine` is its store
# path: `evaluators.yml`'s `evaluator identity` step refuses a column whose running `nix` is any
# other store path.
#
# ★ THE RE-PIN. The sandbox has no network, so every node of `ci/flake.lock` the inner evaluation
# reaches is fetched HERE, by the outer evaluator, and rewritten as a `path` node at its narHash.
# The walk starts at the root and never crosses an engine edge: those subtrees stay as locked and
# are never forced, since the engine itself comes from the outer evaluation.
#
# ★ THE LOCK IS THE FILE, SO AN IN-MEMORY OVERRIDE IS REFUSED. The inner evaluation reads
# `ci/flake.lock` as written in the tree; `--override-input` changes the outer evaluation only. An
# overridden ci input would therefore be judged at the pin the FILE names while the invocation
# names another — a verdict about inputs nobody asked for, green or red, and silent. So every
# direct ci input (a root edge of the lock, walked by edge, never by node name) must carry the
# identity its locked node records, `rev` and `narHash` alike, or the check refuses by name. To
# test a change against a consumer's plane, write the lock: `nix flake lock ./ci --override-input …`.
#
# ★ THE REBIND. A caller judging the plane at another lock's pins passes `rebind = { lock; names; }`
# and the lock evaluated is the declarer's with those root edges grafted onto `rebind.lock`
# (`error-plane-rebind.nix`). The refusal is unchanged and reads the grafted lock: the caller's
# `inputs` must carry the rebind lock's identity for every name it rebinds, so the in-memory pins and
# the file the sandbox reads cannot disagree for a rebound name either.
{
  pkgs,
  lib,
  name,
  root,
  # The declarer's in-memory ci inputs, and the harness's own (`resolve` in the flake module).
  inputs,
  genInputs,
  system,
  rebind ? null,
}:
let
  ev = import ./error-plane-engines.nix { inherit lib genInputs system; };
  inherit (ev) family engine;

  lock = import ./error-plane-rebind.nix {
    inherit lib rebind;
    lock = builtins.fromJSON (builtins.readFile "${root}/ci/flake.lock");
  };
  rootEdges = lock.nodes.${lock.root}.inputs or { };

  # A `follows` edge is a list and names no node of its own; an engine edge is consumed from memory.
  directNodes = lib.filterAttrs (
    n: v: builtins.isString v && !(builtins.elem n ev.inputNames)
  ) rootEdges;
  inMemory = n: if inputs ? ${n} then inputs.${n} else genInputs.${n} or null;
  overridden = lib.filter (
    n:
    let
      locked = lock.nodes.${directNodes.${n}}.locked or { };
      i = inMemory n;
    in
    i == null
    || lib.any (k: locked ? ${k} && (i.${k} or null) != locked.${k}) [
      "rev"
      "narHash"
    ]
  ) (lib.attrNames directNodes);

  # The nodes reachable from the root without crossing an engine edge. Only these are re-pinned.
  reach =
    seen: n:
    if seen ? ${n} then
      seen
    else
      lib.foldl' reach (seen // { ${n} = true; }) (
        lib.mapAttrsToList (_: v: v) (
          lib.filterAttrs (k: v: builtins.isString v && !(builtins.elem k ev.inputNames)) (
            lock.nodes.${n}.inputs or { }
          )
        )
      );
  live = reach { } lock.root;
  repin =
    n: node:
    if n == lock.root || !(live ? ${n}) then
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
  tests-error =
    if overridden != [ ] then
      throw "error plane: ${lib.concatMapStringsSep ", " (n: "`${n}`") overridden} ${
        if builtins.length overridden == 1 then "is" else "are"
      } overridden in memory, and the error plane evaluates ${
        if rebind == null then
          "ci/flake.lock as written, so it would judge the cells at the pin the file names. Write the lock instead: `nix flake lock ./ci --override-input <input> <ref>`"
        else
          "ci/flake.lock as written with its rebound root edges grafted onto the caller's rebind lock, so it would judge the cells at the pin that grafted lock names. Write the lock the pin is read from instead: ci/flake.lock, or the rebind lock for a rebound name"
      }"
    else
      pkgs.runCommand "${name}-tests-error"
        {
          lockJson = builtins.toJSON (lock // { nodes = builtins.mapAttrs repin lock.nodes; });
          passAsFile = [ "lockJson" ];
          passthru = {
            inherit family;
            engine = engine.pkg;
          };
        }
        ''
          export HOME=$TMPDIR NIX_STATE_DIR=$TMPDIR/state NIX_STORE_DIR=$TMPDIR/store NIX_LOG_DIR=$TMPDIR/log
          export NIX_CONF_DIR=$TMPDIR/conf XDG_CONFIG_HOME=$TMPDIR/xdg XDG_CACHE_HOME=$TMPDIR/cache
          mkdir -p "$NIX_CONF_DIR"
          printf '%s' ${lib.escapeShellArg (ev.evalConf + engine.conf)} > "$NIX_CONF_DIR/nix.conf"
          echo "outer: ${builtins.nixVersion} (family ${family}); engine: ${engine.pkg} ($(${engine.pkg}/bin/nix --version))"
          cp -r ${root} "$TMPDIR/src"
          chmod -R u+w "$TMPDIR/src"
          cp "$lockJsonPath" "$TMPDIR/src/ci/flake.lock"
          PATH="${engine.pkg}/bin:$PATH" ${pkgs.python3}/bin/python3 ${./error-plane-runner.py} "$TMPDIR/src" "path:$TMPDIR/src?dir=ci"
          touch $out
        '';
}
