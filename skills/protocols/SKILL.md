---
name: protocols
description: "Shared protocols for Symphony: handoff, multi-turn management, output parsing, state management"
---

# Symphony Shared Protocols

These protocols are referenced by all Symphony command skills. When a command skill says "follow Protocol N", execute the corresponding section below.

## Protocol 1: Handoff Protocol

Every message sent to Codex via `mcp__codex__codex` or `mcp__codex__codex-reply` MUST include this structure. Gather each field before sending.

```markdown
## Purpose (Why)
{Why this project/feature exists. Business context, user problem,
 architectural motivation. Pull from conversation history, CLAUDE.md,
 or ask user if unclear.}

## Context
- Project: {from CLAUDE.md or cwd}
- Working directory: {cwd}
- Current branch: {run `git branch --show-current`}
- Recent changes: {run `git diff --stat` if relevant}

## What Was Done
{specific changes, decisions, code written — be concrete}

## What To Check
{specific asks — NOT "review everything". List 3-7 focused items.}

## Key Files
{files that matter, with line ranges where helpful}

## Constraints
{what NOT to change, architectural boundaries, patterns to preserve}
```

**Rules:**
- Never send a bare prompt to Codex. Always wrap in handoff structure.
- Exception: `/symphony:codex` (pass-through) skips handoff — user writes own prompt.
- Purpose field is MANDATORY — Codex needs business context to make good decisions.

## Protocol 2: Multi-Turn Management

### Starting a session

```
result = mcp__codex__codex(prompt=<handoff>, sandbox="read-only", cwd=<cwd>)
```

Extract `threadId` from result. Store in `.symphony/active.yaml`.

### Continuing on same thread

```
result = mcp__codex__codex-reply(threadId=<threadId>, prompt=<follow-up>)
```

Follow-up prompts also use handoff structure (abbreviated — skip unchanged Context/Constraints).

### Sandbox modes

| Mode | When |
|------|------|
| `read-only` | Default. Reviews, debates, planning. |
| `workspace-write` | When Codex implements code (`--lead codex`). User must explicitly request. |

### Thread lifecycle

- One `threadId` per Symphony session.
- Store in `.symphony/active.yaml` immediately after creation.
- If thread expires or errors: start new thread with summary of prior exchanges as context.
- NEVER discard `threadId` without saving conversation summary to history.

## Protocol 3: Output Parsing

After each Codex response, Claude reads the natural language and extracts:

| Field | Values | When |
|-------|--------|------|
| **VERDICT** | `APPROVED` / `NEEDS_REVISION` / `BLOCKED` | review, fix, build audit |
| **SCORE** | X/10 | review-type commands |
| **FINDINGS** | `[CRITICAL\|HIGH\|MEDIUM\|LOW]` + description | review, fix, cleanup |
| **STANCE** | `SUPPORT` / `OPPOSE` / `UNCERTAIN` | debate |
| **ACTION** | What to do next | all |

**Rules:**
- No strict JSON parsing. Claude infers from Codex's natural language.
- If verdict is ambiguous, default to `NEEDS_REVISION` (conservative).
- Present parsed output to user in structured format.
- CRITICAL findings block progress. HIGH findings require attention. MEDIUM/LOW are advisory.

## Protocol 4: State Management

### Directory

```
.symphony/                     <- in .gitignore
├── active.yaml                <- current session
└── history/
    └── YYYY-MM-DD-HH-MM-<slug>.yaml
```

### Starting a session

Create/overwrite `.symphony/active.yaml`:

```yaml
session_id: sym-YYYYMMDD-NNN
command: <command-name>
task: "<user's task description>"
thread_id: "<from mcp__codex__codex result>"
leader: claude          # or codex
phase: plan             # plan | validate | implement | audit | fix | done
started_at_utc: "<ISO 8601>"
rounds: 0
findings_open: 0
findings_fixed: 0
verdict: pending
```

### Updating during session

After each Codex exchange:
- Increment `rounds`
- Update `phase`, `verdict`, `findings_open`, `findings_fixed`

### Ending a session

1. Copy `active.yaml` to `history/YYYY-MM-DD-HH-MM-<slug>.yaml`
2. Add: `ended_at_utc`, `total_rounds`, `final_verdict`, `score`, `files_changed`, `summary`
3. Delete `active.yaml`

### Rules

- `.symphony/` MUST be in `.gitignore`
- One active session at a time
- Starting new session: warn user, close previous (save to history)
- `thread_id` is source of truth — never discard without saving summary

## Role Switching

Commands support `--lead codex` to flip implementor/auditor roles:

| Command | Default | `--lead codex` |
|---------|---------|----------------|
| codex | Codex always | N/A |
| plan | Claude designs, Codex validates | N/A |
| review | Codex reviews | Claude reviews (rare) |
| debate | Both equal | N/A |
| build | Claude implements, Codex audits | Codex implements, Claude audits |
| fix | Claude fixes, Codex re-reviews | Codex fixes, Claude re-reviews |
| cleanup | Both scan independently | N/A |

When `--lead codex` is active and Codex implements:
- Use `sandbox="workspace-write"` in MCP calls
- Claude becomes the auditor (reviews Codex's output)
