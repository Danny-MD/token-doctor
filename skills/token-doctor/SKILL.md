---
name: token-doctor
description: Diagnose and treat Claude Code context bloat. Use this skill whenever the user complains about hitting usage limits early, burning through tokens, auto-compact firing after short conversations, Claude Code sessions feeling "heavy" or expensive, or asks to audit their ~/.claude setup. Trigger on phrases like "why am I hitting limits", "my Claude Code is burning tokens", "short chats eat my quota", "audit my context", "/token-doctor", "diagnose my setup", or any general frustration with Claude Code cost or context usage. Don't wait for the user to name this skill explicitly — if they're complaining about token usage in Claude Code, run the diagnostic.
---

# Token Doctor

The patient is the user's Claude Code setup. The complaint is almost always the same: "I hit the limit after a short chat." Your job is a systematic visit — intake, examination, diagnosis, prescription — that ends with the user knowing the one or two specific things to change.

Keep the doctor metaphor light. The user is frustrated; they don't want a lecture, they want the answer.

## The mental model

Every turn in Claude Code, the context window carries several layers:

1. **System prompt** — fixed, not your problem.
2. **Tool definitions** — every tool from every connected MCP server, plus built-ins. Each tool's JSON schema costs a few hundred tokens. An MCP that registers 80 tools can add tens of thousands of tokens *to every message the user sends*.
3. **Memory files** — `~/.claude/CLAUDE.md` plus any project `CLAUDE.md` are prepended on every turn, every session.
4. **Skill descriptions** — the name + description of every installed skill sits in context so the model can decide whether to load the body. Descriptions are small individually but add up across dozens of skills.
5. **Skill bodies, when triggered** — the full SKILL.md loads only when the skill matches.
6. **Conversation history** — grows every turn. A single early read of a large file stays in history for the rest of the session.
7. **Auto-compact headroom** — Claude Code reserves space near the top of the window for the summary compaction produces.

Root causes for "hit the limit after a short chat", roughly in order of how often they're the real culprit:

- An MCP with a huge tool surface that the user rarely or never uses.
- A bloated `CLAUDE.md`.
- One big file read early in the session that's still in history.
- Skill/plugin sprawl — many installed, most irrelevant.
- Using Opus/Sonnet for work Haiku would handle fine (not a token problem, a cost problem — flag it if relevant).

Output verbosity (what caveman-style skills target) is usually *not* the main problem. Say so if the user asks.

## The visit

### Step 1: Intake — get the real numbers

The gold standard is asking the user to run `/context` in their Claude Code session and paste the output. It tells you exactly where tokens are going *right now*, in this session. Ask for it first.

If they can't or won't, fall back to a filesystem audit. Run the bundled script:

```bash
bash "$CLAUDE_PLUGIN_ROOT/skills/token-doctor/scripts/audit.sh"
```

(If `$CLAUDE_PLUGIN_ROOT` isn't set in the shell, use the absolute path to this skill's folder.) The script walks `~/.claude` and the current project, listing memory files, settings, configured MCP servers, installed plugins and skills, and estimates token counts. Token counts from the script are approximate — ~4 characters per token. Tell the user they're rough.

Optionally also ask the user to run `/cost` in their session so you can cite real dollars rather than abstract tokens.

### Step 2: Examination — go through the sources

Work the checklist. Don't skip a source just because it seems harmless; the surprise usually comes from the one you'd have skipped.

**Memory files**
- `~/.claude/CLAUDE.md` (user memory, loaded every turn, every session, forever)
- `./CLAUDE.md` and `./CLAUDE.local.md` in the project
- Anything `@`-imported from those files

Record line count and rough token count. A `CLAUDE.md` past ~300 lines is worth scrutinizing.

**MCP servers and their tool count**
- `~/.claude/settings.json` (user) and `./.mcp.json` (project) list configured servers.
- Each server's full tool list is in context on every turn. A server that exposes 50+ tools is the single most likely culprit for runaway token use.
- If the user can run `claude mcp list` or paste the servers block, use that. Otherwise read the files directly.

**Installed plugins and skills**
- `~/.claude/plugins/` — one directory per plugin.
- Each plugin contributes skills (folders with SKILL.md) whose descriptions stay in context so the model can decide when to load them.
- Plugins that ship 20+ skills are common bloat.

**Hooks**
- `~/.claude/settings.json` → `hooks` key. Hooks run on specific events and can inject content into every turn. Check what's there.

**Conversation history**
- Only visible from `/context` output. If the "Messages" section is large relative to the rest, the user needs `/compact` or `/clear` discipline, not a config change.

### Step 3: Diagnose — name the top 3 offenders

Rank by estimated tokens per turn, highest first. Be specific — numbers, names, file paths. Compare:

- Weak: "you have too many MCPs"
- Strong: "your `~/.claude/settings.json` has the `filesystem` MCP registering 62 tools, adding roughly 18K tokens to every message you send"

The user should finish reading the diagnosis and already know what to delete.

Common diagnoses to look for:

- **MCP tool explosion.** Count tools per server. Flag any above ~30.
- **CLAUDE.md obesity.** Flag any memory file past ~300 lines. Often has stale project notes, duplicated instructions, or copy-pasted docs that should be referenced, not inlined.
- **Skill sprawl.** Dozens of installed skills, most never used. Descriptions alone can reach a few thousand tokens.
- **File-read hangover.** Hard to see without `/context`, but if the user mentions reading a big file (SDK, lockfile, generated code) earlier in the session, that's probably still in history.
- **Model mismatch.** If the user is on Opus or Sonnet for routine work, their token count may be fine but cost is the real issue. Call it out.
- **Late auto-compact.** By the time auto-compact fires, the user has already paid for the bloat across many turns. If they aren't using `/compact` or `/clear` proactively, that's where to push.

### Step 4: Prescribe — an ordered list

Give at most 3–5 items, ordered so the first one alone moves the needle. For each:

- **What to do** — one sentence.
- **Exact command or edit** — paste the file path and the specific change.
- **Estimated savings** — tokens per turn, or "eliminates X from every message this session".

Example shape:

> **1. Disable the unused `filesystem` MCP (~18K tokens/turn)**
> Edit `~/.claude/settings.json`, remove the `"filesystem"` entry under `"mcpServers"`. If you use it occasionally, keep it but narrow `allowedDirectories` so the blast radius is smaller (tool count stays the same, but at least it's safer).
> Savings: ~18,000 tokens on every message you send until you restart.

After the list, give the user the built-in hygiene commands they can run *right now* in the same Claude Code session:

- `/context` — see the current breakdown.
- `/compact` — summarize history without clearing it.
- `/clear` — hard reset between unrelated tasks.
- `/cost` — see session spend.
- `/model haiku` — downshift the model for the current session if the work is routine.

### Step 5: Follow-up

Close with one line about what to watch next session — e.g., "run `/context` again after your next long chat; if messages crosses ~80K before you've done much, `/compact` earlier." No long postamble.

## When to stop early

If the top offender alone would solve the user's problem — one 30K-token MCP they didn't know was enabled, a 900-line `CLAUDE.md` full of stale notes — call it out first and stop. They don't need a full audit; they need the one sentence that tells them what to delete.
