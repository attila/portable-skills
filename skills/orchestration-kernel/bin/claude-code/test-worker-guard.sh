#!/bin/bash
# Fixture suite for worker-guard.sh. Self-contained: builds its scratch root
# and git fixtures under a private TMPDIR, so no live scratchpad is touched.
#
# Every case is a real PreToolUse payload fed to the guard on stdin; the guard
# is pure, so no dispatch and no worker are needed to exercise it.
set -uo pipefail

# Absolute, because one fixture below changes the cwd to exercise glob safety.
guard=$(cd -- "$(dirname -- "$0")" && pwd -P)/worker-guard.sh

# A private temp root stands in for the harness's: the guard derives its
# scratch root as <TMPDIR>/claude-<uid>, so exporting TMPDIR pins it here.
# Git config is silenced so a user-level `tmp/` ignore cannot skew the
# gitignore fixtures either way.
work=$(mktemp -d) || exit 1
trap 'rm -rf "$work"' EXIT
work=$(cd "$work" && pwd -P) # physical path, so fixtures match resolved roots
export TMPDIR=$work
export HOME=$work/home XDG_CONFIG_HOME=$work/xdg
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
mkdir -p "$HOME" "$XDG_CONFIG_HOME"

scratch=$work/claude-$(id -u)
mkdir -p "$scratch/session/scratchpad"

repo=$work/repo # tmp/ gitignored — the decision-160 allowance
git init -q "$repo"
mkdir -p "$repo/tmp"
printf 'tmp/\n' >"$repo/.gitignore"

bare=$work/bare # tmp/ present but NOT gitignored
git init -q "$bare"
mkdir -p "$bare/tmp"

pass=0
fail=0

check() {
  local want=$1 label=$2 json=$3 got
  printf '%s' "$json" | "$guard" >/dev/null 2>&1
  got=$?
  if [ "$got" -eq "$want" ]; then
    pass=$((pass + 1))
    printf '  ok    %-58s (exit %s)\n' "$label" "$got"
  else
    fail=$((fail + 1))
    printf '  FAIL  %-58s (want %s, got %s)\n' "$label" "$want" "$got"
  fi
}

w() { printf '{"tool_name":"Write","tool_input":{"file_path":"%s"}}' "$1"; }
b() { printf '{"tool_name":"Bash","tool_input":{"command":%s}}' "$(printf '%s' "$1" | jq -Rs .)"; }

echo "== allowed: session scratch and gitignored tmp/ =="
check 0 "scratchpad file"                "$(w "$scratch/session/scratchpad/x.md")"
check 0 "deep scratch path, unborn dirs" "$(w "$scratch/sandbox/a/b/c.txt")"
check 0 "gitignored repo tmp/ file"      "$(w "$repo/tmp/probe/fixture.md")"
check 0 "gitignored repo tmp/ dir leaf"  "$(w "$repo/tmp/probe")"
check 0 "read-only tool passes through"  '{"tool_name":"Read","tool_input":{"file_path":"/etc/hosts"}}'

echo "== denied: every other write =="
check 2 "repo source file"               "$(w "$repo/src/module.md")"
check 2 "repo root file"                 "$(w "$repo/README.md")"
check 2 "arbitrary absolute path"        "$(w "/Users/nobody/project/file.md")"
check 2 "tmp/ that is not gitignored"    "$(w "$bare/tmp/x")"
check 2 "tmp/ outside any repository"    "$(w "$work/plain/tmp/x")"

echo "== denied: traversal and unruleable input (fails closed) =="
check 2 "..-escape out of scratch"       "$(w "$scratch/x/../../../repo/src/f.md")"
check 2 "..-escape out of repo tmp/"     "$(w "$repo/tmp/../src/f.md")"
check 2 "Write with no path"             '{"tool_name":"Write","tool_input":{}}'
check 2 "Write with a relative path"     "$(w "tmp/x.md")"
check 2 "malformed JSON"                 'not json at all'

echo "== denied: symlink, hardlink and glob aliases =="
outside=$work/outside
mkdir -p "$outside"
ln -s "$outside" "$scratch/esc"
printf 'x\n' >"$repo/notes.md"
ln -s "$repo/notes.md" "$scratch/lnk"
ln "$repo/notes.md" "$scratch/hl"
check 2 "symlink + .. escape from scratch" "$(w "$scratch/esc/../pwned.txt")"
check 2 "write beneath a symlinked dir"    "$(w "$scratch/esc/pwned.txt")"
check 2 "write through a symlink leaf"     "$(w "$scratch/lnk")"
check 2 "write through a hardlink leaf"    "$(w "$scratch/hl")"
# From /, an unquoted glob expansion would turn /*mp into /tmp and land the
# path inside the guard's raw /tmp scratch root; literal handling denies it.
cd / || exit 1
check 2 "glob-char path stays literal"     "$(w "/*mp/claude-$(id -u)/x")"
cd "$work" || exit 1
# A newline in the path would truncate normalisation at the first line, so a
# symlink hidden past the newline would carry the write outside scratch.
mkdir -p "$scratch/s"
nlpath="$scratch/s/legit"$'\n'"x"
ln -s "$outside/target.md" "$nlpath"
check 2 "newline path hides symlink leaf"  "$(jq -cn --arg p "$nlpath" \
  '{tool_name: "Write", tool_input: {file_path: $p}}')"

echo "== denied: unknown tools fail closed =="
check 2 "unrecognised tool name"         '{"tool_name":"MysteryTool","tool_input":{"file_path":"/etc/hosts"}}'
check 2 "tool call without a tool name"  '{"tool_input":{"command":"ls"}}'
check 2 "Task is not allowlisted"        '{"tool_name":"Task","tool_input":{"prompt":"spawn"}}'

echo "== Bash: scratch sandboxes allowed =="
check 0 "mkdir in scratch"               "$(b "mkdir -p $scratch/sandbox")"
check 0 "cp fixture into scratch"        "$(b "cp $repo/README.md $scratch/sandbox/")"
check 0 "git init in scratch"            "$(b "git -C $scratch/sandbox init")"
check 0 "git commit in scratch"          "$(b "git -C $scratch/sandbox commit -m x")"
check 0 "git init in gitignored tmp/"    "$(b "git -C $repo/tmp/sandbox init")"
check 0 "redirect into scratch"          "$(b "echo hi > $scratch/notes.txt")"
check 0 "redirect into repo tmp/"        "$(b "echo hi > $repo/tmp/notes.txt")"
check 0 "stderr to /dev/null"            "$(b "grep -rn foo src/ 2>/dev/null")"
check 0 "fd duplication"                 "$(b 'echo err >&2')"
check 0 "ordinary read command"          "$(b "cat $repo/README.md")"
check 0 "git log is not a write verb"    "$(b "git -C $repo log --oneline -5")"
check 0 "git status is not a write verb" "$(b "git -C $repo status")"
check 0 "cp within scratch"              "$(b "cp $scratch/notes.txt $scratch/sandbox/copy.txt")"
check 2 "scratch git config now denied"  "$(b "git -C $scratch/sandbox config user.email probe@example.com")"

echo "== Bash: writes elsewhere denied =="
check 2 "bare git commit (cwd unknowable)" "$(b 'git commit -m x')"
check 2 "git commit in a real repo"      "$(b "git -C $repo commit -m x")"
check 2 "git init outside scratch"       "$(b "git -C $work/elsewhere init")"
check 2 "git init in non-ignored tmp/"   "$(b "git -C $bare/tmp/sandbox init")"
check 2 "cd into scratch then bare git"  "$(b "cd $scratch && git commit -am x")"
check 2 "redirect into a repo file"      "$(b "echo x > $repo/src/notes.md")"
check 2 "append onto a repo file"        "$(b "echo x >> $repo/README.md")"
check 2 "mkdir outside scratch"          "$(b "mkdir -p $work/elsewhere")"
check 2 "rm outside scratch"             "$(b "rm -rf $repo/src")"
check 2 "sed -i on a repo file"          "$(b "sed -i '' s/a/b/ $repo/README.md")"
check 2 "tee onto a repo file"           "$(b "echo x | tee $repo/out.log")"
check 2 "bare dprint fmt"                "$(b 'dprint fmt')"
check 2 "compound git, second -C escapes"  "$(b "git -C $scratch/sandbox commit -m x && git -C $repo commit -m x")"
check 2 "compound git, first -C escapes"   "$(b "git -C $repo commit -m x && git -C $scratch/sandbox init")"
check 2 "compound git, bare second leg"    "$(b "git -C $scratch/sandbox commit -m x; git push")"
check 2 "two -C flags, second escapes"     "$(b "git -C $scratch/sandbox -C $repo commit -m x")"
check 2 "git -C path with .. component"    "$(b "git -C $scratch/esc/../.. init")"
check 2 "git checkout is a write verb"     "$(b "git -C $repo checkout -- .")"
check 2 "git clean is a write verb"        "$(b "git -C $repo clean -fd")"
check 2 "git worktree is a write verb"     "$(b "git -C $repo worktree add ../w")"
check 2 "git branch is a write verb"       "$(b "git -C $repo branch topic")"
check 0 "git checkout in scratch"          "$(b "git -C $scratch/sandbox checkout -b probe")"
check 0 "double-quoted -C scratch path"    "$(b "git -C \"$scratch/sandbox\" commit -m x")"
check 0 "single-quoted -C scratch path"    "$(b "git -C '$scratch/sandbox' commit -m x")"
bt='`'
check 2 "command-substituted git escapes"  "$(b "echo \$(git -C $repo push)")"
check 2 "backticked git escapes"           "$(b "echo ${bt}git -C $repo push${bt}")"
check 2 "--git-dir= escape"                "$(b "git --git-dir=$repo/.git commit -m x")"
check 2 "--work-tree= escape"              "$(b "git --git-dir=$scratch/sandbox/.git --work-tree=$repo commit -m x")"
check 2 "git config is a write verb"       "$(b "git -C $repo config user.name x")"

echo "== Bash: alias planting and write-through denied =="
# $scratch/lnk (symlink to a repo file) and $scratch/hl (hardlink of one) were
# laid above; a write through either would land outside the allowance.
check 2 "cp -s plants an alias in scratch"   "$(b "cp -s $repo/notes.md $scratch/planted")"
check 2 "cp -l plants a hardlink in scratch" "$(b "cp -l $repo/notes.md $scratch/planted")"
check 2 "cp --symbolic-link long form"       "$(b "cp --symbolic-link $repo/notes.md $scratch/planted")"
check 2 "cp -rs bundle hides the flag"       "$(b "cp -rs $repo $scratch/planted")"
check 2 "redirect through planted symlink"   "$(b "echo x > $scratch/lnk")"
check 2 "append through planted symlink"     "$(b "echo x >> $scratch/lnk")"
check 2 "tee through planted symlink"        "$(b "echo x | tee $scratch/lnk")"
check 2 "cp onto planted symlink leaf"       "$(b "cp $repo/README.md $scratch/lnk")"
check 2 "truncate through hardlink leaf"     "$(b "truncate -s0 $scratch/hl")"
check 2 "redirect through hardlink leaf"     "$(b "echo x > $scratch/hl")"

echo "== Bash: scratch git kept off global state =="
check 2 "scratch git config --global"        "$(b "git -C $scratch/sandbox config --global core.hooksPath $scratch/h")"
check 2 "scratch git config --system"        "$(b "git -C $scratch/sandbox config --system core.pager x")"
check 2 "scratch git maintenance register"   "$(b "git -C $scratch/sandbox maintenance register")"
check 2 "scratch git maintenance start"      "$(b "git -C $scratch/sandbox maintenance start")"
check 2 "scratch git tilde escape"           "$(b "git -C $scratch/sandbox config --file ~/.gitconfig core.pager x")"

echo "== Bash: allowlisted read shapes =="
check 0 "git rev-parse"                  "$(b "git -C $repo rev-parse --short HEAD")"
check 0 "git diff"                       "$(b "git -C $repo diff --stat")"
check 0 "git show"                       "$(b "git -C $repo show HEAD --format=%H -s")"
check 0 "git rev-list"                   "$(b "git -C $repo rev-list --count HEAD")"
check 0 "git ls-files"                   "$(b "git -C $repo ls-files src/")"
check 0 "git check-ignore"               "$(b "git -C $repo check-ignore -q tmp/x")"
check 0 "git blame"                      "$(b "git -C $repo blame README.md")"
check 0 "git branch --list"              "$(b "git -C $repo branch --list")"
check 0 "git remote -v"                  "$(b "git -C $repo remote -v")"
check 0 "narrow git fetch (ratified)"    "$(b "git -C $repo fetch origin")"
check 0 "narrow git fetch with --prune"  "$(b "git -C $repo fetch --prune origin")"
check 0 "ls"                             "$(b "ls -la $repo")"
check 0 "head of a file"                 "$(b "head -40 $repo/README.md")"
check 0 "rg without --pre"               "$(b "rg -n pattern $repo/src")"
check 0 "find without -exec"             "$(b "find $repo -name README.md")"
check 0 "sed print range"                "$(b "sed -n '1,40p' $repo/README.md")"
check 0 "sed substitution"               "$(b "sed 's/foo/bar/g' $repo/README.md")"
check 0 "awk column print"               "$(b "awk '{print \$1}' $repo/README.md")"
check 0 "sort into uniq"                 "$(b "sort $repo/README.md | uniq -c")"
check 0 "pipe into wc"                   "$(b "cat $repo/README.md | wc -l")"
check 0 "jq over a file"                 "$(b "jq -r .name $repo/x.json")"
check 0 "command -v"                     "$(b 'command -v jq')"
check 0 "cd then read"                   "$(b "cd $repo && grep -rn foo src/")"
check 0 "date formatting"                "$(b 'date +%Y-%m-%d')"
check 0 "sandbox init and commit chain"  "$(b "git -C $scratch/sandbox init && git -C $scratch/sandbox commit -m probe")"
check 0 "rm cleans up scratch probe"     "$(b "rm -rf $scratch/sandbox")"

echo "== Bash: deny-by-default =="
check 2 "unlisted binary"                "$(b 'curl https://example.com')"
check 2 "eval"                           "$(b 'eval echo hi')"
check 2 "sh -c"                          "$(b "sh -c 'echo hi'")"
check 2 "bash -c"                        "$(b "bash -c 'echo hi'")"
check 2 "xargs"                          "$(b 'echo x | xargs rm')"
check 2 "env prefix"                     "$(b "env GIT_DIR=$repo/.git git commit -m x")"
check 2 "quoted-separator git escape"    "$(b "git -c k.v=\"a;b\" -C $repo commit -m x")"
check 2 "git -c config injection"        "$(b "git -c core.pager=less -C $repo log")"
check 2 "git log --output writes"        "$(b "git -C $repo log --output=$repo/pwned")"
check 2 "refspec git fetch force-write"  "$(b "git -C $repo fetch . +HEAD:refs/heads/main")"
check 2 "git fetch by URL"               "$(b "git -C $repo fetch https://example.com/r.git")"
check 2 "sort -o writes"                 "$(b "sort -o $repo/pwned $repo/README.md")"
check 2 "find -delete"                   "$(b "find $repo -name x -delete")"
check 2 "find -exec"                     "$(b "find $repo -name x -exec rm {} +")"
check 2 "sed w command"                  "$(b "sed -n 'w$repo/pwned' $repo/README.md")"
check 2 "sed e flag executes"            "$(b "sed 's/a/b/e' $repo/README.md")"
check 2 "awk system() is severed"        "$(b "awk 'BEGIN{system(\"rm -rf $repo\")}'")"
check 2 "rg --pre executes"              "$(b "rg --pre=$repo/evil.sh foo $repo")"
check 2 "cp destination outside"         "$(b "cp $scratch/x $repo/y")"
check 2 "scratch git push escapes"       "$(b "git -C $scratch/sandbox push origin trunk")"
check 2 "scratch git flag-value escape"  "$(b "git -C $scratch/sandbox format-patch --output-directory=$repo")"

echo "== 19f: flag abbreviation, mv sources, rm cleanup =="
check 2 "git --glob abbreviation"        "$(b "git -C $scratch/sandbox config --glob user.name x")"
check 2 "git unknown flag denies"        "$(b "git -C $scratch/sandbox commit --amend")"
check 0 "git commit -m still allowed"    "$(b "git -C $scratch/sandbox commit -m probe")"
check 2 "mv from outside unlinks source" "$(b "mv $repo/README.md $scratch/x")"
check 0 "mv wholly inside scratch"       "$(b "mv $scratch/a $scratch/b")"
check 2 "cp long-option abbreviation"    "$(b "cp --symbolic $repo/README.md $scratch/l")"
check 0 "rm a scratch symlink"           "$(b "rm $scratch/lnk")"
check 0 "rm one side of a hardlink pair" "$(b "rm $scratch/hl")"
check 2 "rm outside the allowance"       "$(b "rm $repo/README.md")"
check 2 "mv -t escapes the operand scan" "$(b "mv -t$repo $scratch/a $scratch/b")"
check 2 "ln -t escapes the operand scan" "$(b "ln -t$repo $scratch/x")"
check 2 "quoted flag bypass"             "$(b "git -C $scratch/sandbox commit \"--amend\"")"
check 2 "send-pack reaches a remote"     "$(b "git -C $scratch/sandbox send-pack host:path main")"
check 0 "mv with bare -- separator"      "$(b "mv -- $scratch/a $scratch/b")"

echo
printf 'pass=%s fail=%s\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
