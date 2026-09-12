#!/bin/bash
# PreToolUse guard for a dispatched worker's file tools.
#
# Refuses Write and Edit outside the roots named on the command line: the unit's
# report artefact, and the member checkouts the handover declares. The
# orchestrator bakes those roots into one dispatch's --settings string, so two
# concurrent workers never share a scope.
#
# Fails CLOSED. Anything it cannot rule on with confidence — unparseable input,
# a missing dependency, a tool call with no path, a relative root — is denied. A
# guard whose failure mode is "allow" reports success identically to a guard
# that works.
#
# Write-shaped Bash is deliberately not policed: write targets cannot be
# recovered reliably from a shell command, and the handover's declared file set
# governs it instead. The sandbox bounds the blast radius regardless; this guard
# exists to keep concurrent workers out of each other's files inside it.

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

[ $# -gt 0 ] || deny "the guard was given no allowed roots"

input=$(cat)
target=$(printf '%s' "$input" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' 2>/dev/null) \
  || deny "the guard could not parse its input"
[ -n "$target" ] || deny "the tool call carries no path the guard can rule on"

case "$target" in
  /*) ;;
  *) deny "$target is not absolute, so it cannot be checked against this unit's scope" ;;
esac

target=$(normalise "$target")

for allowed in "$@"; do
  case "$allowed" in
    /*) ;;
    *) deny "the guard was given a relative root ($allowed); roots must be absolute" ;;
  esac
  root=$(normalise "${allowed%/}")
  case "$target" in
    "$root" | "$root"/*) exit 0 ;;
  esac
done

deny "$target is outside this unit's declared scope. Allowed: $*"
