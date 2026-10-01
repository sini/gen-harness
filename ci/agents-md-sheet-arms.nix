# Wires `agents-md-citations`'s DECLARATION arms into THIS repository's checks (den-hoag-crr2v).
#
# The arms are the builder's own exits, so no `expr`/`expected` pair can hold them: a refusing arm
# fails its derivation, and a derivation cannot build another and read the failure. Each arm here
# runs the SHIPPED builder text — `buildCommand` of the derivation the published
# `lib.checks.agentsMdCitations` returns for that declaration and that fixture root — under the
# shell options stdenv runs it with. The value refused at evaluation is a `testsError` cell
# (`tests-error.nix`), not an arm.
#
# Arms, each read by exit status AND text:
#   `instructions`, a non-empty AGENTS.md -> 0, no region read
#   `instructions`, no AGENTS.md          -> 1, CONTROL FAILED naming the instructions declaration
#   `instructions`, an empty AGENTS.md    -> 1, the same refusal
#   `not-owed`, an AGENTS.md              -> 1, CONTROL FAILED naming the not-owed declaration
#   `not-owed`, no AGENTS.md              -> 0
{ inputs, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      builder =
        sheet: root:
        pkgs.writeText "agents-md-sheet-arm-${sheet}"
          (inputs.gen-harness.lib.checks.agentsMdCitations {
            inherit pkgs root sheet;
            name = "gen-harness";
          }).buildCommand;
      present = pkgs.writeTextDir "AGENTS.md" "# Instructions for agents working in this repository.\n";
      empty = pkgs.runCommand "agents-md-sheet-arm-empty" { } "mkdir $out; touch $out/AGENTS.md";
      absent = pkgs.emptyDirectory;
    in
    {
      checks.agents-md-sheet-arms =
        pkgs.runCommand "gen-harness-agents-md-sheet-arms"
          {
            instrPresent = builder "instructions" present;
            instrAbsent = builder "instructions" absent;
            instrEmpty = builder "instructions" empty;
            notOwedPresent = builder "not-owed" present;
            notOwedAbsent = builder "not-owed" absent;
            inherit present empty absent;
          }
          ''
            arm() { # <name> <builder> <root> <declared> <want-rc> <want-text>
              rc=0
              root="$3" sheetDeclared="$4" out="$PWD/$1.done" \
                ${pkgs.bash}/bin/bash -eu -o pipefail "$2" > "$1.out" 2>&1 || rc=$?
              cat "$1.out"
              [ "$rc" = "$5" ] || { echo "ARM $1: rc $rc, wanted $5"; exit 1; }
              grep -Eq "$6" "$1.out" || { echo "ARM $1: output lacks /$6/"; exit 1; }
            }
            [ -s "$present/AGENTS.md" ] || { echo "CONTROL FAILED: the present fixture has no non-empty AGENTS.md"; exit 1; }
            arm instr-present "$instrPresent" "$present" instructions 0 '^AGENTS.md declared an instructions file and it is present'
            if grep -q 'region declared' instr-present.out; then echo "ARM instr-present: a region was read"; exit 1; fi
            arm instr-absent "$instrAbsent" "$absent" instructions 1 '^CONTROL FAILED: the consumer declares its AGENTS.md an instructions file'
            arm instr-empty "$instrEmpty" "$empty" instructions 1 '^CONTROL FAILED: the consumer declares its AGENTS.md an instructions file'
            arm notowed-present "$notOwedPresent" "$present" not-owed 1 '^CONTROL FAILED: the consumer declares its AGENTS.md sheet not-owed'
            arm notowed-absent "$notOwedAbsent" "$absent" not-owed 0 '^sheet declared not-owed and none is present'
            echo "agents-md-sheet-arms: 5 arms" > $out
          '';
    };
}
