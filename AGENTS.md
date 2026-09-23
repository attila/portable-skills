# Agent instructions

This repository holds Agent Skills, one directory per skill under `skills/`.
Each has a `SKILL.md` at its root carrying `name` and `description`
frontmatter.

Read the `SKILL.md` of the skill you need. Do not preload every skill, and do
not preload every reference file inside one — a skill that splits its guidance
across `references/` says which reference belongs to which phase, and loading
the rest wastes the context it was split up to save.

The shell scripts under a skill's `bin/` are working tools, not examples. Each
has a test suite beside it; run that before changing one.

A skill's `agents/` directory holds Claude Code agent definitions that belong
to it. Each names a guard under the same skill's `bin/`, so change the two
together.
