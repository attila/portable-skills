# Fall back to a worker session

Load this only when the in-process executors of `dispatch-worker.md` do not
apply. Everything else in the dispatch phase is unchanged — the handover, the
fence, the gates and the terminal signal all stand.

Two routes, both session-backed. Prefer the first where the harness offers it.

## Dispatch a background session

On Claude Code, `bin/claude-code/dispatch-worker.sh` launches a genuine session:
full convention injection on both hook surfaces, and per-dispatch write scoping
that `scope-guard.sh` enforces from roots baked into the dispatch — the one
thing the in-process path cannot do. Watch it with `bin/claude-code/watch-worker.sh`,
which rules on the job's timeline and its report. A resume yields a **new** job
id; watch that one.

It needs two primitives: a background-session dispatch and a reachable
supervisor. Probe for both before dispatching; either missing, use the human
route below.

**Its standing cost, and why it is not the default.** A worker's processes
never exit — no idle timeout, no reclaim when the job settles, roughly
0.9 GB a pair held for the life of the Claude home. No job id maps to a process,
so nothing kills one worker; `claude daemon stop` is the only lever and it
clears every background session in the home. Run one orchestrator per home,
bounce the home once the engagement's units are confirmed complete, and never
dispatch from a home a second orchestrator is also using. If upstream adds idle
pruning or a per-job reclaim, this route is worth reinstating as the default.

## Hand the worker to the human

Where no automated primitive exists at all, emit:

```text
🚀 HANDOFF → worker · <lane> · <unit>
Launch:    open a session; first message asserts the role, then points at
           the file — "You are the WORKER, not the orchestrator. Read and
           execute <path> directly." — never a bare file reference
Does:      <one line>
Back when: it prints ✅ COMPLETE, ⏸️ PAUSED AT GATE, or 🛑 BLOCKED
Meanwhile: <independent orchestrator work, or "waiting — nothing to do">
```

Then let the human launch the worker. Do not simulate the handoff inside the
orchestrator session.

Field evidence: a bare file reference let session-start orientation run first,
so the session read itself as orchestrator and re-dispatched the brief
(`spec-executor-model.md`, fourth entry) — the prefix above closed it. On the
automated path the same prefix is carried by the dispatch itself, where it
cannot be mistyped.

The handback returns by hand too: the human pastes the worker's terminal signal,
and `ingest-handback.md` validates it exactly as it validates a watcher's clean
verdict.
