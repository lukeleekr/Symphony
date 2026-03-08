---
name: codex-session
description: "Direct Codex session inside Claude Code — multi-turn pass-through"
---

# /symphony:codex — Direct Codex Pass-Through

> **allowed-tools**: `mcp__codex__codex`, `mcp__codex__codex-reply`, `Read`, `Bash`, `Grep`, `Glob`

## Purpose

Zero-orchestration direct Codex access. Claude = transparent shell. User writes their own prompt, Claude forwards it, keeps `threadId` alive for follow-ups.

**No handoff protocol** — user writes their own prompt. This is the "raw Codex" mode.

## Flow

### 1. Determine sandbox mode

- Default: `sandbox="read-only"`
- If user says "with write access" or "write mode": `sandbox="workspace-write"`

### 2. Send to Codex

```
result = mcp__codex__codex(
  prompt=<user's prompt from $ARGUMENTS>,
  sandbox=<determined above>,
  cwd=<current working directory>
)
```

### 3. Display response

Show Codex's full response to user. Extract and store `threadId`.

### 4. State tracking

Create `.symphony/active.yaml`:
```yaml
session_id: sym-YYYYMMDD-NNN
command: codex
task: "<first line of user prompt>"
thread_id: "<threadId from result>"
leader: codex
phase: active
started_at_utc: "<now UTC>"
rounds: 1
```

### 5. Follow-up loop

After showing response, ask: **"Continue with Codex, or done?"**

If user provides follow-up:
```
result = mcp__codex__codex-reply(
  threadId=<stored threadId>,
  prompt=<user's follow-up>
)
```
Increment `rounds` in state. Display response. Repeat.

If user says "done" or changes topic:
- Save session to `.symphony/history/`
- Report: total rounds, session duration

## Key Rules

- NEVER add handoff structure — user owns the prompt
- ALWAYS keep threadId alive until user says done
- Display Codex response VERBATIM — don't summarize or filter
- If Codex asks a question, relay it to user, then relay answer back via `codex-reply`
