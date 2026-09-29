# An own name containing a dot beside the nested path that would render the same unquoted: the
# declaration keys `engine.lib` and `"engine.lib"` must name different namespaces.
{ }:
{
  "engine.lib".y = throw "root-surface-fixture: an own name containing a dot";
  engine.lib.z = 1;
}
