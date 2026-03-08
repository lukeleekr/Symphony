---
name: planning
description: "Design with Claude, then validate with Codex"
---

# /symphony:plan — Design Then Validate

> **allowed-tools**: `mcp__codex__codex`, `mcp__codex__codex-reply`, `Read`, `Write`, `Edit`, `Bash`, `Grep`, `Glob`, `Skill`

## Purpose

Claude designs with the user first (using brainstorming/socrates skills), then sends to Codex for validation. Two modes based on user intent.

## Mode Detection

Parse `$ARGUMENTS`:
- Contains "validate", "check with codex", "send to codex" → **Mode B** (direct validation)
- Everything else → **Mode A** (design-first, default)

## Mode A: Design-First (default)

### Phase 1: Design with Claude

1. **Invoke brainstorming skill**: Use `Skill("superpowers:brainstorming", args=$ARGUMENTS)` to design collaboratively with user
2. Iterate with user until design is approved
3. User confirms design → proceed to Phase 2

### Phase 2: Codex Validation

4. **Build handoff prompt** following Protocol 1 (from symphony:protocols skill):
   - Purpose: why this feature/project exists
   - Context: project, branch, recent changes
   - What Was Done: the design that was just created
   - What To Check: "Review this design for: completeness, edge cases, architectural soundness, potential issues"
   - Key Files: design doc path + any referenced files
   - Constraints: existing architecture boundaries

5. **Send to Codex**:
   ```
   result = mcp__codex__codex(prompt=<handoff>, sandbox="read-only", cwd=<cwd>)
   ```

6. **Parse response** (Protocol 3): Extract VERDICT, FINDINGS

7. **If NEEDS_REVISION**:
   - Present Codex's feedback to user
   - Claude revises design based on feedback
   - Send revision via `codex-reply(threadId, <revised handoff>)`
   - Repeat until APPROVED or user overrides

8. **If APPROVED**:
   - Present final design
   - Save session to history
   - Offer: "Ready to implement? I can invoke /symphony:build"

## Mode B: Direct Validation

1. Read design from:
   - Conversation context (if design was just discussed)
   - File path (if user provides a path)
   - `$ARGUMENTS` content

2. Build handoff (Protocol 1) → send to Codex → parse → iterate if needed

Same flow as Phase 2 above, but skips the Claude design phase.

## State

Track in `.symphony/active.yaml` with `command: plan`, phases: `design` → `validate` → `done`
