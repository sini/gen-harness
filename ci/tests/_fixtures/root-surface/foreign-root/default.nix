# A re-exported foreign namespace at `engine.lib`: self-referential, as nixpkgs `lib.types` is, with
# a throwing member that sorts before the back-edge. Declared foreign, the walk never enters it.
# Undeclared, the walk forces `bad` first and refuses catchably, not with `max-call-depth exceeded`.
{ }:
let
  t = {
    bad = throw "root-surface-fixture: a member of a foreign namespace";
    types = t;
  };
in
{
  own.x = 1;
  engine.lib = t;
}
