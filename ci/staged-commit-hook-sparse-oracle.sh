# The cells of `checks.staged-commit-hook-sparse` (`staged-commit-hook-sparse.nix`). Env: HOOK, the
# shipped `stagedCommitHook` built with `wholeTree = [ "^w\.nix$" ]`. Prints one PASS/FAIL line per
# cell; the caller holds the count.
set -uo pipefail
work=$(mktemp -d)
export HOME=$work/home PRE_COMMIT_HOME=$work/pc-cache GIT_CONFIG_NOSYSTEM=1 TMPDIR=$work/tmp
mkdir -p "$HOME" "$TMPDIR"
git config --global user.email o@x
git config --global user.name o
git config --global init.defaultBranch main
fail=0
cell() { if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1: got [$2] want [$3]"; fail=1; fi; }

repo=$work/repo
mkdir -p "$repo"
cd "$repo" || exit 1
git init -q
export ORACLE_WORK=$work
printf 'base\n' | tee a.txt b.txt w.nix > /dev/null
git add a.txt b.txt w.nix
git commit -q --no-verify -m base
fresh() { git reset -q --hard; rm -f "$work/listing" "$work/wt-ran"; }
run() { rc=0; "$HOOK" > "$work/hook.out" 2>&1 || rc=$?; echo "$rc"; }

# 1. A staged path no whole-tree hook matches: only that file exists in the export.
fresh; printf 'a1\n' > a.txt; git add a.txt
cell sparse-non-matching-path-exports-only-it "$(run) $(cat "$work/listing" 2>/dev/null)" "0 a.txt "
# 2. A staged path a whole-tree hook matches: the whole tree is exported and that hook runs.
fresh; printf 'w1\n' > w.nix; git add w.nix
cell full-export-when-a-whole-tree-hook-matches "$(run) $(cat "$work/listing" 2>/dev/null)" "0 a.txt b.txt w.nix "
cell whole-tree-hook-runs-on-its-match "$(cat "$work/wt-ran" 2>/dev/null)" "ran"
# 3. A staged deletion alone has nothing to check out, and the hook still succeeds.
fresh; git rm -q b.txt
cell staged-deletion-alone-succeeds "$(run)" "0"
# 4. A files-scoped hook still refuses on the sparse export.
fresh; printf 'BAD\n' > a.txt; git add a.txt
cell sparse-export-keeps-a-hook-refusal "$(run)" "1"

exit "$fail"
