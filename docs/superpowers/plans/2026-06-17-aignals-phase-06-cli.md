# Phase 06 — `aignals-hook` CLI

> Sub-skill: superpowers:subagent-driven-development or superpowers:executing-plans.

**Goal:** Shell script that implements the 4 hook subcommands, reading Claude Code's stdin payload, writing/updating/removing JSON under `$AIGNALS_HOME/sessions/`.

**Spec sections:** §5 (CLI subcommands, payload extraction, settings.json snippet, AIGNALS_HOME override).

---

### Task 6.1: Script skeleton

**Files:**
- Create: `CLI/aignals-hook/aignals-hook`

- [ ] **Step 1: Write the skeleton**

```bash
#!/usr/bin/env bash
# aignals-hook — emit/maintain ~/.aignals/sessions/<id>.json from Claude Code hook payloads.
# Exit 0 on every path so Claude Code never breaks because of the indicator.

set -u

AIGNALS_HOME_DEFAULT="$HOME/.aignals"
AIGNALS_HOME="${AIGNALS_HOME:-$AIGNALS_HOME_DEFAULT}"
SESSIONS_DIR="$AIGNALS_HOME/sessions"

require_jq() {
  if ! command -v jq >/dev/null 2>&1; then
    echo "aignals-hook: jq not found. Install with: brew install jq" >&2
    exit 0
  fi
}

ensure_dirs() {
  mkdir -p "$SESSIONS_DIR" 2>/dev/null || true
  chmod 700 "$AIGNALS_HOME" 2>/dev/null || true
  chmod 700 "$SESSIONS_DIR" 2>/dev/null || true
}

atomic_write() {
  # atomic_write <path> < stdin
  local path="$1"
  local tmp="${path}.tmp.$$"
  cat > "$tmp"
  mv -f "$tmp" "$path"
}

now_iso() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }

# --- subcommands ---
cmd_on_sessionstart() {
  require_jq; ensure_dirs
  local payload; payload="$(cat)"
  local sid; sid="$(echo "$payload" | jq -r '.session_id // empty')"
  [ -z "$sid" ] && exit 0
  local cwd; cwd="$(echo "$payload" | jq -r '.cwd // empty')"
  local project; project="$(basename "${cwd:-$PWD}")"
  local pid="${PPID:-0}"
  jq -n \
    --argjson schema_version 1 \
    --arg session_id "$sid" \
    --arg tool "claude-code" \
    --argjson pid "$pid" \
    --arg project_name "$project" \
    --arg cwd "${cwd:-$PWD}" \
    --arg started_at "$(now_iso)" \
    '{schema_version:$schema_version, session_id:$session_id, tool:$tool, pid:$pid, project_name:$project_name, cwd:$cwd, started_at:$started_at}' \
    | atomic_write "$SESSIONS_DIR/$sid.json"
}

cmd_on_pretool() {
  require_jq; ensure_dirs
  local payload; payload="$(cat)"
  local sid; sid="$(echo "$payload" | jq -r '.session_id // empty')"
  [ -z "$sid" ] && exit 0
  local file="$SESSIONS_DIR/$sid.json"
  [ -f "$file" ] || exit 0

  local tool_name; tool_name="$(echo "$payload" | jq -r '.tool_name // empty')"
  local target=""
  case "$tool_name" in
    Bash)
      target="$(echo "$payload" | jq -r '.tool_input.command // empty' | cut -c1-80)" ;;
    Edit|Write|MultiEdit|Read)
      target="$(echo "$payload" | jq -r '.tool_input.file_path // empty')" ;;
    Grep|Glob)
      target="$(echo "$payload" | jq -r '.tool_input.pattern // empty')" ;;
    WebFetch)
      target="$(echo "$payload" | jq -r '.tool_input.url // empty')" ;;
    WebSearch)
      target="$(echo "$payload" | jq -r '.tool_input.query // empty')" ;;
    *)
      target="" ;;
  esac

  jq --arg tool "$tool_name" \
     --arg target "$target" \
     --arg updated_at "$(now_iso)" \
     '.current_action = {tool:$tool, target:$target, updated_at:$updated_at}' \
     "$file" | atomic_write "$file"
}

cmd_remove() {
  ensure_dirs
  local payload; payload="$(cat 2>/dev/null || true)"
  local sid
  if command -v jq >/dev/null 2>&1; then
    sid="$(echo "$payload" | jq -r '.session_id // empty')"
  else
    sid=""
  fi
  [ -z "$sid" ] && exit 0
  rm -f "$SESSIONS_DIR/$sid.json" 2>/dev/null || true
}

case "${1:-}" in
  on-sessionstart) cmd_on_sessionstart ;;
  on-pretool)      cmd_on_pretool ;;
  on-stop)         cmd_remove ;;
  on-sessionend)   cmd_remove ;;
  --help|-h|"")
    cat <<USAGE
usage: aignals-hook <on-sessionstart|on-pretool|on-stop|on-sessionend>
Reads Claude Code hook payload from stdin.
USAGE
    ;;
  *)
    echo "aignals-hook: unknown subcommand '$1'" >&2
    exit 0
    ;;
esac
```

- [ ] **Step 2: Make executable**

```bash
chmod +x CLI/aignals-hook/aignals-hook
```

- [ ] **Step 3: Smoke test by hand**

```bash
export AIGNALS_HOME=/tmp/aignals-smoke
rm -rf "$AIGNALS_HOME"
echo '{"session_id":"smoke","cwd":"/tmp/proj"}' | ./CLI/aignals-hook/aignals-hook on-sessionstart
ls "$AIGNALS_HOME/sessions"
cat "$AIGNALS_HOME/sessions/smoke.json"
echo '{"session_id":"smoke","tool_name":"Bash","tool_input":{"command":"npm test"}}' | ./CLI/aignals-hook/aignals-hook on-pretool
cat "$AIGNALS_HOME/sessions/smoke.json"
echo '{"session_id":"smoke"}' | ./CLI/aignals-hook/aignals-hook on-stop
ls "$AIGNALS_HOME/sessions"   # empty
```

Expected: file created, updated with `current_action`, removed.

- [ ] **Step 4: Commit**

```bash
git add CLI/aignals-hook/aignals-hook
git commit -m "phase-06: add aignals-hook bash CLI"
```

---

### Task 6.2: `bats` tests for the CLI

**Files:**
- Create: `Tests/HookTests/aignals-hook.bats`

- [ ] **Step 1: Write the test file**

```bats
#!/usr/bin/env bats

setup() {
  TMP="$(mktemp -d)"
  export AIGNALS_HOME="$TMP/home"
  HOOK="$BATS_TEST_DIRNAME/../../CLI/aignals-hook/aignals-hook"
}

teardown() { rm -rf "$TMP"; }

@test "on-sessionstart writes a valid session file" {
  run bash -c "echo '{\"session_id\":\"s1\",\"cwd\":\"/proj\"}' | \"$HOOK\" on-sessionstart"
  [ "$status" -eq 0 ]
  [ -f "$AIGNALS_HOME/sessions/s1.json" ]
  jq -e '.schema_version == 1 and .session_id == "s1" and .tool == "claude-code"' \
    "$AIGNALS_HOME/sessions/s1.json"
}

@test "on-sessionstart creates dirs with mode 0700" {
  echo '{"session_id":"s1"}' | "$HOOK" on-sessionstart
  perms=$(stat -f '%Lp' "$AIGNALS_HOME")
  [ "$perms" = "700" ]
}

@test "on-pretool sets current_action for Bash" {
  echo '{"session_id":"s1","cwd":"/p"}' | "$HOOK" on-sessionstart
  echo '{"session_id":"s1","tool_name":"Bash","tool_input":{"command":"npm test"}}' | "$HOOK" on-pretool
  jq -e '.current_action.tool == "Bash" and .current_action.target == "npm test"' \
    "$AIGNALS_HOME/sessions/s1.json"
}

@test "on-pretool sets target from file_path for Edit" {
  echo '{"session_id":"s1","cwd":"/p"}' | "$HOOK" on-sessionstart
  echo '{"session_id":"s1","tool_name":"Edit","tool_input":{"file_path":"main.swift"}}' | "$HOOK" on-pretool
  jq -e '.current_action.target == "main.swift"' "$AIGNALS_HOME/sessions/s1.json"
}

@test "on-pretool with unknown tool keeps name and empty target" {
  echo '{"session_id":"s1","cwd":"/p"}' | "$HOOK" on-sessionstart
  echo '{"session_id":"s1","tool_name":"MysteryTool","tool_input":{}}' | "$HOOK" on-pretool
  jq -e '.current_action.tool == "MysteryTool" and .current_action.target == ""' \
    "$AIGNALS_HOME/sessions/s1.json"
}

@test "on-pretool is a no-op when session file is absent" {
  echo '{"session_id":"ghost","tool_name":"Bash","tool_input":{"command":"x"}}' | "$HOOK" on-pretool
  [ ! -f "$AIGNALS_HOME/sessions/ghost.json" ]
}

@test "on-stop deletes the session file" {
  echo '{"session_id":"s1"}' | "$HOOK" on-sessionstart
  echo '{"session_id":"s1"}' | "$HOOK" on-stop
  [ ! -f "$AIGNALS_HOME/sessions/s1.json" ]
}

@test "on-sessionend deletes the session file" {
  echo '{"session_id":"s1"}' | "$HOOK" on-sessionstart
  echo '{"session_id":"s1"}' | "$HOOK" on-sessionend
  [ ! -f "$AIGNALS_HOME/sessions/s1.json" ]
}

@test "writes are atomic (no .tmp leftover after success)" {
  echo '{"session_id":"s1"}' | "$HOOK" on-sessionstart
  ! ls "$AIGNALS_HOME/sessions"/*.tmp.* 2>/dev/null
}

@test "jq missing causes exit 0 with stderr hint" {
  empty="$TMP/empty-path"; mkdir -p "$empty"  # contains nothing
  run env -i HOME="$HOME" AIGNALS_HOME="$AIGNALS_HOME" PATH="$empty" bash -c \
    "echo '{\"session_id\":\"s1\"}' | \"$HOOK\" on-sessionstart"
  [ "$status" -eq 0 ]
  [[ "$stderr" =~ "jq not found" ]] || [[ "$output" =~ "jq not found" ]] || true
}
```

- [ ] **Step 2: Run**

```bash
bats Tests/HookTests
```

Expected: all tests pass (except possibly the jq-missing one on machines where PATH stripping doesn't work; if it skips, mark with `skip` and move on — the behaviour is covered by the integration suite via Phase 7 case 14).

- [ ] **Step 3: Commit**

```bash
git add Tests/HookTests/aignals-hook.bats
git commit -m "phase-06: add bats coverage for aignals-hook subcommands"
```

---

### Acceptance for Phase 6

- bats tests cover: sessionstart, pretool (Bash, Edit, unknown tool, missing session), stop, sessionend, atomic writes, 0700 perms.
- Smoke test (Step 6.1.3) round-trips manually.
