---
name: reviewing
description: "Send code to Codex for multi-turn review"
---

# /symphony:review — Multi-Turn Code Review

> **allowed-tools**: `mcp__codex__codex`, `mcp__codex__codex-reply`, `Read`, `Edit`, `Write`, `Bash`, `Grep`, `Glob`

## Purpose

Send code to Codex for thorough multi-turn review. Codex reviews by default (Claude audits with `--lead codex` for rare cases where Codex wrote the code).

## Argument Parsing

Parse `$ARGUMENTS`:
- File path or glob → review those files
- `--diff` or `HEAD~N..HEAD` → review git diff
- `--security` → focus on OWASP top 10, auth, secrets
- `--perf` → focus on performance, N+1 queries, memory
- `--quick` → abbreviated review (top issues only)
- `--lead codex` → Claude reviews instead of Codex (rare)
- No args → review staged/unstaged changes (`git diff`)

## Flow

### 1. Gather context

- Read target files (or run `git diff` for diff mode)
- Read relevant CLAUDE.md, test files, related modules
- Identify project structure, patterns, constraints

### 2. Build handoff (Protocol 1)

- Purpose: "Code review for quality, correctness, and maintainability"
- What Was Done: summary of changes being reviewed
- What To Check: based on preset flags or general review checklist:
  - Correctness (logic errors, edge cases)
  - Security (injection, auth, secrets)
  - Performance (N+1, unnecessary allocations)
  - Maintainability (naming, complexity, DRY)
  - Test coverage (missing tests, weak assertions)
- Key Files: the files being reviewed with line ranges
- Constraints: project patterns from CLAUDE.md

### 3. Send to Codex

```
result = mcp__codex__codex(prompt=<handoff>, sandbox="read-only", cwd=<cwd>)
```

### 4. Parse response (Protocol 3)

Extract: VERDICT, SCORE, FINDINGS (categorized by severity)

### 5. Present to user

Format findings:
```
## Review Results — VERDICT (SCORE/10)

### CRITICAL (N)
- [CRITICAL] Description — file:line

### HIGH (N)
- [HIGH] Description — file:line

### MEDIUM (N)
...

### Summary
Codex recommends: <ACTION>
```

### 6. Fix loop (optional)

If user says "fix" or "fix these":
1. Claude fixes CRITICAL and HIGH findings
2. Send updated diff to Codex via `codex-reply(threadId, "Re-review after fixes: <diff summary>")`
3. Parse new response → repeat until APPROVED

### 7. State

Track in `.symphony/active.yaml` with `command: review`, phases: `review` → `fix` → `done`
