---
name: aw-orienting
description: >-
  Refresh an aw workspace and its member repositories before relying on what
  they say. Use when starting or resuming a session in a workspace, before
  editing STATE.md, DECISIONS.md, FINDINGS.md or an engagement ledger, and
  before asserting any member repository's branch position, merge or CI state.
  Covers the cold-start full refresh, the mid-session targeted fetch, divergence
  handling and what to report when a fetch fails. Also use when the human asks
  to ff the members, fast-forward the members or bring the members up to date.
  Not for ordinary work inside a single member repository once its state is
  already established.
---

# Orienting in an aw workspace

A workspace checkout is one of several. Other sessions and other machines push
to the same remotes, and a stale read looks exactly like a current one. Refresh
first, then read.

## Cold start — full refresh

Two `aw` commands carry the whole refresh. Fetching repositories one by one, or
counting divergence per checkout by hand, duplicates work `aw` already does
across every member at once — and a refresh assembled by hand is how one
repository silently gets left out.

1. **`aw sync`** — fetches the workspace layer and every member repository, one
   reported line each. It exits non-zero if any fetch failed.
2. **`aw status`** — reports, per repository including the layer, ahead and
   behind counts against upstream plus working-tree cleanliness. Read this
   rather than running `git status -sb` or `git rev-list --count` yourself. Its
   unlisted-checkout lines matter too: a worktree left behind after its branch
   merged reads to the next session as live work.
3. **Fast-forward the layer** when step 2 shows it behind and not ahead:
   `git -C <root> merge --ff-only @{u}`. This step is raw git deliberately —
   `aw` writes a working tree only through `aw fast-forward`, which never
   touches the layer, and this write is a judgement call.
4. **If the layer is both ahead and behind, stop.** Report the divergence and
   let the human decide; never merge or rebase the workspace layer unasked.
5. **A member repository behind its upstream is not yours to fast-forward
   unasked.** Surface the count before reading or asserting anything from that
   checkout, the same way layer divergence is surfaced in step 4. When the human
   asks for the members to be brought up to date, run `aw fast-forward`: it
   moves only clean checkouts on their default branch and reports the rest (see
   Boundaries).
6. Read `context/STATE.md`, then the registers it points at, then the open
   engagement's plan and ledger.
7. Report what changed since your last picture if you are resuming, not just the
   current state.

> **Is `aw` on PATH?** Confirm with `command -v aw` before concluding it is
> unavailable. If it genuinely is missing, build and install it from the
> agentic-workspace repository and re-run. Only when that is impossible, degrade
> to raw git — `git fetch` in the layer and in every member checkout for step 1,
> `git -C <path> rev-list --count HEAD..@{u}` per repository for step 2 — and
> say in your report that you ran the degraded path, and why.

## Mid-session — targeted fetch

One repository, one ref. Do not re-run the full refresh.

`aw sync` is whole-workspace by construction — its argument is the workspace
root, never a single member — so a targeted `git fetch` here is the correct
tool, not the degraded path above.

- **Before editing a register** — `STATE.md`, `DECISIONS.md`, `FINDINGS.md` or
  an engagement ledger. Fetch the workspace root, fast-forward if behind, and
  re-read the section you are about to change. A stale edit is not rejected on
  push: it fast-forwards cleanly and leaves your section contradicting whatever
  another session already wrote there.
- **Before asserting a member repository's state** — a branch position, a merge,
  a pull request status, a CI result. Fetch that one repository first. Never
  quote any of these from memory or from an earlier turn.
- **When the human says they have worked elsewhere** — treat it as a cold start
  and refresh in full.
- **Before landing work in a member repository** — a commit, a push, a branch, a
  pull request. Read that repository's declared delivery model in its own
  instruction files first, every time. `STATE.md` points at the declaring file
  and never copies what it says, because the workspace recognises a delivery
  model and never controls it. A repository that declares nothing takes the
  conservative default: commit, push a feature branch, open a draft pull
  request, and stop there.

## When a fetch fails

`aw sync` names the failing repository on its own line and exits non-zero. Say
so, and label everything downstream of that repository as possibly stale. Do not
proceed quietly on the last known state, and do not present a conclusion drawn
from it as current.

A repository reported `not present, skipped` has not failed. It is declared in
the manifest and absent from disk, so facts about it are unavailable rather than
stale, and the remedy is `aw bootstrap` rather than another fetch. Report it as
a provisioning gap.

## Boundaries

- Fetching is read-only and safe unattended. Fast-forwarding the workspace layer
  is safe because that layer is committed and pushed automatically by its own
  governance.
- Run `aw fast-forward` only when the human asks, and never move a member
  repository any other way: no merge, rebase, pull or checkout. Worker sessions
  own those working trees; otherwise you refresh their remote refs only.
- Divergence is a decision gate, never something to resolve on your own.
