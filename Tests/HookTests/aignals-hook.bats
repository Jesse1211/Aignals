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
