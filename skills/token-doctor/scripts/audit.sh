#!/usr/bin/env bash
# token-doctor audit
# Inventories Claude Code context sources and estimates token cost.
# Token estimates are rough: ~4 characters per token. For exact numbers, run /context inside Claude Code.
#
# Usage:
#   bash audit.sh                       # audits $HOME/.claude and $PWD
#   bash audit.sh /path/to/claude/home  # audits a specific claude home
#   bash audit.sh ~/.claude /path/proj  # also audits a specific project dir

set -u

CLAUDE_HOME="${1:-$HOME/.claude}"
PROJECT_DIR="${2:-$PWD}"

chars_to_tokens() { echo $(( ${1:-0} / 4 )); }

# Portable char count that handles missing files gracefully.
count_chars() {
  local f="$1"
  if [[ -f "$f" ]]; then
    wc -c < "$f" 2>/dev/null | tr -d ' \n' || echo 0
  else
    echo 0
  fi
}

count_lines() {
  local f="$1"
  if [[ -f "$f" ]]; then
    wc -l < "$f" 2>/dev/null | tr -d ' \n' || echo 0
  else
    echo 0
  fi
}

report_file() {
  local label="$1"
  local path="$2"
  if [[ -f "$path" ]]; then
    local chars lines tokens
    chars=$(count_chars "$path")
    lines=$(count_lines "$path")
    tokens=$(chars_to_tokens "$chars")
    printf "  %-32s %s (%s lines, ~%s tokens)\n" "$label:" "$path" "$lines" "$tokens"
  else
    printf "  %-32s (not found: %s)\n" "$label:" "$path"
  fi
}

hr() { printf '\n%s\n' "=== $1 ==="; }

printf 'Token Doctor audit\n'
printf 'Claude home: %s\n' "$CLAUDE_HOME"
printf 'Project dir: %s\n' "$PROJECT_DIR"

# ---------- Memory ----------
hr "Memory files (prepended every turn)"
report_file "User memory" "$CLAUDE_HOME/CLAUDE.md"
report_file "Project memory" "$PROJECT_DIR/CLAUDE.md"
report_file "Project local memory" "$PROJECT_DIR/CLAUDE.local.md"

# ---------- Settings ----------
hr "Settings files"
report_file "User settings" "$CLAUDE_HOME/settings.json"
report_file "Project settings" "$PROJECT_DIR/.claude/settings.json"
report_file "Project MCP config" "$PROJECT_DIR/.mcp.json"

# ---------- MCP servers ----------
hr "Configured MCP servers"
list_mcp_servers() {
  local file="$1"
  [[ -f "$file" ]] || return
  printf '  From %s:\n' "$file"
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$file" <<'PY'
import json, sys
try:
    with open(sys.argv[1]) as f:
        d = json.load(f)
    servers = d.get("mcpServers") or {}
    if not servers:
        print("    (none configured)")
    for name, cfg in servers.items():
        # Most configs only have command/args/env — the actual tool count
        # comes from the server at runtime, not the config file.
        print(f"    - {name}")
except Exception as e:
    print(f"    (could not parse: {e})")
PY
  elif command -v jq >/dev/null 2>&1; then
    jq -r '(.mcpServers // {}) | keys[]? | "    - " + .' "$file" 2>/dev/null
  else
    printf '    (install python3 or jq to parse MCP server list)\n'
  fi
}
list_mcp_servers "$CLAUDE_HOME/settings.json"
list_mcp_servers "$PROJECT_DIR/.claude/settings.json"
list_mcp_servers "$PROJECT_DIR/.mcp.json"

cat <<'NOTE'

  Note: server names come from the config, but each server's tool count
        only shows up at runtime. Run "claude mcp list" if available, or
        ask the user to start each server and check how many tools it has.
        An MCP with 50+ tools is the single most common cause of bloat.
NOTE

# ---------- Plugins ----------
hr "Installed plugins"
if [[ -d "$CLAUDE_HOME/plugins" ]]; then
  found=0
  while IFS= read -r p; do
    [[ -z "$p" ]] && continue
    found=1
    plugin_dir=$(dirname "$p")
    plugin_name=$(basename "$plugin_dir")
    printf '  - %s  (%s)\n' "$plugin_name" "$plugin_dir"
  done < <(find "$CLAUDE_HOME/plugins" -maxdepth 4 -name plugin.json 2>/dev/null)
  if [[ "$found" -eq 0 ]]; then
    printf '  (no plugin.json files found under %s/plugins)\n' "$CLAUDE_HOME"
  fi
else
  printf '  (no plugins directory)\n'
fi

# ---------- Skills ----------
hr "Installed skills (each registration sits in context)"
total_skill_chars=0
skill_count=0
if [[ -d "$CLAUDE_HOME/plugins" ]] || [[ -d "$CLAUDE_HOME/skills" ]]; then
  while IFS= read -r s; do
    [[ -z "$s" ]] && continue
    skill_count=$((skill_count + 1))
    chars=$(count_chars "$s")
    total_skill_chars=$((total_skill_chars + chars))
    tokens=$(chars_to_tokens "$chars")
    skill_dir=$(basename "$(dirname "$s")")
    printf '  %-40s ~%s tokens (body)\n' "$skill_dir" "$tokens"
  done < <( { [[ -d "$CLAUDE_HOME/plugins" ]] && find "$CLAUDE_HOME/plugins" -name SKILL.md 2>/dev/null; [[ -d "$CLAUDE_HOME/skills" ]] && find "$CLAUDE_HOME/skills" -name SKILL.md 2>/dev/null; } )
fi
total_skill_tokens=$(chars_to_tokens "$total_skill_chars")
printf '\n  Skills found: %s  total body tokens if all loaded: ~%s\n' "$skill_count" "$total_skill_tokens"
printf '  (Note: only skill names + descriptions are ALWAYS in context. Bodies load on trigger.)\n'

# ---------- Hooks ----------
hr "Hooks (run per event, can inject context)"
list_hooks() {
  local file="$1"
  [[ -f "$file" ]] || return
  if command -v jq >/dev/null 2>&1; then
    jq -r '(.hooks // {}) | to_entries[]? | "  - \(.key): \(.value | length) hook(s)"' "$file" 2>/dev/null
  elif command -v python3 >/dev/null 2>&1; then
    python3 - "$file" <<'PY'
import json, sys
try:
    with open(sys.argv[1]) as f:
        d = json.load(f)
    for k, v in (d.get("hooks") or {}).items():
        n = len(v) if isinstance(v, list) else "?"
        print(f"  - {k}: {n} hook(s)")
except Exception:
    pass
PY
  else
    grep -E '"(PreToolUse|PostToolUse|UserPromptSubmit|Notification|Stop|SubagentStop|SessionStart)"' "$file" 2>/dev/null | sed 's/^[[:space:]]*/  /' || true
  fi
}
list_hooks "$CLAUDE_HOME/settings.json"

# ---------- Totals ----------
hr "Rough totals"
user_mem_t=$(chars_to_tokens "$(count_chars "$CLAUDE_HOME/CLAUDE.md")")
proj_mem_t=$(chars_to_tokens "$(count_chars "$PROJECT_DIR/CLAUDE.md")")
proj_local_t=$(chars_to_tokens "$(count_chars "$PROJECT_DIR/CLAUDE.local.md")")
memory_total=$((user_mem_t + proj_mem_t + proj_local_t))
printf '  Memory files prepended every turn: ~%s tokens\n' "$memory_total"
printf '  Installed skill bodies (lazy-loaded): ~%s tokens if every skill triggered\n' "$total_skill_tokens"
printf '\nReminder: run /context inside Claude Code for the authoritative breakdown.\n'
printf '          run /cost inside Claude Code for session spend.\n'
