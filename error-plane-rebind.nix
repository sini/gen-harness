# THE REBIND — a declarer's `ci/flake.lock` with some of its ROOT edges bound to another lock's pins.
#
# The error plane evaluates a lock FILE in the sandbox (`error-plane-check.nix`), so a caller that
# wants a member judged at another set of pins — the gen hub, at its own — cannot substitute inputs
# in memory the way a `tests` evaluation can. It hands the lock it wants instead: `rebind.lock`, a
# parsed `flake.lock`, and `rebind.names`, the root edges to take from it.
#
# ★ THE GRAFT. Every node of `rebind.lock` joins the declarer's lock under the `rebind:` prefix, so
# no id can collide, and each named root edge of the declarer points at the node the rebind lock's
# own root names for it. A grafted node carries its whole closure with it, so a name reached only
# through a rebound sibling is at the rebind lock's pin too. A `follows` is a path from the root of
# the file it was written in, so every one in the rebind lock is resolved THERE, segment by segment
# from its root, before a node leaves it; copied verbatim it would resolve against the declarer's
# root instead.
#
# ★ ROOT EDGES ONLY. A node the declarer reaches through an edge that is not rebound keeps its own
# closure, rev-pinned fixtures included: a roster library pinned under another name is frozen on
# purpose, and rewriting the edges beneath it would judge the fixture at a closure nobody chose.
#
# A named edge the declarer's root does not have is left absent; a name the rebind lock's root does
# not declare is refused by name, because there is no pin to bind it to.
{
  lib,
  lock,
  rebind,
}:
if rebind == null then
  lock
else
  let
    hub = rebind.lock;
    hubRoot = hub.nodes.${hub.root}.inputs or { };
    prefix = "rebind:";
    resolve =
      v:
      if builtins.isList v then
        lib.foldl' (k: seg: resolve hub.nodes.${k}.inputs.${seg}) hub.root v
      else
        v;
    lacking = lib.filter (n: !(hubRoot ? ${n})) rebind.names;
    grafted = lib.mapAttrs' (
      n: node:
      lib.nameValuePair (prefix + n) (
        node
        // lib.optionalAttrs (node ? inputs) {
          inputs = lib.mapAttrs (_: v: prefix + resolve v) node.inputs;
        }
      )
    ) hub.nodes;
    ownRoot = lock.nodes.${lock.root};
  in
  if lacking != [ ] then
    throw "error plane: rebind names ${
      lib.concatMapStringsSep ", " (n: "`${n}`") lacking
    }, which the rebind lock's root does not declare"
  else
    lock
    // {
      nodes =
        lock.nodes
        // grafted
        // {
          ${lock.root} = ownRoot // {
            inputs = lib.mapAttrs (
              n: v: if builtins.elem n rebind.names then prefix + resolve hubRoot.${n} else v
            ) (ownRoot.inputs or { });
          };
        };
    }
