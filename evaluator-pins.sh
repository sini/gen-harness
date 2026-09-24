#!/usr/bin/env bash
# THE EVALUATOR-PIN STALENESS READER — gating, not a warning (owner ruling 2026-09-24, "latest pins",
# den-hoag-lbtnv). Each evaluator `evaluators.yml` pins must equal that evaluator's LATEST release;
# a pin behind it is RED.
#
# It is a WORKFLOW JOB of gen-harness's own CI and not a flake check, because "latest" is a fact
# about the network at the moment of reading and a pure check has no network. It reds GEN-HARNESS,
# where the pins live — never a caller: a caller receives a bump through its relock.
#
# Sources of "latest", one per evaluator:
#   upstream     https://nixos.org/nix/install redirects to releases.nixos.org/nix/nix-<v>/install
#   Determinate  https://github.com/DeterminateSystems/nix-installer/releases/latest redirects to …/tag/v<v>
#   Lix          https://releases.lix.systems/manifest.nix names …-lix-<v> per system
#
# EXIT: 0 every pin is latest · 1 a pin differs from latest (named) · 2 COULD NOT MEASURE — a source
# unreachable or unparseable, or a pin unreadable. A failed read is never reported as current.
set -uo pipefail
wf=${1:-.github/workflows/evaluators.yml}

pin() {
  sed -n "s/^  $1: \"\([^\"]*\)\".*/\1/p" "$wf"
}
redirect() {
  curl -sSfI --max-time 30 "$1" | tr -d '\r' | sed -n 's/^[Ll]ocation: //p' | tail -n1
}

latest_nix=$(redirect https://nixos.org/nix/install | sed -n 's|.*/nix-\([0-9][0-9.]*\)/install$|\1|p')
latest_det=$(redirect https://github.com/DeterminateSystems/nix-installer/releases/latest | sed -n 's|.*/tag/v\([0-9][0-9.]*\)$|\1|p')
latest_lix=$(curl -sSf --max-time 30 https://releases.lix.systems/manifest.nix | sed -n 's|.*x86_64-linux = "/nix/store/[a-z0-9]*-lix-\([0-9][0-9.]*\)";.*|\1|p')

st=0
for row in "NIX_VERSION upstream $latest_nix" "DETERMINATE_VERSION Determinate $latest_det" "LIX_VERSION Lix $latest_lix"; do
  read -r key label latest <<<"$row"
  have=$(pin "$key")
  if [ -z "$have" ] || [ -z "$latest" ]; then
    echo "CONTROL FAILED: $label: pin '${have}' from $wf, latest '${latest}' — could not measure" >&2
    st=2
  elif [ "$have" != "$latest" ]; then
    echo "BEHIND: $label is pinned at $have and its latest release is $latest — bump $key in $wf"
    [ "$st" -eq 2 ] || st=1
  else
    echo "current: $label $have"
  fi
done
exit "$st"
