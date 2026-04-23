# token-doctor

A Claude Code skill that diagnoses *why* your context window is filling up so fast and tells you exactly what to change.

Most "I hit the limit after a short chat" complaints trace back to one of:

- An MCP with 50+ tools that you don't actually use (every tool's schema is in context every turn).
- A bloated `~/.claude/CLAUDE.md` full of stale notes.
- One big file you read early in the session that keeps getting dragged along.
- Skill/plugin sprawl — dozens installed, most irrelevant.
- Using Opus/Sonnet for work Haiku would handle.

Output verbosity is almost never the real cause. This skill focuses on the layers that actually dominate.

## What it does

When you complain about token use in Claude Code, the skill activates and runs a four-step visit:

1. **Intake** — asks you to run `/context` (gold standard) or runs a filesystem audit script as a fallback.
2. **Examination** — walks through memory files, `settings.json`, MCP servers, installed plugins, skills, and hooks.
3. **Diagnosis** — ranks the top 3 offenders by estimated tokens-per-turn, with specific numbers.
4. **Prescription** — an ordered list of fixes with exact edits and estimated savings.

## Install

**As a skill (drop-in):**

```bash
mkdir -p ~/.claude/skills
cp -r skills/token-doctor ~/.claude/skills/
```

**As a plugin (git-based):**

If you host this repo on GitHub:

```bash
claude plugin add <your-username>/token-doctor
```

Then restart Claude Code.

## Try it

In any Claude Code session, just say one of:

- "why am I hitting claude limits so fast"
- "audit my claude setup"
- "my claude code is burning tokens"
- "diagnose my context"

The skill's description is written to trigger on that kind of language without needing a slash command.

## The audit script standalone

You can also run the measurement script directly without Claude:

```bash
bash skills/token-doctor/scripts/audit.sh                 # audits ~/.claude and $PWD
bash skills/token-doctor/scripts/audit.sh ~/.claude       # custom claude home
bash skills/token-doctor/scripts/audit.sh ~/.claude /path/to/project
```

It needs `python3` or `jq` for the MCP server list (both are optional — if neither is present you'll still get memory/plugins/skills counts).

## Limits

- Token counts are approximate (`chars / 4`). `/context` inside Claude Code is authoritative.
- The filesystem audit can't see *conversation history* — the one thing only `/context` can show you. Always ask for `/context` output when you can.
- Tool counts per MCP only appear at runtime. The script lists servers; you'll need to run `claude mcp list` or inspect each server to get actual tool counts.

## License

MIT.
