#!/bin/bash
# PreToolUse guard for the kernel's `worker-writing` agent.
#
# An in-process writing executor may write its member repository and its own
# report artefact. It may not write the workspace's durability layer — that
# belongs to the orchestrator role alone. This enforces the role boundary
# mechanically rather than leaving it to the prompt. That mechanical enforcement
# is the precondition: an in-process executor was barred from writing any
# repository until the boundary held without depending on the prompt, and this
# guard is what lifted the bar.
#
# The rule is positional, not per-unit. The `Agent` tool exposes no per-call
# hook or settings parameter, so unlike `scope-guard.sh` this cannot receive one
# unit's declared roots at dispatch. Disjointness *between* concurrent units is
# therefore instruction plus the orchestrator's re-verification. That is a
# knowingly accepted cost, taken when in-process executors became the default:
# per-unit scope enforcement was traded away for them, and re-verification at
# ingest is what covers the gap. What this guard delivers is that no unit,
# however it strays, writes the layer that records the engagement.
#
# Containment is the Write/Edit path rule below, and only that. The Bash rules
# are best-effort tripwires for common write shapes, no more: an
# interpreter one-liner passes them, and enumerating interpreters is unwinnable.
#
# Fails CLOSED, on the same reasoning as `scope-guard.sh`: anything it cannot
# rule on with confidence is denied, because a guard whose failure mode is
# "allow" reports success identically to a guard that works.

set -uo pipefail

deny() {
  echo "Blocked: $1" >&2
  exit 2
}

# Collapse `.` and `..` lexically, then resolve symlinks on the deepest existing
# ancestor. Lexical first, because realpath cannot normalise a path whose leaf
# does not exist yet — which is every file a worker is about to create.
normalise() {
  local path=$1 part joined head tail resolved
  local -a out=()
  local IFS=/
  for part in $path; do
    case "$part" in
      '' | .) ;;
      ..) [ ${#out[@]} -gt 0 ] && unset "out[$((${#out[@]} - 1))]" && out=(${out[@]+"${out[@]}"}) ;;
      *) out+=("$part") ;;
    esac
  done
  joined="/${out[*]-}"
  IFS=$' \t\n'

  head=$joined
  tail=""
  while [ "$head" != "/" ] && [ ! -e "$head" ]; do
    tail="/$(basename -- "$head")$tail"
    head=$(dirname -- "$head")
  done
  if [ -d "$head" ]; then
    resolved=$(cd -P -- "$head" 2>/dev/null && pwd -P) || resolved=$head
    printf '%s%s' "${resolved%/}" "$tail"
  else
    printf '%s' "$joined"
  fi
}

command -v jq >/dev/null 2>&1 \
  || deny "the guard cannot run — jq is not on PATH, so no write can be ruled on"

[ -n "${CLAUDE_PROJECT_DIR:-}" ] \
  || deny "CLAUDE_PROJECT_DIR is unset, so the workspace layer cannot be located"

case "$CLAUDE_PROJECT_DIR" in
  /*) ;;
  *) deny "CLAUDE_PROJECT_DIR is relative, so the workspace layer cannot be located" ;;
esac

root=$(normalise "$CLAUDE_PROJECT_DIR")

input=$(cat) || deny "the guard could not read the tool call"
tool=$(printf '%s' "$input" | jq -r '.tool_name // empty') \
  || deny "the tool call is not parseable JSON"

# Paths the file tools carry. Bash is handled separately below, because a shell
# command has no path field to read.
target=$(printf '%s' "$input" \
  | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty')

case "$tool" in
  Write | Edit | NotebookEdit)
    [ -n "$target" ] \
      || deny "$tool carried no path, so the guard cannot rule on it"
    case "$target" in
      /*) ;;
      *) deny "$tool carried the relative path $target, which the guard cannot resolve" ;;
    esac

    resolved=$(normalise "$target")

    # Outside the workspace root entirely: scratch or an unrelated checkout, and
    # the sandbox bounds it. Only the layer is this guard's business.
    case "$resolved" in
      "$root"/*) ;;
      *) exit 0 ;;
    esac

    relative=${resolved#"$root"/}

    # Member repositories are inner repos *beneath* the root, so depth is not
    # the test — the layer is a fixed, enumerated set of paths. Everything the
    # inverted `.gitignore` hides from the layer is a member checkout and is
    # this executor's to write.
    case "$relative" in
      # The one write into the layer a worker owns: its own report artefact, in
      # the engagement directory that dispatched it, plus that engagement's
      # untracked scratch.
      context/engagements/*/report-*.md | context/engagements/*/tmp/*) exit 0 ;;
      context/*)
        deny "$relative is the workspace durability layer, which only the orchestrator writes — a worker writes its member repository and its own report artefact"
        ;;
      .claude/* | .githooks/* | bin/*)
        deny "$relative is workspace instance configuration, which only the orchestrator writes"
        ;;
      tmp/*) exit 0 ;;
      */*) exit 0 ;;
      *)
        deny "$relative is a workspace layer root file, which only the orchestrator writes"
        ;;
    esac
    ;;

  Bash)
    command=$(printf '%s' "$input" | jq -r '.tool_input.command // empty')
    [ -n "$command" ] || exit 0

    # Best-effort, and deliberately narrow. A shell command's write targets
    # cannot be recovered reliably, so this catches the three shapes that would
    # actually corrupt the layer — committing it, redirecting into it, and
    # editing or formatting it in place — rather than pretending to a
    # completeness it cannot have. An interpreter one-liner still gets through;
    # the path rule above is the real containment.

    # A git write verb must name its repository explicitly, and that repository
    # must not be the layer. Bare `git commit` is denied rather than guessed at:
    # the hook cannot see the worker's working directory, and the workspace root
    # is exactly where it is most likely to be standing.
    if printf '%s' "$command" \
      | grep -Eq '(^|[;&|[:space:]])git([[:space:]]+-[^[:space:]]+([[:space:]]+[^[:space:]]+)?)*[[:space:]]+(add|commit|push|reset|restore|rm|mv|stash|apply|am|rebase|merge|cherry-pick|revert)([[:space:]]|$)'; then
      scoped=$(printf '%s' "$command" \
        | sed -n 's/.*git[[:space:]]\{1,\}-C[[:space:]]\{1,\}\([^[:space:]]*\).*/\1/p')
      [ -n "$scoped" ] \
        || deny "that git command does not name its repository with -C, so the guard cannot rule out the workspace layer"
      case "$(normalise "$scoped")" in
        "$root")
          deny "that command writes the workspace layer's git state, which only the orchestrator does"
          ;;
      esac
    fi

    escaped_root=$(printf '%s' "$root" | sed 's/[.[\*^$\/]/\\&/g')
    layer_path="(($escaped_root/)?(context|\.claude|\.githooks)/|(^|/)bin/)"

    # A worker legitimately writes and formats its own report artefact, which
    # lives in the layer. Blank those paths out first, so the rules below judge
    # only what is left — the layer paths the unit has no claim on.
    residue=$(printf '%s' "$command" | sed -E \
      "s#($escaped_root/)?context/engagements/[^/[:space:]]+/(report-[^[:space:]]*|tmp/[^[:space:]]*)##g")

    if printf '%s' "$residue" | grep -Eq ">{1,2}[[:space:]]*('|\")?$layer_path"; then
      deny "that command redirects into the workspace durability layer, which only the orchestrator writes"
    fi

    # In-place editors and formatters name their target as an argument rather
    # than a redirect, so the rule above misses them entirely. Deny the pair:
    # a write-shaped command word anywhere, and a layer path anywhere.
    if printf '%s' "$command" \
      | grep -Eq '(^|[;&|[:space:]])(sed[[:space:]]+-[^[:space:]]*i|perl[[:space:]]+-[^[:space:]]*i|tee|dd|cp|mv|rm|ln|truncate|shred|install|chmod|chown|dprint[[:space:]]+fmt)([[:space:]]|$)'; then
      if printf '%s' "$residue" | grep -Eq "$layer_path"; then
        deny "that command writes into the workspace durability layer, which only the orchestrator writes"
      fi
      # `dprint fmt` with no path formats the whole repository from the root,
      # which is the layer, so it needs no layer path to reach it.
      if printf '%s' "$command" \
        | grep -Eq '(^|[;&|[:space:]])dprint[[:space:]]+fmt[[:space:]]*($|[;&|])'; then
        deny "a bare 'dprint fmt' formats the whole workspace layer; name your own file instead"
      fi
    fi
    exit 0
    ;;

  *)
    exit 0
    ;;
esac
