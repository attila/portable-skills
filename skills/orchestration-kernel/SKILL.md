---
name: orchestration-kernel
description: >-
  Run a multi-unit engagement across dispatched worker executors in an aw
  workspace. Use for gated implementation units with dependencies, work across
  multiple repositories, or safely parallel work over disjoint file sets.
  Define orchestrator and worker roles, lane scheduling, self-contained
  handovers, the single-writer engagement ledger, and human control gates. Do
  not use for single-unit or solo-agent work.
---

# Orchestration kernel

Run one orchestrator in the workspace repository. Dispatch each unit to its own
in-process executor — a writing one for implementation, a write-nothing one for
discovery and review. Separate worker sessions remain available as a fallback;
the dispatch reference says when to reach for one.

## Respect the base contract

Read the workspace and target repository instruction files before running an
engagement. Treat them as authoritative for:

- human-only actions and approval gates;
- verification evidence;
- pull-request wording and publication rules;
- repository-specific delivery autonomy.

Apply this skill only as the orchestration delta. Never replace or weaken the
base contract. When a member repository declares no delivery model, default
conservatively: allow a signed commit, feature-branch push and draft pull
request; stop before ready-for-review, merge or a protected-branch push.

## Preserve these invariants

- Every executor is orchestrator or worker. The orchestrator alone writes the
  workspace layer, and writes nothing else; a worker writes its member
  repository and its own report file, nothing else.
- Keep exactly one active orchestrator and one writer for the engagement ledger.
- Give each worker one implementation unit and one disjoint report file.
- Keep workers blind to shared coordination state; inline every required fact in
  the handover.
- Dispatch every unit to an executor satisfying the executor contract: one
  canonical absolute worktree; writes confined to the role's allowance;
  blindness to shared coordination state, every required fact inlined; and a
  declared ability to suspend and resume, or a requirement to terminate on a
  blocker.
- Gates belong to the human, never an executor, whatever launched it. An
  executor may waive a gate only under authorisation recorded in advance and
  scoped to a named class of action — the shape this workspace's durability
  pre-authorisation and each member repository's delivery model already use.
- Bind the worker role to an agent definition where the harness supports one —
  on Claude Code, `worker-writing` for a unit that writes and `worker` for one
  that does not, each carrying the guard that enforces its allowance. Prose
  remains the carrier where the harness has no such format; Codex and Crush have
  none.
- Inline into the handover every skill and convention the unit needs. An
  in-process executor is listed its skills by name but loads none of them, and
  receives no pattern catalogue, so anything it must apply up front has to be
  named or quoted rather than assumed.
- Run units concurrently only across independent repositories or proven disjoint
  file sets.
- Reach for a worker session only under the dispatch reference's fallback, and
  bounce the Claude home afterwards: every session-backed worker stays resident
  for the life of that home, and nothing reclaims one short of clearing all of
  them.
- Re-verify worker claims against live repository and remote state before
  recording them.
- Make workspace state durable according to its policy, using explicit paths
  rather than blanket staging.

## Confine reads to lookup, not judgement

The orchestrator orchestrates; it does not read code, review a diff, decide
content or write anything but the layer's own records. Three ringfences:

- **Bounded return** — a lookup returns a scalar (a SHA, a boolean, a status,
  a count); prose, a diff or a file body means the work is a dispatch.
- **Reads confined to the layer's own records** — ledger, plan, handovers,
  reports, registers, never a member-repository file, with one exception:
  `git -C <member_repo_path> status`, a path-only check for writes outside a
  unit's declared file set.
- **No composite shell** — one command, one lookup.

Deferred, no mechanism yet: a lookup-count budget across a run of individually
valid lookups, and where an allow-list enforcing this would live.

**Guard boundary**: both agent guards contain writes through their fail-closed
file-tool path rules; each guard's Bash rules are best-effort tripwires only.
The write-nothing `worker` writes session scratch and gitignored `tmp/`
alone.

## Load one phase reference

Read only the reference for the current phase. Do not preload every reference.

| Phase                                            | Required reference                                        |
| ------------------------------------------------ | --------------------------------------------------------- |
| Start or resume; decompose and schedule units    | [start-and-schedule.md](references/start-and-schedule.md) |
| Prepare and dispatch a worker                    | [dispatch-worker.md](references/dispatch-worker.md)       |
| Fall back to a worker session                    | [fallback-handoff.md](references/fallback-handoff.md)     |
| Receive a handback; verify and reconcile state   | [ingest-handback.md](references/ingest-handback.md)       |
| Debug, review or change this orchestration model | [failure-rationale.md](references/failure-rationale.md)   |

Never load `failure-rationale.md` during routine execution.

## Run the operating loop

1. Start or resume from the ledger, reconcile it against live truth, then build
   dependency-ordered lanes.
2. Select a ready unit whose declared scope can run safely.
3. Prepare its handover, then dispatch by what the unit writes:
   `worker-writing` for a member repository, `worker` for a unit that writes
   nothing. Where neither applies, fall back to a worker session.
4. An in-process executor's returned text is the HANDBACK — proceed straight to
   step 5. A fallback session is watched instead, and only independent
   orchestrator work continues while it runs.
5. Ingest exactly one HANDBACK state, re-verify its report, update the ledger,
   and make the resulting workspace state durable.
6. Repeat until every unit is complete or the next action is a human gate or
   genuine blocker.

Do not invent an unresolved convention. Consult the decisions register first;
surface only genuinely new decisions to the human.

## Honour the loading budget

`bin/lint-skills` defines and enforces the canonical token budgets. Routine
phase loading must fit the entrypoint plus one operational reference. Treat a
budget failure as a design failure: remove duplication or split by function;
never raise a ceiling merely to admit accumulated prose.
