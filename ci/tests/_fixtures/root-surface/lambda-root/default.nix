# A LAMBDA root whose every published name evaluates, with each leaf class the walk must STOP at:
# each carries a throwing field that is not a published name, so descending into it reds.
{
  dep ? "s0",
}:
{
  top = dep;
  ns.deeper.leaf = 1;
  ns.deeper.fn = x: x;
  # `_type`-tagged and self-cyclic through `functor.type`, as an option type is.
  typed =
    let
      t = {
        _type = "option-type";
        functor.type = t;
        impl = throw "root-surface-fixture: a typed value was descended into";
      };
    in
    t;
  drv = {
    type = "derivation";
    drvAttrs = throw "root-surface-fixture: a derivation was descended into";
  };
  list = [ (throw "root-surface-fixture: a list was deep-forced") ];
}
