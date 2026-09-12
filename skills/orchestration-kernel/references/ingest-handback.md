# Ingest a handback

Use this phase when a worker settles — on the automated path, when its watcher
rules; on the fallback path, when the human returns its terminal HANDBACK
signal.

## Act on the watcher's verdict

A dispatched worker's watcher settles into one of four verdicts. They decide
whether this phase runs at all.

| Verdict | What it means | What to do |
| ------- | ------------- | ---------- |
| clean | settled `done`, report present, `kind` as declared | ingest it — continue below |
| missing | settled without writing its report | bounce once |
| wrong-kind | report present, `kind` not as declared | bounce once |
| blocked | stopped at a gate or blocker | surface to the human |
| timeout | the watcher gave up; the worker's state is unknown | surface to the human — never bounce, and never record the unit either way |

**Bounce once, never twice.** Resume the same worker with
`--resume <session-id>`, quoting exactly what was wrong; its context carries, so
never restate the unit. The resume returns a **new job id** — watch that one. A
second failure of the same kind surfaces to the human with the worker's
transcript path.

**A timeout is not a verdict on the work.** The worker may still be running.
Establish its real state before acting — the roster and `claude attach` both
answer — and never treat the silence as failure or as success.

**Never retry a blocker.** A blocker is a judgement, not a slip. Once a human
clears the gate, the unit continues as a **fresh dispatch** whose brief carries
the sign-off — never as a bounce of the blocked worker, whose picture of the
repository is stale by definition, a gate being precisely the moment a human
changed something.

## Validate the signal and report

1. Accept exactly one state: `✅ COMPLETE`, `⏸️ PAUSED AT GATE` or `🛑 BLOCKED`.
2. Resolve the stated report path and confirm that it belongs to the expected
   engagement and unit.
3. Read the report as a claim, not as authoritative global state.
4. Check that required sections and verbatim verification output are present.

Reject an incomplete or ambiguous handback: bounce it to the worker, or on the
fallback path ask the human to return it, rather than reconstructing missing
evidence.

## Re-verify before recording

Fetch before making cross-repository claims. Re-check commit identifiers,
branches, pull-request state, checks and relevant file claims against the
specific checkout and remote.

Check the workspace layer's own `git log` against its state before dispatch,
every time, regardless of the report's `Workspace layer touched:` line —
field evidence (2026-08-11) shows that attestation can be wrong or absent.
Silence is not a clean bill; only the log is.

Use `git -C <absolute-path>` for every repository command. Record resulting
identifiers such as `main → <short-sha>`, not uncheckable verbs such as
“fast-forwarded”.

If re-verification conflicts with the report, record the discrepancy and use
live truth. Never silently repair or reinterpret the worker's claim.

## Reconcile by terminal state

A handback carries two separate facts: **unit position** (complete, at-gate,
blocked) and **executor liveness** (resumable, terminated). A session at a gate
is resumable — the human resumes that session directly. A subagent at a gate is
terminated by design, whatever the harness's resume mechanics happen to
support, so the orchestrator resumes the **unit**, not the executor.

For `✅ COMPLETE`:

- record verified results and advance dependent units;
- ingest the worker report into the workspace layer;
- perform post-merge worktree and local-branch cleanup when the applicable gate
  has been cleared.

For `⏸️ PAUSED AT GATE`:

- verify the exact approval artefact;
- update the ledger with the paused position, and record the executor's
  liveness alongside it;
- present that artefact and its destination to the human;
- if the executor is terminated (any in-process executor), do not attempt to
  resume it. Once the gate clears, dispatch a continuation whose brief is the
  terminated executor's own resume note, taken verbatim from the last act of
  its report — see `dispatch-worker.md`. A resumable session executor is
  simply resumed by the human instead.

For `🛑 BLOCKED`:

- verify the evidence that can be checked locally;
- condense the blocker using the control-contract format;
- update the ledger without inventing a resolution.

## Make state durable

Update the ledger only after verification. Inspect the workspace diff and stage
the ledger, report and other intended artefacts by explicit path. Never use
blanket staging: a worker or concurrent process may have left unrelated changes
that would otherwise ride into durable history.

Commit and push the workspace layer according to its own durability policy.
Workers never perform this step.

Treat cleanup as the orchestrator's responsibility. A worker has stopped by
handback and cannot remove its worktree safely after later gates or merges.
Sweep any worker scratch that survived handback — session-scratchpad residue
and gitignored `tmp/` sandboxes — at ingest and again at engagement
conclusion.

## Halt on signals already held

Any of these stops the loop and calls the human. Each is a lookup against the
report and the ledger, never content judgement:

- a worker returned `🛑 BLOCKED`;
- a report's verification block is missing, or a command exited non-zero;
- `## Decisions needed` or `## Deferred` is non-empty;
- `git -C <member_repo_path> status` shows writes outside the unit's declared
  file set;
- the plan's acceptance criteria are not all evidenced.

Judging whether the work is slop is content judgement, not a lookup — dispatch
a reviewer instead of judging it directly.

## Dispatch a reviewer by default

A writing unit's `✅ COMPLETE` handback auto-dispatches a reviewer before the
next unit, unless the plan declares an opt-out for that unit. The reviewer is
read-only, in-process, no worktree, no gate — cheap enough that default-on
costs little, and default-off would miss exactly the units nobody thought to
flag.

The reviewer returns a halt-shaped verdict — `pass`, `findings` or
`blocking` — so the orchestrator acts on the bounded return without reading
the review body itself:

- `pass`: advance as usual;
- `findings`: auto-dispatch a new worker with the review report as its brief,
  to evaluate and fix what was flagged;
- `blocking`: halt the loop for the human, same as the signals above.

The reviewer reviews the diff against the plan's acceptance criteria, never
the worker's own report — treating the report as authority launders the
worker's account instead of checking it.
