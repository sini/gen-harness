{
  outputs = inputs: {
    marker = "the-tree";
    inherit (inputs) dep;
  };
}
