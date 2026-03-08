---
name: debating
description: "Multi-round Claude vs Codex structured debate"
---

# /symphony:debate — Multi-Round Debate

> **allowed-tools**: `mcp__codex__codex`, `mcp__codex__codex-reply`, `Read`, `Bash`, `Grep`, `Glob`

## Purpose

Structured multi-round debate between Claude and Codex on a topic. Both models are equals. Claude proposes, Codex critiques, they iterate until convergence or max rounds.

Key upgrade from CodeMoot: same thread throughout — Codex accumulates understanding across rounds.

## Flow

### 1. Claude generates opening proposal

- Analyze the topic from `$ARGUMENTS`
- If codebase-relevant: gather context (read files, check patterns)
- Write structured opening:
  - **Position**: Claude's stance
  - **Reasoning**: Why (with evidence from codebase if relevant)
  - **Trade-offs**: What Claude acknowledges as downsides

### 2. Send to Codex (Protocol 1)

Build handoff with:
- Purpose: "Structured debate on: <topic>"
- What Was Done: Claude's opening proposal
- What To Check: "Critique this proposal. State your STANCE (SUPPORT/OPPOSE/UNCERTAIN). Identify weaknesses, alternatives, and risks Claude missed."
- Key Files: relevant codebase files if applicable

```
result = mcp__codex__codex(prompt=<handoff>, sandbox="read-only", cwd=<cwd>)
```

### 3. Parse Codex response (Protocol 3)

Extract: STANCE, key arguments, counter-proposals

### 4. Iterate (max 3 rounds default)

If Codex OPPOSES or is UNCERTAIN:
1. Claude considers Codex's critique
2. Claude either:
   - **Revises** position (incorporating valid points)
   - **Rebuts** (with new evidence or reasoning)
3. Send via `codex-reply(threadId, <claude's revision/rebuttal>)`
4. Parse new response → check STANCE

If Codex SUPPORTS: proceed to summary.

### 5. Present debate summary

```
## Debate Summary: <topic>

### Final Position
<the converged or best position>

### Agreements
- Point 1 (both agree)
- Point 2

### Disagreements (if any)
- Point: Claude says X, Codex says Y

### Rounds: N | Final Stance: SUPPORT/OPPOSE/UNCERTAIN
```

### 6. State

Track in `.symphony/active.yaml` with `command: debate`
Max rounds configurable: default 3, user can say "keep going" to extend.
