# Failure rationale

Read this reference only when debugging, reviewing or changing the orchestration
model. These rules come from observed failures rather than theoretical
preferences.

## Workers wrote shared state

Workers launched from the workspace root inherited its automatic commit-and-push
instruction. Several edited and pushed `STATE.md` and the engagement ledger,
breaching the single-writer boundary. The content happened to agree; divergent
facts would have produced a conflict in signed durable history.

Current controls:

- inline required facts in the handover instead of linking mutable state;
- state the orchestrator-only fence explicitly;
- require workers to write only their report;
- make the orchestrator review the workspace diff and stage explicit paths;
- scope the workspace durability instruction explicitly to the orchestrator
  role at source, in `CLAUDE.md` itself, rather than leaving it standing
  behind a fence a worker session could still read as its own grant.

Candidate mechanical control: deny worker sessions write access to the
workspace layer.

Recurred 2026-08-11 with every current control above already in place — the
CLAUDE.md scoping control included, landed before this worker was dispatched —
plus the handover restating the fence in plain language. The worker wrote and
pushed to `trunk` anyway, then confirmed it directly when asked. Prose fencing
is not undertested; it is tested and insufficient. The candidate mechanical
control is the only one left standing (`spec-executor-model.md`'s field
evidence carries the incident).

Ruled out by measurement (2026-08-02): launching from inside the member worktree
so workspace-root instructions are not inherited. Probing an in-process executor
showed both the user's and the project's instruction files injected into it in
full, durability mandate included, whatever the launch location. Fencing must be
stated in the executor's own prompt.

## Sweeping work nearly overlapped scoped work

A repository-wide formatter nearly ran alongside a unit adding a file because
“sequence work in a repository” was read as advice. A sweeping operation cannot
be file-disjoint from another writer.

Current control: require `scope: scoped | sweeping`; give sweeping units an
exclusive repository lock.

Candidate mechanical control: make the scheduler reject concurrent writers
whenever either unit declares sweeping scope.

## Ambient working directory identified the wrong checkout

An engagement may have the main checkout, several worktrees and reviewer clones
of one repository. Shell working directories persist across commands. A reviewer
operated on a stray clone and read its reflog, then drew a false conclusion
about the orchestrator's checkout.

Current controls:

- target every repository command with `git -C <absolute-path>`;
- verify the exact working copy;
- record resulting commit identifiers rather than action verbs.

Candidate mechanical control: assign every unit one canonical absolute worktree
path and generate repository commands from it.

## Interactive skills stopped a prepared worker

A fresh worker session auto-loaded planning and brainstorming instructions and
asked the human for permission rather than executing its already approved
handover. The launcher was not necessarily watching that session.

Current control: make the handover override interactive planning for that worker
session and redirect genuine ambiguity to a `🛑 BLOCKED` report.

Candidate mechanical controls:

- launch workers in a mode that suppresses interactive skill injection;
- place the execution override in a preamble read before other skills;
- detect an attempted question and redirect it to the terminal blocker signal.
