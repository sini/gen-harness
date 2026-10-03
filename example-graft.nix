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
# whoever reaches it, becomes the tree's flake folded from the tree's `flake.lock`, so the tree's
# inputs are the tree's pins and never the example lock's. A parent with no root lock folds with no
# inputs.
#
# ★ ONE NODE PER SHARED REPOSITORY, AT THE NEWER PIN. A repository is SHARED when the example lock
# reaches it by a `follows` from a parent node, or from a node of a repository already shared: the
# hub declaring one node for it, so the published closure holds it once. Every edge into a shared
# repository the parent's lock also pins, from either lock and at any depth, takes ONE node: the
# newer by `locked.lastModified` of the parent's pin and the example's, ties and absent dates to the
# parent. That is the closure that publishes, since the hub trails and relocks each shared repository
# to at least both. The parent's pin alone would hold a trailing parent's hub siblings to a
# dependency older than the hub's; the example's alone would run the tree on a dependency it does
# not declare. Two values of one library in one evaluation is the defect either way, since gen's
# identity is value-borne. A parent lock pinning a shared repository at two revisions is refused by
# name. A repository the example lock does not unify keeps its two nodes, as it will publish.
#
# Nix's override is not the primary here. `nix flake lock --override-input <hub>/<parent> <tree>`
# keeps the hub's follows when the override creates the lock, and drops them for the tree's own
# lock when the lock already exists, which is the two-copy closure (Nix, Determinate and Lix alike).
#
# ★ A `flake = false` NODE IS TAKEN AS ITS SOURCE, never its flake value: the referencing edge
# declared a source. A parent node so declared becomes the tree's source. A `path` node is refused
# by name: a relative path resolves against the example's own source, which this fold does not
# model.
#
# Every other node keeps its lock's pin, with `follows` resolved from that lock's root. The fold is
# pure: every such node is rev- and narHash-locked. Nothing is written.
{
  # The repository root, `inputs.self.sourceInfo.outPath`: the tree the parent nodes become.
  root,
  # The repository's name, the one the self-input scanner matches.
  name,
  # The example's directory under `examples/`.
  dir,
  # The fetcher for every node that is not a lock's root. A test seam: `tests.example-graft` stubs
  # it to evaluate a shared-node fixture offline. The flake module passes nothing.
  fetch ? builtins.fetchTree,
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

  # The scanner's identity. A `path` node names no repository.
  repoOf =
    node:
    let
      l = node.locked or { };
    in
    if l ? repo then
      l.repo
    else if (l.type or "") == "git" && l ? url then
      last (builtins.split "/" (removeSuffix ".git" l.url))
    else
      null;
  isParentNode = node: repoOf node == name;

  # repository -> its non-root node keys in one lock.
  keysByRepo =
    lock:
    builtins.groupBy (k: repoOf lock.nodes.${k}) (
      builtins.filter (k: k != lock.root && repoOf lock.nodes.${k} != null) (
        builtins.attrNames lock.nodes
      )
    );
  parentKeys = keysByRepo parentLock;
  exampleKeys = keysByRepo exampleLock;

  # The repositories the example lock unifies: reached by a `follows` from the parent's nodes, then
  # from the nodes of every repository so reached.
  shared = map (x: x.key) (
    builtins.genericClosure {
      startSet = [ { key = name; } ];
      operator =
        { key }:
        builtins.concatMap (
          k:
          builtins.concatMap (
            spec:
            let
              r = repoOf exampleLock.nodes.${resolveIn exampleLock spec};
            in
            if builtins.isList spec && r != null then [ { key = r; } ] else [ ]
          ) (builtins.attrValues (exampleLock.nodes.${k}.inputs or { }))
        ) (exampleKeys.${key} or [ ]);
    }
  );

  # A shared repository the parent pins -> the one node every edge into it takes, `{ inParent; key; }`.
  pick =
    repo:
    let
      ks = parentKeys.${repo};
      hashes = map (k: parentLock.nodes.${k}.locked.narHash or k) ks;
      own =
        if builtins.length (builtins.attrNames (builtins.groupBy (h: h) hashes)) > 1 then
          throw "example graft: the parent's own flake.lock pins `${repo}` at more than one revision (${toString ks}), so the closure would hold two copies"
        else
          builtins.head ks;
      date = lock: k: lock.nodes.${k}.locked.lastModified or null;
      newest =
        builtins.foldl'
          (
            best: k:
            let
              d = date exampleLock k;
            in
            if best.d != null && d != null && d > best.d then { inherit d k; } else best
          )
          {
            d = date parentLock own;
            k = null;
          }
          (exampleKeys.${repo} or [ ]);
    in
    if newest.k == null then
      {
        inParent = true;
        key = own;
      }
    else
      {
        inParent = false;
        key = newest.k;
      };
  chosen =
    builtins.listToAttrs (
      map (r: {
        name = r;
        value = pick r;
      }) (builtins.filter (r: r != name && parentKeys ? ${r}) shared)
    )
    // {
      ${name} = {
        inParent = true;
        key = parentLock.root;
      };
    };

  # One table per lock, each node lazily `{ flake; src; }`. An edge resolves in its own lock, then
  # through `chosen`; the referencing node's `flake` flag picks the flake value or the source.
  table =
    lock: rootSrc: where:
    let
      self = builtins.mapAttrs (
        key: node:
        let
          sourceInfo =
            if key == lock.root then
              { outPath = rootSrc; }
            else if (node.locked.type or "") == "path" then
              throw "example graft: ${where} node `${key}` is a `path` node, which this fold does not resolve"
            else
              fetch (node.info or { } // removeAttrs node.locked [ "dir" ]);
          subdir = if key == lock.root then "" else node.locked.dir or "";
          outPath = if subdir == "" then sourceInfo.outPath else sourceInfo.outPath + "/${subdir}";
          flake = import (outPath + "/flake.nix");
          inputs = builtins.mapAttrs (_: spec: valueOf lock self (resolveIn lock spec)) (node.inputs or { });
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
        {
          flake = result;
          src = sourceInfo;
        }
      ) lock.nodes;
    in
    self;
  valueOf =
    lock: self: k:
    let
      node = lock.nodes.${k};
      r = repoOf node;
      c = if r != null && chosen ? ${r} then chosen.${r} else null;
      v =
        if c == null then
          self.${k}
        else if c.inParent then
          parentNodes.${c.key}
        else
          exampleNodes.${c.key};
    in
    if node.flake or true then v.flake else v.src;

  parentNodes = table parentLock root "the parent's flake.lock";
  exampleNodes = table exampleLock exampleDir "examples/${dir}/flake.lock";

  grafted = builtins.filter (k: isParentNode exampleLock.nodes.${k}) (
    builtins.attrNames exampleLock.nodes
  );
  nodes = builtins.mapAttrs (k: _: valueOf exampleLock exampleNodes k) exampleLock.nodes;
in
{
  inherit
    isParentNode
    grafted
    nodes
    shared
    ;
  # The example's flake: its outputs over the grafted inputs.
  flake = exampleNodes.${exampleLock.root}.flake;
}
