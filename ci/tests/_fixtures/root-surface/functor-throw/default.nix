# An attrset carrying `__functor` without `_type` is a namespace: its other names are addressable.
{ }:
{
  callable = {
    __functor = _: x: x;
    broken = throw "root-surface-fixture: functor member";
  };
}
