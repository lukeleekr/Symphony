---
name: fixing
description: "Review → fix → re-review until approved"
---

# /symphony:fix — Review-Fix-Recheck Loop

> **allowed-tools**: `mcp__codex__codex`, `mcp__codex__codex-reply`, `Read`, `Write`, `Edit`, `Bash`, `Grep`, `Glob`

## Purpose

Tight loop: Codex reviews code → leader fixes → Codex re-reviews on same thread → repeat until APPROVED. No planning phase — starts directly with review.

## Argument Parsing

Parse `$ARGUMENTS`:
- File path or glob → target those files
- `--lead codex` → Codex fixes, Claude re-reviews
- No args → target staged/unstaged changes

## Flow

### 1. Gather context

Read target files, related tests, project patterns from CLAUDE.md.

### 2. Initial review (Protocol 1)

Build handoff:
- Purpose: "Fix loop — review code, identify issues for iterative fixing"
- What To Check: "Identify ALL issues by severity. Be thorough — this will loop until you approve."

```
result = mcp__codex__codex(prompt=<handoff>, sandbox="read-only", cwd=<cwd>)
```

### 3. Parse findings (Protocol 3)

Extract VERDICT, FINDINGS. Categorize by severity.

### 4. Fix loop (max 5 rounds)

For each round:

**If Claude fixes (default):**
1. Fix CRITICAL findings first, then HIGH
2. Show user what was fixed
3. Build abbreviated handoff with changes
4. `codex-reply(threadId, "Re-review after fixes: <changes>")`
5. Parse new response

**If Codex fixes (`--lead codex`):**
1. `codex-reply(threadId, "Fix the CRITICAL and HIGH findings you identified", sandbox="workspace-write")`
2. Parse response — Codex reports what it fixed
3. Claude reviews the fixes (read changed files, run tests)
4. If more issues: `codex-reply(threadId, "Additional issues found: <list>")`

### 5. Termination

- APPROVED → report summary, save to history
- Max rounds (5) reached → report remaining findings, ask user how to proceed
- User says "stop" → save progress to history

### 6. State

Track in `.symphony/active.yaml` with `command: fix`, phases: `review` → `fix` → `done`
Track `findings_open` and `findings_fixed` counts.
