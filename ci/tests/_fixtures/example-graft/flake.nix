# The graft fixture's PARENT: the tree every parent node in `examples/*/flake.lock` becomes. It has
# no root lock, so it folds with no inputs.
{ outputs = _: { marker = "the-tree"; }; }
