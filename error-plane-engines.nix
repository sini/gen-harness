# The error plane's three ENGINES, and the one reader of the evaluator pins they must agree with
# (den-hoag-o7kjc). `error-plane-check.nix` builds one of them; `ci/tests/engine-pins.nix` holds the
# pins equal.
#
# ★ AN ENGINE IS A FLAKE INPUT OF THE HARNESS, one per evaluator family, taken at the release tag the
# column installs and with no `follows`, so its out path is the installed one. The family is read
# from the evaluator evaluating this expression — `builtins.nixVersion` and the builtin set, both
# pure — so a column builds only its own family's engine, and the other two inputs are never fetched.
# `filterAttrs` is the one builtin separating Determinate from upstream at their pinned releases; if
# upstream gains it, the `evaluator identity` step of `evaluators.yml` refuses the misdetection by
# store path.
#
# ★ ONE SOURCE FOR THE COLUMN'S CONFIGURATION. `evaluators.yml`'s `EVAL_CONF` block is what every
# installer is handed and what `evaluator identity` reads back; it is read here from the same file,
# so the engine's `nix.conf` cannot hold a second copy of it to drift.
{
  lib,
  genInputs,
  system,
}:
let
  yml = builtins.readFile ./.github/workflows/evaluators.yml;
  lines = lib.splitString "\n" yml;

  # `  <KEY>: "<value>"` in the workflow's top-level `env:`. Absent is a refusal, never a default.
  pinOf =
    text: k:
    let
      m = lib.findFirst (x: x != null) null (
        map (builtins.match "  ${k}: \"([^\"]+)\".*") (lib.splitString "\n" text)
      );
    in
    if m == null then throw "error plane: no `${k}` pin in evaluators.yml" else builtins.head m;

  # The `EVAL_CONF: |` block scalar: the lines after its key that carry its 4-space indentation.
  evalConf =
    let
      at = lib.lists.findFirstIndex (l: l == "  EVAL_CONF: |") null lines;
      block =
        (lib.foldl'
          (
            acc: l:
            if acc.done then
              acc
            else if lib.hasPrefix "    " l then
              acc // { ls = acc.ls ++ [ l ]; }
            else
              acc // { done = true; }
          )
          {
            done = false;
            ls = [ ];
          }
          (lib.drop (at + 1) lines)
        ).ls;
    in
    if at == null || block == [ ] then
      throw "error plane: no `EVAL_CONF: |` block in evaluators.yml"
    else
      lib.concatMapStrings (l: lib.removePrefix "    " l + "\n") block;

  engines = {
    nix = {
      pin = "NIX_VERSION";
      pkg = genInputs.nix-upstream.packages.${system}.nix-cli;
      conf = "experimental-features = nix-command flakes\n";
    };
    determinate = {
      pin = "DETERMINATE_VERSION";
      pkg = genInputs.nix-determinate.packages.${system}.nix-cli;
      # Stated at the Determinate install step of `evaluators.yml`, not in EVAL_CONF.
      conf = "lazy-trees = true\n";
    };
    lix = {
      pin = "LIX_VERSION";
      pkg = genInputs.nix-lix.packages.${system}.default;
      conf = "experimental-features = nix-command flakes\n";
    };
  };
  family =
    if lib.hasSuffix "-lix" builtins.nixVersion then
      "lix"
    else if builtins ? filterAttrs then
      "determinate"
    else
      "nix";
in
{
  inherit engines evalConf family;
  # The engine of the family evaluating this expression: what `checks.tests-error` runs and what the
  # flake module publishes as `errorPlane.engine`, one binding for both.
  engine = engines.${family};
  # The input names the engines come from: the error plane never re-pins beneath them.
  inputNames = [
    "nix-upstream"
    "nix-determinate"
    "nix-lix"
  ];
  # Each family whose `evaluators.yml` pin is not its engine input's version, as a sentence. `text`
  # is the workflow's text, so a cell can hand a doctored copy.
  disagreements =
    text:
    lib.concatMap (
      f:
      let
        want = pinOf text engines.${f}.pin;
        got = engines.${f}.pkg.version;
      in
      lib.optional (want != got) "${f}: evaluators.yml ${engines.${f}.pin} ${want} vs engine input ${got}"
    ) (lib.attrNames engines);
  inherit yml;
}
