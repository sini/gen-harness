# The fixture PARENT: every parent node becomes this tree, folded from its own `flake.lock`.
{
  outputs = inputs: {
    marker = "the-tree";
    inherit (inputs) dep data own;
  };
}
