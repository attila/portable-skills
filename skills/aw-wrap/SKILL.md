---
name: aw-wrap
description: >-
  Make an aw workspace session durable before it ends. Use before compaction,
  before switching to unrelated work, when the human says to wrap up or park
  something, and at any natural pause in a long session. Sweeps what the session
  produced that is not yet written down, routes each loose end to the register
  or ledger that owns it, reconciles every summary record against reality, and
  commits the layer. Also use on its own when asked whether the records agree
  with each other and with reality. The counterpart of aw-orienting. Not for
  landing work in a member repository.
---

# Wrapping up an aw workspace session

Everything the session knows and has not written down dies at compaction. This
is the pass that moves it into the layer. It is meant to run often, so it stays
short: refresh, sweep, route, reconcile, commit.

## 1. Refresh before writing

Fetch the workspace layer and fast-forward it if it is behind, then re-read
every section you are about to change. Another session may have written there.
`aw-orienting` owns the full procedure — follow it, do not reinvent it. If the
layer is both ahead and behind, stop and report; never merge it unasked.

## 2. Sweep for loose ends

Scan the session — not the files — for anything that would be lost. Work
through these, out loud, one line each:

- **Rulings.** Anything settled in conversation that will bind later work.
- **Durable facts.** Something discovered that stays true after this task:
  a behaviour, a constraint, a mapping, a confirmed absence.
- **Verification.** Commands run and their output, still unrecorded.
- **In flight.** Work started and not finished; anything blocked and on whom.
- **Raised, not resolved.** Questions put to a human, drafts awaiting approval,
  things the human said they would do.
- **Member-repo state.** Branches pushed, pull requests opened or merged,
  checkouts left dirty or on a merged branch.

Nothing found is a valid outcome. Say so and stop.

## 3. Route each one

The subject owns the record — file it against the topic it acts on, not the one
where it came up.

| Loose end | Home |
| --- | --- |
| A binding ruling | `DECISIONS.md`, numbered, append-only |
| A durable fact | `FINDINGS.md` |
| Run detail, verification verbatim | the owning engagement's ledger |
| What a cold session needs to resume | `STATE.md` |

A ledger entry carries the command and its output verbatim; `STATE.md` points at
the ledger and never quotes it. If the owning engagement has no ledger, open
one — `STATE.md` is not a fallback home for run detail. A subject with no
engagement stays an open item in `STATE.md`; do not mint an engagement to
receive a single record.

## 4. Reconcile the summary records against reality

Summary records are what go stale: `STATE.md` items and `## Next`, a ledger's
board table, a plan's unit list, an engagement's registry status. Narrative
ledger entries are dated history; leave them alone and fix the rows. For every
engagement the session touched, check all of its summary records, not just the
`STATE.md` item. Grepping them for status words — not started, ruled, pending,
in flight, blocked — finds the rows that make claims.

Each status is a claim about a fact some system owns. Code state — branches,
merges, pull requests, releases — belongs to the code host; a ticket's status to
the tracker; a ruling or a plan to the layer itself. Which systems those are is
the workspace's arrangement, declared in its own instruction files: a client's
Jira or Linear, a public issue tracker, or the layer as its own tracker. Check
each claim against its owner, read-only, fetching first. Never check it against
what the session remembers. If the workspace declares no owners, ask once and
suggest it records them. An owner you cannot reach — no access, no credentials,
the sandbox — does not make the claim agree: report it as unverified, with the
reason.

Rewrite each stale record in place — replace its fields with the present state.
If your edit only adds text you are writing a changelog; stop and rewrite. For a
`STATE.md` item: does Now still name what is happening, is Blocked still
blocked, does the Ledger line still point somewhere live. Bump the item's date
only when you have re-read it against reality, never as a formality. Keep
`## Next` pointing at live slugs.

## 5. Commit the layer

Run the repository's artefact lint, fix what it flags, commit, and push if an
origin is configured. This layer commits unconditionally — no sign-off needed.
One conventional `doc(<topic>):` commit per subject reads better later than one
sweep commit, but do not split hairs over it.

## Boundaries

- **The layer only.** Never commit, push or branch in a member repository here.
  Unlanded member work is reported as a loose end, not landed.
- **Never a decision gate.** If the sweep turns up something that conflicts with
  a settled decision, record the conflict and raise it; do not resolve it.
- **No secrets, ever** — not in `context/`, not in any tracked file.
