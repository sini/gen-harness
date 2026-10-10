# A tombstone one namespace down, beside its successor and a leaf a declaration cannot reach under.
{ }:
{
  live = 1;
  show = {
    node = 1;
    cell = throw "root-surface-fixture: `show.cell` is renamed `show.node`.";
  };
}
