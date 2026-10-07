# The REPOSITORY a lock node names, the rule `ci-self-input.nix`'s scanner states: a
# `github`/`gitlab`/`sourcehut` node names it in `locked.repo`; a `git` node, which is what every
# `git+file` override locks to, names it only as the last segment of `locked.url` with `.git`
# stripped; every other type (`path`, `tarball`, `file`) names none and reads `null`.
#
# ONE HOME, TWO RENDERINGS. `lockedRepo` is the rule over a node's `locked` attribute set, for Nix
# readers (the example graft, every member's entry cell, the hub's entry cell); `jq` is the same rule
# as a jq `def`, for the shell readers (the scanner, `relock`). Pure builtins, so a caller with no
# `lib` can take it. Both renderings are held to the scanner's own seeds (`passthru.seeds`): the Nix
# one by `example-graft.test-the-node-predicate-agrees-with-the-scanner-seeds`, the jq one by the
# scanner's build-time arming (`checks.ci-self-input`, `arming ok: self-git-url`).
let
  lastSegment = url: builtins.elemAt (builtins.match "(.*/)?([^/]*)" url) 1;
  stripGit =
    s:
    let
      m = builtins.match "(.*)[.]git" s;
    in
    if m == null then s else builtins.head m;
in
{
  lockedRepo =
    l:
    if l ? repo then
      l.repo
    else if (l.type or "") == "git" && l ? url then
      stripGit (lastSegment l.url)
    else
      null;

  jq = ''
    def lockedRepo:
      if (.repo // null) != null then .repo
      elif (.type // "") == "git" and (.url // null) != null
        then (.url | sub("\\.git$"; "") | split("/") | last)
      else null end;
  '';
}
