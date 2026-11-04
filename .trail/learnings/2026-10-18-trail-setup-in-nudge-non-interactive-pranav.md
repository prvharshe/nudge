---
title: "trail setup in nudge: non-interactive init"
author: Pranav
date: 2026-10-18
branch: main
touches:
  - ".codebase-memory/artifact.json"
  - ".codebase-memory/graph.db.zst"
---

## Decided
- trail is wired for Claude Code only, repo-scoped: `trail init --agents claude --no-global`. The user chose not to touch ~/.claude, ~/.codex, or the Cursor/Gemini/Copilot/opencode files.

## Tried and ruled out
- Plain `trail init` from an agent shell writes nothing: with no TTY it requires `--agents ...` or `--yes`.
- `--yes` alone wires every detected agent and also writes user-level files (~/.claude/settings.json, ~/.codex/*), which affects all repos. Use `--dry-run` to preview, `--no-global` to keep it in the repo.

## Watch out
- nudge is not a git repo, so `.trail/` (learnings included) isn't committed or shared until someone runs `git init`.
- `.trail/cache/` is git-ignored local state; rebuild with `trail build`.
