# portable-skills

Agent Skills for orchestrating work across a multi-repository workspace.

Two skills, both built around the same idea: an agent working across several
repositories needs to know what is actually true before it acts, and needs a
record of the work that survives the session it happened in.

## The skills

| Skill                  | What it does                                                                                                                       |
| ---------------------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| `aw-orienting`         | Refresh a workspace and every repository in it before relying on what they say. Covers cold start, targeted refresh, and divergence. |
| `orchestration-kernel` | Run a multi-unit engagement across dispatched worker agents: roles, lane scheduling, self-contained handovers, and control gates.    |

`orchestration-kernel` ships working guards for Claude Code. They are
`PreToolUse` hooks that confine what a dispatched worker may write — one for a
worker that writes a repository, one for a worker that writes nothing — with
their own test suites under `skills/orchestration-kernel/bin/claude-code/`.

## Using them

Each skill is a directory with a `SKILL.md` at its root, which is the format
Claude Code and Codex both read. Point your agent at them however your tool
expects: symlink a directory into `.claude/skills/`, copy one in, or add this
repository as a submodule and link from there.

Both skills assume a workspace laid out as several repositories under one root,
with a `context/` directory holding the record of the work — state, decisions,
findings, and a per-engagement ledger. They are written against `aw`, a
workspace tool, but nothing in them requires it: the shape is what matters, and
the commands degrade to plain git where the tool is absent.

## Scope

This repository is shared for reference and reuse. Issues, pull requests, wiki
edits, support requests, and feature requests are not accepted.

## Licence

MIT. See `LICENSE`.
