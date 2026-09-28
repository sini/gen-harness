# `checks.tests-error` EXISTS FOR A DECLARER AND IS ABSENT FOR ANYONE ELSE — never a name with no value.
#
# `checks` is `lazyAttrsOf`: a `mkIf false` definition keeps the NAME and throws "accessed but has no
# value defined" when forced, and `nix flake check` forces every name, so every consumer that declares no
# error plane went red on its first relock onto the harness that added the check (gen-demo, relock 37).
# The unit held here is the NAME SET, read off `mkCi` applied to two fixture consumers that differ only
# in one `testsError` cell: attrNames does not force a check, so a valueless name is visible here as a
# name, which is exactly the defect.
{ inputs, lib, ... }:
let
  namesOf =
    dir:
    builtins.attrNames
      (inputs.gen-harness.lib.mkCi {
        inputs = {
          inherit (inputs) nixpkgs gen-harness;
          self = {
            outPath = dir;
            sourceInfo.outPath = dir;
          };
        };
        name = "fixture";
        testModules = dir;
        extraModules = [ { gen.ci.rootSurface.entry = "not-owed"; } ];
      }).checks.x86_64-linux;
in
{
  flake.tests.plane-check-names = {
    test-a-non-declarer-has-no-tests-error-check = {
      expr = builtins.elem "tests-error" (namesOf ./_fixtures/plane/none);
      expected = false;
    };
    # CONTROL, same reader, same run: a declarer's names carry it.
    test-control-a-declarer-has-the-tests-error-check = {
      expr = builtins.elem "tests-error" (namesOf ./_fixtures/plane/declared);
      expected = true;
    };
  };
}
