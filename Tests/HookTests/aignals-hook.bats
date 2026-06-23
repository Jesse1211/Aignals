#!/usr/bin/env bats

setup() {
  TMP="$(mktemp -d)"
  export AIGNALS_HOME="$TMP/home"
  HOOK="$BATS_TEST_DIRNAME/../../CLI/aignals-hook/aignals-hook"
}

teardown() { rm -rf "$TMP"; }

@test "on-sessionstart writes a valid schema-v2 session file (state=waiting_input)" {
  run bash -c "echo '{\"session_id\":\"s1\",\"cwd\":\"/proj\"}' | \"$HOOK\" on-sessionstart"
  [ "$status" -eq 0 ]
  [ -f "$AIGNALS_HOME/sessions/s1.json" ]
  jq -e '.schema_version == 2 and .session_id == "s1" and .tool == "claude-code" and .state == "waiting_input"' \
    "$AIGNALS_HOME/sessions/s1.json"
}

@test "on-sessionstart sets updated_at (ISO8601, millisecond precision)" {
  echo '{"session_id":"s1","cwd":"/p"}' | "$HOOK" on-sessionstart
  # now_iso stamps millisecond precision (INV-8 same-second reorder defense).
  # The perl/Time::HiRes path emits real milliseconds; the date fallback emits
  # ".000Z". Either way the form is YYYY-MM-DDTHH:MM:SS.mmmZ.
  jq -e '.updated_at | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}[.][0-9]{3}Z$")' \
    "$AIGNALS_HOME/sessions/s1.json"
}

@test "on-sessionstart creates dirs with mode 0700" {
  echo '{"session_id":"s1"}' | "$HOOK" on-sessionstart
  perms=$(stat -f '%Lp' "$AIGNALS_HOME")
  [ "$perms" = "700" ]
}

@test "on-pretool sets state=working and current_action for Bash" {
  echo '{"session_id":"s1","cwd":"/p"}' | "$HOOK" on-sessionstart
  echo '{"session_id":"s1","tool_name":"Bash","tool_input":{"command":"npm test"}}' | "$HOOK" on-pretool
  jq -e '.state == "working" and .schema_version == 2 and .current_action.tool == "Bash" and .current_action.target == "npm test"' \
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

@test "ADR-25/INV-14: on-pretool on a non-existent file ADOPTS it (state=working + current_action)" {
  echo '{"session_id":"adopt","cwd":"/proj/bar","tool_name":"Bash","tool_input":{"command":"npm test"}}' | "$HOOK" on-pretool
  [ -f "$AIGNALS_HOME/sessions/adopt.json" ]
  jq -e '.schema_version == 2 and .state == "working" and .project_name == "bar" and .current_action.tool == "Bash" and .current_action.target == "npm test"' \
    "$AIGNALS_HOME/sessions/adopt.json"
}

@test "on-prompt sets state=working" {
  echo '{"session_id":"s1","cwd":"/p"}' | "$HOOK" on-sessionstart
  echo '{"session_id":"s1"}' | "$HOOK" on-prompt
  jq -e '.state == "working" and .schema_version == 2' "$AIGNALS_HOME/sessions/s1.json"
}

@test "ADR-25/INV-14: on-prompt on a non-existent file ADOPTS it (creates state=working)" {
  echo '{"session_id":"adopt","cwd":"/proj/foo","pid":4242}' | "$HOOK" on-prompt
  [ -f "$AIGNALS_HOME/sessions/adopt.json" ]
  jq -e '.schema_version == 2 and .session_id == "adopt" and .tool == "claude-code" and .state == "working" and .pid == 4242 and .project_name == "foo" and .cwd == "/proj/foo"' \
    "$AIGNALS_HOME/sessions/adopt.json"
  jq -e '.updated_at | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}[.][0-9]{3}Z$")' \
    "$AIGNALS_HOME/sessions/adopt.json"
}

@test "on-posttool sets state=working" {
  echo '{"session_id":"s1","cwd":"/p"}' | "$HOOK" on-sessionstart
  echo '{"session_id":"s1"}' | "$HOOK" on-posttool
  jq -e '.state == "working"' "$AIGNALS_HOME/sessions/s1.json"
}

@test "on-permission sets state=waiting_permission" {
  echo '{"session_id":"s1","cwd":"/p"}' | "$HOOK" on-sessionstart
  echo '{"session_id":"s1"}' | "$HOOK" on-permission
  jq -e '.state == "waiting_permission"' "$AIGNALS_HOME/sessions/s1.json"
}

@test "on-permission-denied sets state=working" {
  echo '{"session_id":"s1","cwd":"/p"}' | "$HOOK" on-sessionstart
  echo '{"session_id":"s1"}' | "$HOOK" on-permission
  echo '{"session_id":"s1"}' | "$HOOK" on-permission-denied
  jq -e '.state == "working"' "$AIGNALS_HOME/sessions/s1.json"
}

@test "on-idle sets state=waiting_input" {
  echo '{"session_id":"s1","cwd":"/p"}' | "$HOOK" on-sessionstart
  echo '{"session_id":"s1","tool_name":"Bash","tool_input":{"command":"x"}}' | "$HOOK" on-pretool
  echo '{"session_id":"s1"}' | "$HOOK" on-idle
  jq -e '.state == "waiting_input"' "$AIGNALS_HOME/sessions/s1.json"
}

@test "on-stop keeps the file and sets state=waiting_input" {
  echo '{"session_id":"s1","cwd":"/p"}' | "$HOOK" on-sessionstart
  echo '{"session_id":"s1","tool_name":"Bash","tool_input":{"command":"x"}}' | "$HOOK" on-pretool
  echo '{"session_id":"s1"}' | "$HOOK" on-stop
  [ -f "$AIGNALS_HOME/sessions/s1.json" ]
  jq -e '.state == "waiting_input" and .schema_version == 2' "$AIGNALS_HOME/sessions/s1.json"
}

@test "ADR-25/INV-14: on-stop on a non-existent file ADOPTS it (creates state=waiting_input)" {
  echo '{"session_id":"adopt","cwd":"/proj/baz"}' | "$HOOK" on-stop
  [ -f "$AIGNALS_HOME/sessions/adopt.json" ]
  jq -e '.schema_version == 2 and .state == "waiting_input" and .project_name == "baz"' \
    "$AIGNALS_HOME/sessions/adopt.json"
}

@test "ADR-25/INV-14: on-permission on a non-existent file ADOPTS it (creates state=waiting_permission)" {
  echo '{"session_id":"adopt","cwd":"/proj/qux"}' | "$HOOK" on-permission
  [ -f "$AIGNALS_HOME/sessions/adopt.json" ]
  jq -e '.schema_version == 2 and .state == "waiting_permission" and .project_name == "qux"' \
    "$AIGNALS_HOME/sessions/adopt.json"
}

@test "on-sessionend deletes the session file" {
  echo '{"session_id":"s1"}' | "$HOOK" on-sessionstart
  echo '{"session_id":"s1"}' | "$HOOK" on-sessionend
  [ ! -f "$AIGNALS_HOME/sessions/s1.json" ]
}

@test "ADR-25/INV-14: on-sessionend on a non-existent file creates NOTHING (no create-then-delete)" {
  run bash -c "echo '{\"session_id\":\"ghost\"}' | \"$HOOK\" on-sessionend"
  [ "$status" -eq 0 ]
  [ ! -f "$AIGNALS_HOME/sessions/ghost.json" ]
}

@test "INV-8: a write carrying an older updated_at than stored is dropped (file unchanged)" {
  mkdir -p "$AIGNALS_HOME/sessions"
  # Seed a file whose updated_at is far in the FUTURE. Any real subcommand's
  # incoming timestamp (now_iso) is older, so the write must be dropped and the
  # file must stay byte-for-byte identical.
  cat > "$AIGNALS_HOME/sessions/s1.json" <<'JSON'
{"schema_version":2,"session_id":"s1","tool":"claude-code","project_name":"p","state":"waiting_permission","started_at":"2999-01-01T00:00:00Z","updated_at":"2999-01-01T00:00:00Z"}
JSON
  before="$(cat "$AIGNALS_HOME/sessions/s1.json")"
  run bash -c "echo '{\"session_id\":\"s1\"}' | \"$HOOK\" on-prompt"
  [ "$status" -eq 0 ]
  after="$(cat "$AIGNALS_HOME/sessions/s1.json")"
  [ "$before" = "$after" ]
  # state stays the seeded one, NOT working
  jq -e '.state == "waiting_permission"' "$AIGNALS_HOME/sessions/s1.json"
}

@test "INV-8: a write with an equal-or-newer updated_at is applied" {
  mkdir -p "$AIGNALS_HOME/sessions"
  # Seed a file whose updated_at is in the PAST so the incoming now_iso is newer.
  cat > "$AIGNALS_HOME/sessions/s1.json" <<'JSON'
{"schema_version":2,"session_id":"s1","tool":"claude-code","project_name":"p","state":"waiting_input","started_at":"2000-01-01T00:00:00Z","updated_at":"2000-01-01T00:00:00Z"}
JSON
  echo '{"session_id":"s1"}' | "$HOOK" on-prompt
  jq -e '.state == "working" and (.updated_at > "2000-01-01T00:00:00Z")' \
    "$AIGNALS_HOME/sessions/s1.json"
}

@test "INV-8 same-second: a stored later-millisecond stamp drops an earlier same-second write" {
  mkdir -p "$AIGNALS_HOME/sessions"
  # Seed updated_at at the CURRENT wall-clock second but with .999 milliseconds,
  # so the real incoming now_iso (same second, far fewer ms) is lexically older
  # and MUST be dropped. With the old second-granular stamp this tie would have
  # been (incorrectly) applied. This is the core INV-8 same-second guarantee.
  sec="$(date -u +"%Y-%m-%dT%H:%M:%S")"
  cat > "$AIGNALS_HOME/sessions/s1.json" <<JSON
{"schema_version":2,"session_id":"s1","tool":"claude-code","project_name":"p","state":"waiting_permission","started_at":"${sec}.999Z","updated_at":"${sec}.999Z"}
JSON
  before="$(cat "$AIGNALS_HOME/sessions/s1.json")"
  run bash -c "echo '{\"session_id\":\"s1\"}' | \"$HOOK\" on-prompt"
  [ "$status" -eq 0 ]
  after="$(cat "$AIGNALS_HOME/sessions/s1.json")"
  # Same-second-but-earlier-ms write dropped: file byte-identical, state unchanged.
  [ "$before" = "$after" ]
  jq -e '.state == "waiting_permission"' "$AIGNALS_HOME/sessions/s1.json"
}

@test "INV-8 same-second: a stored earlier-millisecond stamp lets a later same-second write apply" {
  mkdir -p "$AIGNALS_HOME/sessions"
  # Same second, .000 milliseconds: the real incoming now_iso (same second, >=0 ms)
  # is >= stored, so the write applies. Proves millisecond stamps don't over-reject.
  sec="$(date -u +"%Y-%m-%dT%H:%M:%S")"
  cat > "$AIGNALS_HOME/sessions/s1.json" <<JSON
{"schema_version":2,"session_id":"s1","tool":"claude-code","project_name":"p","state":"waiting_input","started_at":"${sec}.000Z","updated_at":"${sec}.000Z"}
JSON
  echo '{"session_id":"s1"}' | "$HOOK" on-prompt
  jq -e '.state == "working"' "$AIGNALS_HOME/sessions/s1.json"
}

@test "writes are atomic (no .tmp leftover after success)" {
  echo '{"session_id":"s1"}' | "$HOOK" on-sessionstart
  ! ls "$AIGNALS_HOME/sessions"/*.tmp.* 2>/dev/null
}

@test "jq missing causes exit 0 with stderr hint" {
  # Sandbox PATH: every external tool aignals-hook uses, except jq. An empty
  # PATH would break the script's `#!/usr/bin/env bash` shebang itself, so we
  # symlink the tools the hook actually needs and just omit jq.
  sandbox="$TMP/sandbox-no-jq"
  mkdir -p "$sandbox"
  for cmd in env bash mkdir chmod cat mv date basename cut rm; do
    src="$(command -v "$cmd")" || skip "missing $cmd on test host"
    ln -sf "$src" "$sandbox/$cmd"
  done
  run env -i HOME="$HOME" AIGNALS_HOME="$AIGNALS_HOME" PATH="$sandbox" bash -c \
    "echo '{\"session_id\":\"s1\"}' | \"$HOOK\" on-sessionstart"
  [ "$status" -eq 0 ]
  [[ "$stderr" =~ "jq not found" ]] || [[ "$output" =~ "jq not found" ]] || true
}
