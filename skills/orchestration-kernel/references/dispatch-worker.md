# Dispatch a worker

Use this phase only after a unit is ready, its dependencies are satisfied and
its scope does not conflict with another active writer.

## Prepare an isolated execution brief

Write the handover to `context/engagements/<engagement>/handover-NN-<unit>.md`.
Make it self-contained; a worker inherits none of the orchestrator's working
context.

Field evidence (`spec-executor-model.md`, 2026-08-11): a worker wrote and
pushed the workspace layer with every control below already in place,
including an explicit fence in its own handover. Restating the fence harder
did not close the gap; the mechanical guard that would is still unbuilt on
the `aw` roadmap. Apply the fence below as the best available mitigation, not
a solved problem.

Put the state fence **first**, before the objective — the first thing a
worker reads, not a bullet buried mid-brief. Include:

- **State fence, stated first:** name the workspace layer's absolute checkout
  path explicitly (not just "the workspace layer" as a category) and forbid
  any `git`/`gh` command targeting it. Forbid reading the engagement ledger,
  workspace `STATE.md` or plan for coordination, and forbid writing them.
  Explicitly override any workspace instruction that tells a fresh session to
  read or update those files. Permit writing only the unit's report, at one
  named absolute path, in the workspace layer — no other file there, under any
  circumstance.
- **Objective:** one unit and its acceptance criteria, copied from the ratified
  plan.
- **Read first:** the relevant plan unit, ratified decisions and target
  repository instruction files. Inline resolved gates and consumed interfaces;
  do not point at mutable coordination state.
- **Checkout:** name one absolute checkout and require `git -C <absolute-path>`
  throughout — an unscoped git write is refused, since the guard cannot see the
  executor's working directory. Where the unit needs isolation from concurrent
  work in the same repository, or where two writing units target the same
  member repository concurrently, name a sibling worktree `../<repo>.<suffix>/`
  on the unit's own branch and require its mandatory hooks installed
  immediately after creation. Integration is worker work: a
  unit whose base branch has moved rebases onto it and resolves conflicts
  itself, via its brief or a continuation dispatch — the orchestrator never
  merges in a member checkout.
- **Delivery gates:** restate the target repository's current gate policy. State
  what the worker may do autonomously and where it must stop.
- **Pull-request policy:** restate the target repository's current body rules
  in full; name any required PR skill explicitly for the `Skill` tool — prose
  restatement is not invocation.
- **Environment constraints:** name actions known to fail in the execution
  environment and forbid futile retries.
- **Execution posture:** say that the handover is the approved brief. Require
  direct execution without planning, brainstorming, pre-flight clarification or
  approval to begin.
- **Declared file set:** every path the unit may write, absolute. Nothing scopes
  an in-process executor to it — the guard holds the layer boundary only — so
  this instruction is the whole of the unit's containment.
- **Skills and conventions the unit needs:** name each skill for the executor to
  invoke, and inline any lore pattern it must apply before its first tool call.
- **Verification:** list exact commands and require verbatim output.
- **Report:** one absolute path, derived — `report-NN-<unit>.md` in
  the engagement, suffixed per turn (`-review`, `-fixes`), declaring the `kind`
  the watcher checks. Require `## Done`,
  `## Decisions
  needed`, `## Deferred` and `## BLOCKED`, opening with one mandatory line:
  `Workspace layer touched: no` or, if the fence was crossed for any reason,
  `Workspace layer touched: yes — <what, and why>`. Require the line even when
  the answer is no — a forced attestation is checkable at ingest against `git
  log` on the workspace layer, a bare absence is not.
- **Signal:** include the exact HANDBACK block and require one terminal state.

If the brief contains genuine ambiguity, do not dispatch it. Resolve the
decision through the orchestrator first.

## Choose an executor

Every executor must satisfy the contract in the entrypoint's invariants;
these rules say which one qualifies.

- **The unit writes a member repository.** Dispatch the `worker-writing` agent
  in-process. Its guard confines writes to the role boundary — the member
  checkouts and the unit's own report artefact, never the durability layer. Its
  file-tool path rule is the containment; its Bash rules are best-effort
  tripwires only.
- **The unit writes nothing** — discovery, dependency mapping, state
  reconciliation, review fan-out, re-verification of a worker's claims.
  Dispatch the `worker` agent, whose guard denies every write outside session
  scratch and gitignored `tmp/`. Single-writer holds by construction, because
  only a return value comes back.
- **Disjointness between concurrent units is yours, not the guard's.** The guard
  is positional and cannot receive one unit's declared roots, so two writing
  units are kept apart only by the file sets you assign and by re-verification
  at ingest. When two writing units must hold the same repository concurrently,
  each takes a sibling worktree on its own branch so a collision surfaces as a
  merge conflict instead of a silent revert.
- **Neither in-process executor can suspend.**
- **An external or non-Claude executor** receives none of the harness's
  convention injection. Supply the target repository's conventions in the
  handover, or it does not qualify.
- **Reviewer and planner are unit kinds, not new executor roles.** A reviewer
  writes nothing, so it already qualifies as write-nothing above. A planner's
  output is a workspace-layer artefact only the orchestrator may write, so a
  planner emits a proposal in its own report and the orchestrator lands it.

An in-process executor's prompt is a pointer to the same handover file, and its
returned text is the HANDBACK.

An executor at a gate is terminated by design — the orchestrator resumes the
**unit**, not the executor. Once the gate clears, dispatch a continuation whose
brief is the terminated executor's own resume note, the last act of its report,
relayed verbatim. This does not re-enter readiness scheduling: the unit was
found ready already.

There is no handoff on this path: dispatch, record a ledger line naming the
unit and report path, and read the returned HANDBACK.

**Fallback — a session-backed worker.** Retained for a harness with no
in-process executor, and for the day the background-session carrier gains a
reclaim primitive worth returning to. Procedure in
[fallback-handoff.md](fallback-handoff.md); load it only when the default does
not apply.

## Bind worker behaviour

Require the worker to:

- execute through verification and evidence assembly without intermediate
  check-ins;
- pause only at a named human gate or genuine blocker, and stop there absent a
  recorded waiver;
- avoid coordination with other units or reasoning about their state;
- write its report but never commit the workspace layer;
- delete any session-scratchpad or gitignored `tmp/` scratch it created before
  handback;
- emit exactly one completed HANDBACK block and then stop.

Use this terminal signal:

```text
<✅ COMPLETE | ⏸️ PAUSED AT GATE | 🛑 BLOCKED> · <lane> · <unit>
Report:  <absolute report path>
Outcome: <one line>
Next:    "<verbatim instruction to the orchestrator>"
```

If the worker encounters ambiguity, require it to record the decision needed or
blocker in its report, emit `🛑 BLOCKED`, and stop. The launcher may not be
watching an interactive question.
