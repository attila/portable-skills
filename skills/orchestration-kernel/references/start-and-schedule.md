# Start and schedule an engagement

Use this phase when creating an engagement, resuming after context loss or idle
time, or deciding which unit may run next.

## Establish authoritative state

1. Read the engagement ledger before doing anything else. Store live engagement
   state in `context/engagements/<engagement>/ledger-<slug>.md`, not in this
   skill.
2. Confirm that no other orchestrator is active. If another session owns the
   ledger, require an explicit handover before writing it.
3. Fetch and inspect the specific repositories and remotes relevant to the next
   unit. Target every checkout explicitly with `git -C <absolute-path>`.
4. Reconcile the ledger against live truth. Never report remembered branch,
   commit, pull-request or check state after an idle period.
5. On conflicting claims, prefer the ledger only after reconciling it against
   live state. Flag the conflict; never average sources.

The ledger owns current global status. Worker reports record what one worker
did. Decisions belong in the workspace decisions register. Keep each fact in one
authoritative place.

## Declare implementation units

Give every unit:

- one objective and verifiable acceptance criteria;
- one member repository;
- explicit dependencies;
- `scope: scoped` with a named file set, or `scope: sweeping`;
- exact verification commands;
- the applicable repository gates;
- one uniquely named handover and report path.

Reject a scoped declaration whose possible writes are unknown. Treat repository-
wide formatting, mass renames and codemods as sweeping.

## Build lanes

Order dependent units within a lane. Run units concurrently only when their
repositories differ or their declared file sets are disjoint.

A sweeping unit takes an exclusive lock on its repository. Do not run any other
writer in that repository until it finishes. Sequencing care cannot make a
whole-tree rewrite disjoint.

Keep the ledger single-writer even when implementation runs concurrently.
Workers write only their own report files; the orchestrator ingests those
reports and advances the ledger.

## Select a ready unit

A unit is ready when every clause is checkable from the ledger and the
ratified plan alone:

1. it is declared in the ratified plan with acceptance criteria, one member
   repository and exact verification commands;
2. every declared dependency is complete and ingested into the ledger, not
   merely reported complete by a worker;
3. its scope does not collide with an active writer — different repository,
   or declared file sets proven disjoint, and no sweeping unit holds that
   repository's lock;
4. its brief carries no unresolved decision (`dispatch-worker.md` already
   forbids dispatching one);
5. it does not open at a human gate.

A continuation dispatch — resuming a unit after `⏸️ PAUSED AT GATE`, see
`ingest-handback.md` — does not re-enter this check: the unit was already
found ready when first dispatched.

## Auto-dispatch on completion

On a `✅ COMPLETE` handback the orchestrator may dispatch the next ready unit
without surfacing it to the human. The control point is plan ratification: a
ratified plan's units already carry acceptance criteria and exact
verification commands (clause 1 above), scrutinised before execution starts,
so auto-dispatch runs against a plan that already earned that scrutiny.
Automating the planning step itself is out of scope. The loop runs until no
unit is ready, a gate opens, or a worker blocks.

The per-ingest ledger commit — already durable and pushed after every
handback — stands as the trace of this progress; no separate line format.

## Apply the human control contract

Check the decisions register before asking anything. Apply an existing precedent
directly and cite it in the ledger. Treat an unratified default as a decision,
not a convention.

When a new decision is required:

1. Present one decision per message.
2. Give numbered options, their consequences and one recommendation.
3. Wait for the human's numeric reply.
4. Record the decision before using it.

At an approval gate, end with the exact artefact and destination being approved,
such as the staged file set, commit or pull request. A summary alone is not an
approval surface.

When blocked, present:

```text
Blocker — <lane/unit>: <one line>
Blocked on: <the action that cannot proceed>
Evidence: <two or three verified facts>
Options: 1. <choice and consequence> 2. <choice and consequence>
Recommendation: <number and reason>
Unblocks: <the immediate next action>
```

After the human decides, update the handover fragment from the recorded
decision. Do not paraphrase it from memory.
