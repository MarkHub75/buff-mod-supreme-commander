# FAF Buff Draft Mod



## Context

We are building a private SIM+UI mod for Supreme Commander: Forged Alliance Forever.



## Core Rules

Gameplay logic must live in SIM, not UI.

UI must only display data and send player choices to SIM.

Do not add UI, buffs, balance changes, or gameplay changes unless explicitly asked.

Do not globally mutate blueprints for side-specific effects.

Prefer minimal hooks and small files over rewriting FAF core files.

Do not add "Co-authored-by Codex" or similar AI attribution to commits.

Add useful information to docs/FINDINGS.md if you discover something in references or online.



## Workflow

1. Before coding: inspect the project structure and search needed references if it exists. Also check docs/FINDINGS.md. 

2. If needed, search online or in references before guessing.

3. Implement change. 

4. After coding: do not talk too much. Say only main things. 



## Technical Notes

SupCom Lua is not normal Lua; copy patterns from FAF code instead of guessing.

Use LOG/WARN messages with prefix FAF_BUFF_DRAFT.

Keep diffs small, focused, and easy to revert.