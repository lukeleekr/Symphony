# Symphony

Multi-turn Claude-Codex orchestration plugin for [Claude Code](https://docs.anthropic.com/en/docs/claude-code).

Symphony eliminates manual copy-paste between Claude Code and Codex App while preserving 100% quality parity. It automates the message-bus role using native Codex MCP tools (`mcp__codex__codex` + `mcp__codex__codex-reply`) for true multi-turn GPT sessions.

## Why Symphony?

The manual Claude-Codex workflow is high-quality but painful:

1. Claude brainstorms/plans → 2. Copy to Codex → 3. Codex revises → 4. Copy back to Claude → 5. Copy revision to Codex → 6. Codex audits → 7. Claude fixes → 8. Copy to Codex → repeat.

Symphony automates steps 2-8 while preserving the full multi-turn context that makes Codex effective.

## Commands

| Command | Description | Default Leader |
|---------|-------------|----------------|
| `/symphony:codex` | Direct Codex session — multi-turn pass-through | Codex |
| `/symphony:plan` | Design with Claude, validate with Codex | Claude designs, Codex validates |
| `/symphony:build` | Full pipeline: plan → implement → audit → fix loop | Claude implements, Codex audits |
| `/symphony:review` | Send code to Codex for multi-turn review | Codex reviews |
| `/symphony:debate` | Multi-round Claude vs Codex structured debate | Both equal |
| `/symphony:fix` | Review → fix → re-review until approved | Claude fixes, Codex re-reviews |
| `/symphony:cleanup` | Claude + Codex independently scan, then merge findings | Both scan independently |

All commands except `codex` and `debate` support `--lead codex` to flip implementor/auditor roles.

## Architecture

```
┌────────────────────────────────────────────────┐
│                  Claude Code                   │
│                                                │
│  User ──► /symphony:<cmd> ──► Claude Skills    │
│                                   │            │
│                           (user confirms)      │
│                                   │            │
│                                   ▼            │
│         ┌──────── Symphony Core ────────────┐  │
│         │  Handoff Protocol                 │  │
│         │  ┌─────────────────────────────┐  │  │
│         │  │ • Purpose (why)             │  │  │
│         │  │ • Context (project, branch) │  │  │
│         │  │ • What was done             │  │  │
│         │  │ • What to check             │  │  │
│         │  │ • Key files                 │  │  │
│         │  │ • Constraints               │  │  │
│         │  └─────────────────────────────┘  │  │
│         │              │                    │  │
│         │              ▼                    │  │
│         │  mcp__codex__codex(prompt)        │  │
│         │         │                         │  │
│         │         ▼ threadId                │  │
│         │  mcp__codex__codex-reply(...)     │  │
│         │    (loop until converged)         │  │
│         │         │                         │  │
│         │         ▼                         │  │
│         │  Output Parsing                   │  │
│         │  (verdict, score, findings)       │  │
│         └───────────────────────────────────┘  │
│                                                │
│  State: .symphony/active.yaml                  │
└────────────────────────────────────────────────┘
```

## Key Design Decisions

- **Claude-first**: Design and brainstorming always happen with Claude + existing skills. Codex enters only after user confirmation.
- **Structured handoff**: Every message to Codex follows a 6-field protocol (Purpose, Context, What Was Done, What To Check, Key Files, Constraints).
- **Single threadId per session**: All Codex interactions share one thread. Codex accumulates full context across rounds — no single-turn degradation.
- **Natural language parsing**: Claude infers verdicts, scores, and findings from Codex's natural language. More robust than strict JSON parsing.
- **YAML state**: Session state in `.symphony/active.yaml`. Human-readable, git-ignorable. History preserved in `.symphony/history/`.

## Prerequisites

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) CLI
- [Codex CLI](https://github.com/openai/codex) with MCP server running (`codex mcp-server`)
- Codex MCP tools available: `mcp__codex__codex`, `mcp__codex__codex-reply`

## Installation

### 1. Create the plugin directory

```bash
mkdir -p ~/.claude/plugins/cache/local/symphony/1.0.0/.claude-plugin
mkdir -p ~/.claude/plugins/cache/local/symphony/1.0.0/{commands,skills}
```

### 2. Create plugin manifest

Create `~/.claude/plugins/cache/local/symphony/1.0.0/.claude-plugin/plugin.json`:

```json
{
  "name": "symphony",
  "description": "Multi-turn Claude-Codex orchestration — plan, review, debate, build, fix, cleanup with true multi-turn GPT sessions via codex-reply",
  "version": "1.0.0",
  "author": {
    "name": "Your Name"
  }
}
```

### 3. Add command stubs

For each command (`codex`, `plan`, `build`, `review`, `debate`, `fix`, `cleanup`), create a file in `commands/`. Example `commands/build.md`:

```markdown
---
description: "Full pipeline: plan → implement → audit → fix loop"
argument-hint: "<task> [--lead codex]"
---

Invoke the symphony:build skill and follow it exactly as presented to you
```

### 4. Add skill definitions

Create `skills/<command>/SKILL.md` for each command and `skills/protocols/SKILL.md` for shared protocols. See the `skills/` directory in this repo for complete definitions.

### 5. Register in local marketplace

Create `~/.claude/local-plugins/.claude-plugin/marketplace.json`:

```json
{
  "name": "local-plugins",
  "owner": { "name": "Your Name" },
  "metadata": {
    "description": "Local plugins",
    "pluginRoot": "./plugins"
  },
  "plugins": [
    {
      "name": "symphony",
      "source": "./plugins/symphony",
      "description": "Multi-turn Claude-Codex orchestration",
      "version": "1.0.0"
    }
  ]
}
```

Then symlink and install:

```bash
# Symlink plugin into marketplace
ln -sf ~/.claude/plugins/cache/local/symphony/1.0.0 ~/.claude/local-plugins/plugins/symphony

# Register marketplace and install
claude plugin marketplace add ~/.claude/local-plugins
claude plugin install symphony@local-plugins
```

### 6. Enable autocomplete (workaround)

Due to a [known Claude Code bug](https://github.com/anthropics/claude-code/issues/18949), plugin commands don't appear in autocomplete. Workaround:

```bash
cd ~/.claude/commands
for cmd in codex plan build review debate fix cleanup; do
  ln -sf ~/.claude/plugins/cache/local/symphony/1.0.0/commands/${cmd}.md "symphony:${cmd}.md"
done
```

Restart Claude Code. Type `/symphony:` and all 7 subcommands appear with descriptions.

## Shared Protocols

Symphony uses 4 shared protocols across all commands:

| Protocol | Purpose |
|----------|---------|
| **Handoff** | Structured 6-field message format for every Codex interaction |
| **Multi-Turn** | `threadId` management — start, continue, end sessions |
| **Output Parsing** | Extract VERDICT, SCORE, FINDINGS, STANCE from Codex responses |
| **State Management** | `.symphony/active.yaml` tracking, history archival |

## How It Compares

| Dimension | Manual Copy-Paste | CodeMoot | Symphony |
|-----------|------------------|----------|----------|
| GPT session | Multi-turn (manual) | Single-turn (`codex exec`) | Multi-turn (`codex-reply`) |
| Context across rounds | Preserved (manual) | Lost (new exec each time) | Preserved (same threadId) |
| Effort | High (8+ copy-paste steps) | Low (CLI command) | Zero (automated) |
| Quality | Highest | Degraded (single-turn) | Highest (multi-turn parity) |
| Role flexibility | Manual | Claude always leads | Configurable per-command |
| Dependencies | None | npm, SQLite | Zero (MCP server already running) |

## Plugin Structure

```
~/.claude/plugins/cache/local/symphony/1.0.0/
├── .claude-plugin/
│   └── plugin.json
├── commands/
│   ├── codex.md        → /symphony:codex
│   ├── plan.md         → /symphony:plan
│   ├── build.md        → /symphony:build
│   ├── review.md       → /symphony:review
│   ├── debate.md       → /symphony:debate
│   ├── fix.md          → /symphony:fix
│   └── cleanup.md      → /symphony:cleanup
└── skills/
    ├── protocols/
    │   └── SKILL.md     ← shared handoff, multi-turn, output parsing
    ├── codex/SKILL.md
    ├── plan/SKILL.md
    ├── build/SKILL.md
    ├── review/SKILL.md
    ├── debate/SKILL.md
    ├── fix/SKILL.md
    └── cleanup/SKILL.md
```

## License

MIT
