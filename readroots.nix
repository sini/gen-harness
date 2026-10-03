# The EVAL half of the read-roots guard: turn the declared roots into worktree-relative
# pathspecs the shell half can hand to git, and refuse — loudly — any root that cannot
# become one.
#
# WHY A STRIP AT ALL. The guard runs in the shell, where the roots are `ci/tests`; the
# evaluator holds `/nix/store/<hash>-source/ci/tests`. The prefix is `sourceInfo.outPath`
# and NOT `outPath`: under the `?dir=ci` layout every consumer uses, the latter is
# `<root>/ci` and stripping it yields a pathspec that names nothing.
#
# ★ WHY THE TWO PER-ROOT CHECKS THROW RATHER THAN RETURN. `lib.removePrefix` on a
# non-matching prefix RETURNS ITS INPUT — it does not refuse. A misspelt root, or one that
# is the source root itself, therefore strips to a pathspec matching no file, and
# `git ls-files --others` over a pathspec that names nothing exits 0 with empty output:
# the guard is silently OFF for that root and reads exactly like a clean one. Emptiness
# cannot distinguish "this root is clean" from "this root names nothing", so the
# distinguishing has to happen here, where the root is still a path value.
#
# `admitSourceRoot` is the PUBLICATION-mode door (`read-roots-guard.nix`): the hub holds its
# whole repository to the publication invariant, so there the source root is a legitimate root
# and strips to `.`. Worktree mode keeps the throw — the source root there is a guard that
# always refuses (every gitignored byte in the checkout), which is a misderived root.
#
# ★ A ROOT IS A PATH VALUE (or an absolute string, which is what `sourceInfo.outPath` is). A
# relative string such as `"ci/tests"` reaches `builtins.pathExists` and aborts with a type error
# that `tryEval` cannot catch; the named throw below is the catchable door for that caller's mistake.
{
  lib,
  sourceRoot,
  admitSourceRoot ? false,
}:
let
  root = toString sourceRoot;

  strip =
    r:
    let
      s = toString r;
    in
    if !(builtins.isPath r || (builtins.isString r && lib.hasPrefix "/" r)) then
      throw "readRoots: a root must be a path value or an absolute path string, got ${builtins.typeOf r}: ${s}"
    else if !builtins.pathExists r then
      throw "readRoots: root does not exist in the evaluated source: ${s}"
    else if s == root && admitSourceRoot then
      "."
    else if s == root then
      throw "readRoots: root is the source root; it cannot be made relative: ${s}"
    else
      lib.removePrefix (root + "/") s;
in
roots:
# The collection root is CONCATENATED into this list rather than defaulted, so under normal
# use it cannot be empty — which is exactly what makes this assertion worth keeping. It is
# the control proving the concatenation is still there, and an empty list would widen the
# scan to the whole repository rather than narrow it to nothing.
if roots == [ ] then
  throw "readRoots: the derived root list is empty; the guard would scan the whole repository"
else
  # ★★ EAGER BY CONSTRUCTION, and `map strip roots` alone is NOT. `map` is lazy in its
  # elements, so the two per-root assertions above fire only if a consumer forces THAT
  # ELEMENT — while the empty-list assertion above fires at WHNF, the shallowest depth any
  # consumer that uses the value at all reaches. A consumer that forces only the SPINE
  # (`builtins.length`, `!= [ ]`, `lib.optionalString`, `mkIf`) therefore receives an
  # ORDINARY VALUE from a misspelt root, and the shell half cannot see a typo either — so
  # the root passes both halves and the guard is off for it. Measured, one operand, both
  # spellings: `builtins.length (readRoots [ <typo> ])` reads `1` without this line and
  # THROWS with it, while a good root list reads its relative strings either way.
  #
  # The construction is gen-aspects `lib/types.nix`'s, binding `ks`: `deepSeq` over the
  # validated value with the value passed through. Forcing a handful of declared strings is
  # cheap; a silently disabled guard is not.
  let
    rel = map strip roots;
  in
  builtins.deepSeq rel rel
