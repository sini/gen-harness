# THE EXAMPLE GRAFT: an integration example's flake, evaluated at its own lock with every node that
# is this repository replaced by the working tree.
#
# WHY. An integration example reaches its parent through another flake (the hub, or a sibling whose
# own inputs pin the parent), so the example's lock carries PUBLISHED copies of the parent. A suite
# that evaluates the example as locked tests those copies and reads no byte of the tree: measured
# on gen-aspects/demo, green with a marker planted in the tree never read. This fold does what
# nix's `call-flake.nix` does with a lock, and substitutes the tree for the parent wherever it sits.
#
# ★ EVERY NODE, AT ANY DEPTH, NOT THE ROOT'S EDGES ONLY. A node is the parent when the self-input
# scanner (`ci-self-input.nix`) names it: `locked.repo`, or a `git` URL's last segment with `.git`
# stripped, equal to `name`. Grafting only the root's edges (the error plane's rebind rule) grafts
# nothing on an example that reaches its parent through the hub, and the cell reads green on the
# published copy. A partial graft leaves a published copy beside the tree in one evaluation, which
# is the defect `ci-self-input.nix` exists for, one plane over. `tests.example-graft`'s parity cell
# holds this predicate equal to the scanner's over the scanner's own seeds.
#
# ★ ONE VALUE, FOLDED FROM THE PARENT'S OWN ROOT LOCK. Every parent node, whatever its label and
# whoever reaches it, becomes the tree's flake folded from the tree's `flake.lock`, so its inputs
# are the tree's pins and never the example lock's. That is nix's own override semantics: with an
# input overridden to a tree, `nix flake lock` takes the tree's lock for that input's dependencies.
# A parent with no root lock folds with no inputs.
#
# ★ A `flake = false` PARENT NODE BECOMES THE TREE'S SOURCE, never its flake value: the consumer
# declared a source. A `path` node is refused by name: a relative path resolves against the
# example's own source, which this fold does not model.
#
# Every other node keeps the example lock's pin, with `follows` resolved from the example lock's
# root. The fold is pure: every such node is rev- and narHash-locked. Nothing is written.
{
  # The repository root, `inputs.self.sourceInfo.outPath`: the tree the parent nodes become.
  root,
  # The repository's name, the one the self-input scanner matches.
  name,
  # The example's directory under `examples/`.
  dir,
}:
let
  exampleDir = root + "/examples/${dir}";
  readLock = d: builtins.fromJSON (builtins.readFile (d + "/flake.lock"));
  exampleLock = readLock exampleDir;
  parentLock =
    if builtins.pathExists (root + "/flake.lock") then
      readLock root
    else
      {
        root = "root";
        nodes.root = { };
      };

  # A lock input is a node key, or a `follows` path from the lock's own root.
  resolveIn =
    lock: spec:
    if builtins.isList spec then
      builtins.foldl' (k: seg: resolveIn lock lock.nodes.${k}.inputs.${seg}) lock.root spec
    else
      spec;

  last = xs: builtins.elemAt xs (builtins.length xs - 1);
  removeSuffix =
    sfx: str:
    let
      n = builtins.stringLength sfx;
      m = builtins.stringLength str;
    in
    if m >= n && builtins.substring (m - n) n str == sfx then builtins.substring 0 (m - n) str else str;

  # The scanner's predicate. A `path` node names no repository.
  isParentNode =
    node:
    let
      l = node.locked or { };
      repo =
        if l ? repo then
          l.repo
        else if (l.type or "") == "git" && l ? url then
          last (builtins.split "/" (removeSuffix ".git" l.url))
        else
          null;
    in
    repo == name;

  fold =
    lock: rootSrc: override:
    let
      allNodes = builtins.mapAttrs (
        key: node:
        let
          o =
            if (node.locked.type or "") == "path" && key != lock.root then
              throw "example graft: examples/${dir}/flake.lock node `${key}` is a `path` node, which this fold does not resolve"
            else
              override key node;
          sourceInfo =
            if key == lock.root then
              { outPath = rootSrc; }
            else if o ? src then
              { outPath = o.src; }
            else
              builtins.fetchTree (node.info or { } // removeAttrs node.locked [ "dir" ]);
          subdir = if key == lock.root || o ? src then "" else node.locked.dir or "";
          outPath = if subdir == "" then sourceInfo.outPath else sourceInfo.outPath + "/${subdir}";
          flake = import (outPath + "/flake.nix");
          inputs = builtins.mapAttrs (_: spec: allNodes.${resolveIn lock spec}) (node.inputs or { });
          outputs = flake.outputs (inputs // { self = result; });
          result =
            outputs
            // sourceInfo
            // {
              inherit
                outPath
                inputs
                outputs
                sourceInfo
                ;
              _type = "flake";
            };
        in
        if o ? result then
          o.result
        else if node.flake or true then
          result
        else
          sourceInfo
      ) lock.nodes;
    in
    allNodes;

  parentAtOwnLock = (fold parentLock root (_: _: { })).${parentLock.root};
  grafted = builtins.filter (k: isParentNode exampleLock.nodes.${k}) (
    builtins.attrNames exampleLock.nodes
  );
  override =
    key: node:
    if !(builtins.elem key grafted) then
      { }
    else if !(node.flake or true) then
      { src = root; }
    else
      { result = parentAtOwnLock; };
  nodes = fold exampleLock exampleDir override;
in
{
  inherit isParentNode grafted nodes;
  # The example's flake: its outputs over the grafted inputs.
  flake = nodes.${exampleLock.root};
}
