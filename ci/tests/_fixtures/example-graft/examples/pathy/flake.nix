# A `path` node in the lock: refused by name, never resolved.
{
  inputs.near.url = "path:./near";
  outputs = i: { near = i.near; };
}
