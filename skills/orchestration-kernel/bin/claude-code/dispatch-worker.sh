#!/bin/bash
# Dispatch one worker as a background session and, optionally, watch it.
#
# Claude Code only. Assembles the command line the choreography requires and
# nothing else — it holds no policy about when a unit is ready, which is the
# orchestrator's judgement.
#
# Usage:
#   dispatch-worker.sh --handover PATH --report PATH [options]
#
#   --handover PATH    absolute path to the unit's handover (required)
#   --report PATH      absolute path the unit must write (required)
#   --kind KIND        frontmatter kind the report must declare (default: report)
#   --cwd DIR          directory to dispatch from; the worker inherits it
#   --allow DIR        an additional writable root, repeatable, absolute
#   --lore DIR         lore's Claude Code plugin directory
#   --resume ID        resume a settled worker's session instead of starting one
#   --id-file PATH     write the job id here as well as to stdout
#   --timeout SECONDS  passed to the watcher (default: its own)
#   --watch            after dispatching, run the watcher in the foreground
#
# Prints the new job id on stdout. A resume always yields a NEW job id, so the
# caller must use the id printed here and never the settled one. With --watch
# the watcher's output follows on the same stream, so pass --id-file when the
# caller needs the id independently of the watch.

set -euo pipefail

CDPATH=''
here=$(cd -- "$(dirname -- "$0")" && pwd)
kind=report
cwd=
resume=
lore=
watch=
handover=
report=
id_file=
timeout=
declare -a allow=()

while [ $# -gt 0 ]; do
  case "$1" in
    --handover) handover=$2; shift 2 ;;
    --report) report=$2; shift 2 ;;
    --kind) kind=$2; shift 2 ;;
    --cwd) cwd=$2; shift 2 ;;
    --allow) allow+=("$2"); shift 2 ;;
    --lore) lore=$2; shift 2 ;;
    --resume) resume=$2; shift 2 ;;
    --id-file) id_file=$2; shift 2 ;;
    --timeout) timeout=$2; shift 2 ;;
    --watch) watch=1; shift ;;
    *) echo "dispatch-worker.sh: unknown argument $1" >&2; exit 64 ;;
  esac
done

fail() { echo "dispatch-worker.sh: $1" >&2; exit "${2:-64}"; }

[ -n "$handover" ] || fail "--handover is required"
[ -n "$report" ] || fail "--report is required"
command -v jq >/dev/null 2>&1 || fail "jq is not on PATH; the scope guard cannot be built without it" 70

# Roots are baked into the guard's command line, so a relative one would never
# match the absolute paths the file tools report, silently blocking the unit
# from its own report.
declare -a roots=("$report")
[ ${#allow[@]} -gt 0 ] && roots+=("${allow[@]}")
for root in "${roots[@]}"; do
  case "$root" in
    /*) ;;
    *) fail "--report and --allow must be absolute; got: $root" ;;
  esac
done

# Both probes read output and ignore exit status on purpose: `claude daemon
# status` exits non-zero while reporting a perfectly reachable socket, because
# its header describes an installed background service we deliberately do not
# have.

# Primitive 1 — a harness that can dispatch a background session.
help_out=$(claude --help 2>&1 || true)
grep -q -- '--bg' <<<"$help_out" \
  || fail "no background-session primitive: fall back to a human-launched session" 69

# Primitive 2 — a reachable supervisor. Read the bg sessions block, never the
# header, which prints 'not running' inside a sandbox regardless.
status_out=$(claude daemon status 2>&1 || true)
grep -q 'control\.sock:[[:space:]]*reachable' <<<"$status_out" \
  || fail "supervisor unreachable: ask for it to be started before dispatching" 70

# Quote every root, so a path containing a space, a semicolon or a substitution
# reaches the guard as one argument instead of becoming shell syntax.
guard=$(printf '%s\n' "$here/scope-guard.sh" "${roots[@]}" \
  | jq -Rsc 'split("\n")[:-1] | map(@sh) | join(" ")' | jq -r .)

# Prove the guard blocks before trusting it with a worker. A hook that exits
# anything but 2 is treated as non-blocking, so a mispathed or broken guard is
# indistinguishable from an absent one once the worker is running.
probe='{"tool_input":{"file_path":"/dev/null/definitely-outside-every-scope"}}'
set +e
printf '%s' "$probe" | eval "$guard" >/dev/null 2>&1
probe_status=$?
set -e
[ "$probe_status" -eq 2 ] \
  || fail "the scope guard did not block an out-of-scope path (exit $probe_status); refusing to dispatch unfenced" 70

settings=$(jq -nc --arg cmd "$guard" \
  '{hooks:{PreToolUse:[{matcher:"Write|Edit|NotebookEdit",hooks:[{type:"command",command:$cmd}]}]}}')

set -- --bg --dangerously-skip-permissions --settings "$settings"
if [ -n "$lore" ]; then set -- "$@" --plugin-dir "$lore"; fi
if [ -n "$resume" ]; then set -- "$@" --resume "$resume"; fi

prompt="You are the WORKER, not the orchestrator. Read and execute $handover directly."
if [ -n "$cwd" ]; then cd "$cwd"; fi

roster() { claude agents --json --all 2>/dev/null | jq -r '.[] | .id // empty' 2>/dev/null; }
before=$(roster || true)
dispatched=$(date +%s)

banner=$(claude "$@" "$prompt" 2>&1) || true

# The banner is a convenience, never the authority: by the time it is parsed the
# session already exists, so a wording change would otherwise leave a running
# worker nobody is watching. The roster is what actually knows.
job=$(printf '%s' "$banner" | sed -n 's/^backgrounded ·[[:space:]]*\([0-9a-fA-F]\{4,\}\).*/\1/p' | head -1)
if [ -z "$job" ] || ! printf '%s\n' "$(roster || true)" | grep -qx "$job"; then
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    job=$(comm -13 <(printf '%s\n' "$before" | sort) <(roster | sort) | head -1)
    [ -n "$job" ] && break
    sleep 1
  done
fi

if [ -z "$job" ]; then
  echo "dispatch-worker.sh: no job id could be resolved. The worker may be running unwatched." >&2
  printf '%s\n' "$banner" >&2
  exit 1
fi

echo "$job"
[ -n "$id_file" ] && printf '%s\n' "$job" >"$id_file"

if [ -n "$watch" ]; then
  set -- "$job" "$report" "$kind" --since "$dispatched"
  if [ -n "$timeout" ]; then set -- "$@" --timeout "$timeout"; fi
  exec "$here/watch-worker.sh" "$@"
fi
exit 0
