---
name: cleaning-up
description: "Claude + Codex independently scan, then merge findings"
---

# /symphony:cleanup — Bidirectional Scan

> **allowed-tools**: `mcp__codex__codex`, `mcp__codex__codex-reply`, `Read`, `Edit`, `Write`, `Bash`, `Grep`, `Glob`

## Purpose

Claude and Codex independently scan codebase for issues, then merge findings. Two independent perspectives catch more than one.

## Argument Parsing

Parse `$ARGUMENTS` for scope:
- `security` → OWASP top 10, secrets, auth issues
- `deadcode` → unused functions, imports, variables
- `duplicates` → copy-paste code, DRY violations
- `deps` → outdated/vulnerable dependencies
- `anti-patterns` → code smells, complexity, naming
- `all` → all of the above (default if no scope given)
- Also accept a directory path to scope the scan

## Flow

### Phase 1: Claude scans independently

1. Use Grep/Glob/Read to scan codebase for the selected scope
2. Build Claude's findings list:
   ```
   - [SEVERITY] description — file:line
   ```

### Phase 2: Codex scans independently

3. Build handoff (Protocol 1):
   - Purpose: "Independent codebase scan for: <scope>"
   - What To Check: scope-specific checklist
   - Constraints: "This is an independent scan. Do your own analysis — don't just agree with previous findings."

4. `mcp__codex__codex(prompt=<handoff>, sandbox="read-only", cwd=<cwd>)`
5. Parse Codex's findings list

### Phase 3: Merge findings

6. Cross-reference Claude's and Codex's findings:
   - **Both agree** → HIGH confidence finding
   - **Only one found** → MEDIUM confidence (note which model)
   - **Contradicting** → flag for rebuttal

7. Present merged report:
   ```
   ## Cleanup Report — <scope>

   ### HIGH Confidence (both agree)
   - [SEV] description — file:line

   ### MEDIUM Confidence (single model)
   - [SEV] description — file:line (found by: Claude|Codex)

   ### Disputed
   - description — Claude says X, Codex says Y
   ```

### Phase 4: Rebuttal (optional)

8. If disputed findings exist and user wants resolution:
   - `codex-reply(threadId, "Claude disagrees on: <disputed items>. Claude's reasoning: <...>. Reconsider.")`
   - Parse response → update confidence

### Phase 5: Fix (optional)

9. If user says "fix":
   - Claude fixes HIGH confidence findings
   - Re-scan via `codex-reply` to verify

### State

Track in `.symphony/active.yaml` with `command: cleanup`
