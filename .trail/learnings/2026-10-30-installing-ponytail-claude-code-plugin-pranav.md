---
title: Installing ponytail Claude Code plugin
author: Pranav
date: 2026-10-30
branch: main
cost: { minutes: 3, tokens: 39964 }
touches:
  - ".codebase-memory/artifact.json"
  - ".codebase-memory/graph.db.zst"
  - CLAUDE.md
---

## Decided
- Installed ponytail v5.3.3 (DietrichGebert/ponytail) at user scope via CLI: `claude plugin marketplace add DietrichGebert/ponytail` then `claude plugin install ponytail@ponytail`.
- Reviewed hooks before install: SessionStart, SubagentStart and UserPromptSubmit hooks, plus a band UI module. The only network call is the optional webhook (empty by default). It writes a local ledger to ~/.config/ponytail/band/.

## Tried and ruled out
- Nothing ruled out. The README's `/plugin` slash commands map directly to `claude plugin ...` in the CLI.

## Watch out
- The installer warns about 4 unset userConfig options. They have safe defaults; change them with `/plugin configure ponytail@ponytail`.
- Ponytail injects instructions every session and into every subagent, alongside CLAUDE.md, context-mode and trail. Use `/ponytail off` if it conflicts.
- Only install from DietrichGebert/ponytail or @dietrichgebert/ponytail. The author says genuine copies never ship .exe/.dll files.
