---
name: building
description: "Full pipeline: plan → implement → audit → fix loop"
---

# /symphony:build — Full Pipeline

> **allowed-tools**: `mcp__codex__codex`, `mcp__codex__codex-reply`, `Read`, `Write`, `Edit`, `Bash`, `Grep`, `Glob`, `Skill`, `Agent`

## Purpose

End-to-end pipeline: design → validate → implement → audit → fix until approved. The most comprehensive Symphony command. Composes brainstorming, TDD, and review into a single guided workflow.

## Argument Parsing

Parse `$ARGUMENTS`:
- `--lead codex` → Codex implements, Claude audits
- Everything else → task description (Claude implements by default)

## Pipeline

### Phase 1: Plan

1. Invoke `/symphony:plan` protocol (Mode A):
   - Claude designs with user (brainstorming skill)
   - User approves design

### Phase 2: Validate with Codex

2. Build handoff (Protocol 1) with the approved design
3. `mcp__codex__codex(handoff, sandbox="read-only")` → Codex reviews plan
4. Parse response → if NEEDS_REVISION, iterate via `codex-reply`
5. **Gate 1**: Present validated plan to user. User must approve to continue.

### Phase 3: Implement

**If Claude leads (default):**

6. Claude implements using TDD (invoke `superpowers:test-driven-development` skill)
7. After implementation, gather diff: `git diff --stat`, read changed files
8. Build handoff for audit:
   - Purpose: same as Phase 1
   - What Was Done: implementation details, files changed
   - What To Check: "Audit this implementation against the approved plan. Check: correctness, edge cases, test coverage, security, performance"

**If Codex leads (`--lead codex`):**

6. Send implementation request via `codex-reply(threadId, <implement handoff>)` with `sandbox="workspace-write"`
7. Parse Codex's response — it will report what it built
8. Claude reviews the changes (read files, run tests)

### Phase 4: Audit

9. Non-leader reviews:
   - Claude leads → `codex-reply(threadId, <audit handoff>)` (Codex audits)
   - Codex leads → Claude reviews directly (read code, run tests, check against plan)
10. Parse audit response → VERDICT, SCORE, FINDINGS

### Phase 5: Fix Loop

11. If NEEDS_REVISION:
    - Leader fixes CRITICAL and HIGH findings
    - Send fix summary via `codex-reply(threadId, "Re-review after fixes: <changes>")`
    - Repeat until APPROVED or max 5 rounds
12. If BLOCKED: halt, present blocker to user

### Phase 6: Report

13. **Gate 2**: Present build report:
    ```
    ## Build Report

    Task: <description>
    Leader: <claude|codex>
    Rounds: N
    Final Verdict: APPROVED (SCORE/10)

    ### Files Changed
    - file1.py (added)
    - file2.py (modified)

    ### Findings Resolved
    - [CRITICAL] ... → FIXED
    - [HIGH] ... → FIXED

    ### Test Results
    <test output summary>
    ```

14. **Gate 3**: User confirms commit.

## State

Track in `.symphony/active.yaml` with phases: `plan` → `validate` → `implement` → `audit` → `fix` → `done`
