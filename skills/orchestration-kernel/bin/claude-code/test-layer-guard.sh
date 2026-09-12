#!/bin/bash
# Fixture suite for layer-guard.sh. Run from an aw workspace root.
#
# Every case is a real PreToolUse payload fed to the guard on stdin; the guard
# is pure, so no dispatch and no worker are needed to exercise it.
set -uo pipefail

guard=$(dirname -- "$0")/layer-guard.sh
root=$(pwd -P)
export CLAUDE_PROJECT_DIR=$root

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

echo "== allowed: member repositories and scratch =="
check 0 "member repo source file"        "$(w "$root/member-repo/src/module/notes.md")"
check 0 "member repo nested path"        "$(w "$root/other-repo/README.md")"
check 0 "member repo root-level file"    "$(w "$root/member-repo/AGENTS.md")"
check 0 "workspace scratch tmp/"         "$(w "$root/tmp/notes.md")"
check 0 "outside the workspace entirely" "$(w "/private/tmp/scratch/x.md")"

echo "== allowed: the worker's own report artefact =="
check 0 "report in engagement dir"       "$(w "$root/context/engagements/an-engagement/report-u1.md")"
check 0 "engagement scratch tmp/"        "$(w "$root/context/engagements/an-engagement/tmp/probe.txt")"

echo "== denied: the durability layer =="
check 2 "STATE.md"                       "$(w "$root/context/STATE.md")"
check 2 "DECISIONS.md"                   "$(w "$root/context/DECISIONS.md")"
check 2 "an engagement ledger"           "$(w "$root/context/engagements/an-engagement/ledger-run.md")"
check 2 "an engagement plan"             "$(w "$root/context/engagements/an-engagement/plan-work.md")"
check 2 "instance agent definition"      "$(w "$root/.claude/agents/worker.md")"
check 2 "instance hook"                  "$(w "$root/.claude/hooks/worker-guard.sh")"
check 2 "layer bin/"                     "$(w "$root/bin/lint-artefacts")"
check 2 "layer root file CLAUDE.md"      "$(w "$root/CLAUDE.md")"
check 2 "layer root file workspace.toml" "$(w "$root/workspace.toml")"

echo "== denied: traversal onto the layer =="
check 2 "..-escape from a member repo"   "$(w "$root/member-repo/../context/STATE.md")"
check 2 "..-escape from engagement tmp"  "$(w "$root/context/engagements/an-engagement/tmp/../../../STATE.md")"
check 2 "report-shaped path via .."      "$(w "$root/context/engagements/an-engagement/../../STATE.md")"

echo "== denied: unruleable input (fails closed) =="
check 2 "Write with no path"             '{"tool_name":"Write","tool_input":{}}'
check 2 "Write with a relative path"     "$(w "context/STATE.md")"
check 2 "malformed JSON"                 'not json at all'

echo "== Bash: layer writes denied, member writes allowed =="
check 2 "git -C <root> commit"           "$(b "git -C $root commit -m x")"
check 2 "git -C <root> add"              "$(b "git -C $root add -A context")"
check 2 "redirect into context/"         "$(b "echo hi > $root/context/NOTES.md")"
check 2 "redirect into relative context/" "$(b 'echo hi >> context/STATE.md')"
check 0 "git -C <member> commit"         "$(b "git -C $root/member-repo commit -m x")"
check 0 "redirect into a member repo"    "$(b "echo hi > $root/member-repo/src/x.md")"
check 0 "ordinary read command"          "$(b 'grep -rn foo member-repo/src')"

echo "== Bash: adversarial =="
check 2 "bare git commit (cwd unknowable)"   "$(b 'git commit -m x')"
check 2 "cd into layer then commit"          "$(b "cd $root && git commit -am x")"
check 2 "compound, layer commit second"      "$(b "ls && git -C $root push origin HEAD")"
check 2 "git rebase without -C"              "$(b 'git rebase origin/trunk')"
check 2 "tee into context/"                  "$(b "echo x > $root/context/FINDINGS.md")"
check 0 "compound, both member-scoped"       "$(b "git -C $root/member-repo add -A && git -C $root/member-repo commit -m x")"
check 0 "git status is not a write verb"     "$(b "git -C $root status")"
check 0 "git log is not a write verb"        "$(b 'git log --oneline -5')"

echo "== Bash: in-place editors and formatters =="
check 2 "bare dprint fmt (whole layer)"      "$(b 'dprint fmt')"
check 2 "dprint fmt on a layer path"         "$(b 'dprint fmt context/STATE.md')"
check 2 "sed -i on a layer path"             "$(b "sed -i '' s/a/b/ $root/context/STATE.md")"
check 2 "perl -i on a layer path"            "$(b 'perl -i -pe s/a/b/ context/FINDINGS.md')"
check 2 "tee into a layer path"              "$(b 'echo x | tee context/NOTES.md')"
check 2 "cp over a layer file"               "$(b "cp /tmp/x $root/context/STATE.md")"
check 2 "rm a layer file"                    "$(b 'rm context/FINDINGS.md')"
check 0 "dprint fmt on the worker's report"  "$(b "dprint fmt $root/context/engagements/an-engagement/report-1-x.md")"
check 0 "sed -i inside a member repo"        "$(b "sed -i '' s/a/b/ $root/member-repo/src/x.md")"
check 0 "grep over the layer is a read"      "$(b 'grep -rn foo context/')"
check 0 "cat a layer file is a read"         "$(b 'cat context/STATE.md')"
check 0 "dotted .bin/ is not the layer bin/" "$(b "rm $root/member-repo/node_modules/.bin/tsx")"
check 2 "layer bin/ is still caught in Bash" "$(b "rm $root/bin/lint-artefacts")"

echo
printf 'pass=%s fail=%s\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
