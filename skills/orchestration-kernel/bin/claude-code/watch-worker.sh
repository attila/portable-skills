#!/bin/bash
# Watch one dispatched worker to its terminal state and rule on its handback.
#
# Claude Code only. Emits one line per step on stdout while the worker works,
# then one VERDICT line, and exits.
#
# Usage:
#   watch-worker.sh <job-id> <report-path> [kind] [--timeout SECONDS]
#                                                 [--since EPOCH]
#
#   kind        frontmatter kind the report must declare; skipped if omitted
#   --timeout   give up after this long (default 3600, one hour)
#   --since     treat a report older than this epoch as stale (default: the
#               job's own createdAt from its state.json, not the watcher's
#               start time — a watcher started well after dispatch must not
#               call its own late start the origin of freshness)
#
# Exit codes — five outcomes, each distinct, because "no answer" and "bad
# answer" must never look alike to the orchestrator:
#   0  clean       terminal, report present, fresh, kind as declared
#   1  blocked     terminal at a gate or blocker
#   2  missing     terminal without a fresh report
#   3  wrong-kind  report present but its frontmatter kind is not the one asked
#   4  timeout     the watcher gave up; the worker's state is UNKNOWN
#   5  internal    the watcher could not do its job

set -uo pipefail

readonly CLEAN=0 BLOCKED=1 MISSING=2 WRONG_KIND=3 TIMEOUT=4 INTERNAL=5
poll=2
timeout=3600
started=$(date +%s)
since=$started
since_explicit=
job=""
report=""
kind=""

while [ $# -gt 0 ]; do
  case "$1" in
    --timeout) timeout=$2; shift 2 ;;
    --since) since=$2; since_explicit=1; shift 2 ;;
    --poll) poll=$2; shift 2 ;;
    -*) echo "watch-worker.sh: unknown argument $1" >&2; exit $INTERNAL ;;
    *)
      if [ -z "$job" ]; then job=$1
      elif [ -z "$report" ]; then report=$1
      elif [ -z "$kind" ]; then kind=$1
      else echo "watch-worker.sh: unexpected argument $1" >&2; exit $INTERNAL
      fi
      shift ;;
  esac
done

[ -n "$job" ] && [ -n "$report" ] || {
  echo "watch-worker.sh: <job-id> and <report-path> are required" >&2
  exit $INTERNAL
}
case "$job" in
  *[!0-9a-fA-F-]* | "") echo "watch-worker.sh: implausible job id: $job" >&2; exit $INTERNAL ;;
esac
command -v jq >/dev/null 2>&1 || { echo "watch-worker.sh: jq is not on PATH" >&2; exit $INTERNAL; }

jobs_dir=${CLAUDE_JOBS_DIR:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/jobs}
timeline="$jobs_dir/$job/timeline.jsonl"
state_file="$jobs_dir/$job/state.json"
# The deadline runs from the watcher's own start; --since is a freshness
# reference for the report, never a clock origin.
deadline=$((started + timeout))
offset=0

say() { echo "[$job] $*"; }

# The report's kind lives in the leading frontmatter block, nowhere else. A
# substring search over the head of the file would accept a body that merely
# quotes its handover, and reject a long frontmatter that pushes the field down.
declared_kind() {
  awk 'NR==1 && $0!="---" {exit} NR==1 {next} /^---[[:space:]]*$/ {exit}
       /^kind:[[:space:]]*/ {sub(/^kind:[[:space:]]*/,""); gsub(/^["'"'"']|["'"'"']$/,"");
                             sub(/[[:space:]]+$/,""); print; exit}' "$1" 2>/dev/null
}

modified_at() { stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null; }

# state.json's own createdAt is the job's dispatch time as the supervisor
# recorded it — the only origin safe to default `since` to when the caller
# never passed one. The watcher's own start time is not: a caller that
# dispatches without --watch (the --id-file path exists precisely for this)
# and watches later starts its watcher after the report may already be
# written, which would call genuinely fresh work "stale" and misreport a
# successful unit as missing.
job_created_at() {
  local iso
  iso=$(jq -r '.createdAt // empty' "$1" 2>/dev/null) || return 1
  [ -n "$iso" ] || return 1
  date -j -u -f '%Y-%m-%dT%H:%M:%S' "${iso%%.*}" +%s 2>/dev/null \
    || date -u -d "$iso" +%s 2>/dev/null
}

rule() {
  local state=$1 mtime declared
  if [ ! -f "$report" ]; then
    say "VERDICT missing — settled $state, nothing at $report"
    return $MISSING
  fi
  mtime=$(modified_at "$report")
  if [ -z "$mtime" ]; then
    say "VERDICT internal — cannot stat $report"
    return $INTERNAL
  fi
  # A report older than the dispatch is a leftover from an earlier attempt, and
  # believing it would record work that never happened.
  if [ "$mtime" -lt "$since" ]; then
    say "VERDICT missing — settled $state, but $report predates this dispatch"
    return $MISSING
  fi
  if [ -n "$kind" ]; then
    declared=$(declared_kind "$report")
    if [ "$declared" != "$kind" ]; then
      say "VERDICT wrong-kind — $report declares '${declared:-nothing}', not '$kind'"
      return $WRONG_KIND
    fi
  fi
  if [ "$state" != "done" ]; then
    say "VERDICT blocked — $state, report at $report"
    return $BLOCKED
  fi
  say "VERDICT clean — report at $report"
  return $CLEAN
}

# Consume only whole lines. A line read mid-append would otherwise be counted as
# seen and never re-read — and the terminal event, which carries the worker's
# closing message, is the largest line in the file and the likeliest to tear.
drain() {
  local size chunk complete
  size=$(wc -c <"$timeline" 2>/dev/null | tr -d ' ') || return 0
  [ -n "$size" ] && [ "$size" -gt "$offset" ] || return 0
  chunk=$(tail -c "+$((offset + 1))" "$timeline" 2>/dev/null) || return 0
  case "$chunk" in
    *$'\n'*) complete=${chunk%$'\n'*}$'\n' ;;
    *) return 0 ;;
  esac
  offset=$((offset + ${#complete}))
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    local state detail
    state=$(printf '%s' "$line" | jq -r '.state // "?"' 2>/dev/null) || continue
    detail=$(printf '%s' "$line" | jq -r '.detail // ""' 2>/dev/null)
    if [ -n "$detail" ]; then say "$state: $detail"; else say "$state"; fi
  done <<<"$complete"
}

while :; do
  now=$(date +%s)
  if [ "$now" -ge "$deadline" ]; then
    say "VERDICT timeout — no terminal state after ${timeout}s; the worker's state is unknown"
    exit $TIMEOUT
  fi

  [ -f "$timeline" ] && drain

  # state.json is the supervisor's own view. Its firstTerminalAt is the
  # authority on whether the session has ended: `blocked` is also written for a
  # session that is merely waiting, and ruling on the state name alone would
  # settle a worker that is still running.
  if [ -f "$state_file" ]; then
    terminal_at=$(jq -r '.firstTerminalAt // empty' "$state_file" 2>/dev/null)
    if [ -n "${terminal_at:-}" ]; then
      state=$(jq -r '.state // "?"' "$state_file" 2>/dev/null)
      [ -f "$timeline" ] && drain
      if [ -z "$since_explicit" ]; then
        created_epoch=$(job_created_at "$state_file") && [ -n "$created_epoch" ] && since=$created_epoch
      fi
      rule "$state"
      exit $?
    fi
  fi

  sleep "$poll"
done
