{
  pkgs,
  system,
  genInputs,
}:
let
  inherit (pkgs) lib;
  ev = import ./error-plane-engines.nix { inherit lib genInputs system; };
in
pkgs.runCommand "gen-evaluators" { } (
  lib.concatMapStringsSep "\n" (
    family:
    let
      engine = ev.engines.${family};
    in
    ''
      mkdir -p "$out/${family}/bin"
      ln -s ${engine.executable} "$out/${family}/bin/nix"
      cp ${engine.configuration} "$out/${family}/nix.conf"
    ''
  ) (lib.attrNames ev.engines)
)
