#!/bin/bash
# Deterministic regression suite. No real cursor/keyboard input or LaunchAgent changes.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/stay-active"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/home"
export HOME="$TMP/home" STAY_ACTIVE_STATE_DIR="$TMP/state" PATH="$TMP/bin:$PATH"
export CLOCK_FILE="$TMP/clock" CLICK_LOG="$TMP/clicks" IDLE_VALUE=120
REAL_DATE="$(command -v date)"
cat >"$TMP/bin/date" <<'EOF'
#!/bin/bash
if [[ "$1" = '+%H:%M' ]]; then
  if [[ -f "$CLOCK_FILE" ]]; then head -n 1 "$CLOCK_FILE"; sed '1d' "$CLOCK_FILE" > "$CLOCK_FILE.next"; mv "$CLOCK_FILE.next" "$CLOCK_FILE"; else echo 09:00; fi
else
  /bin/date "$@"
fi
EOF
cat >"$TMP/bin/ioreg" <<'EOF'
#!/bin/bash
if [[ "${IDLE_VALUE:-120}" = invalid ]]; then echo 'no HIDIdleTime'; else echo '    "HIDIdleTime" = '${IDLE_VALUE:-120}'000000000'; fi
EOF
cat >"$TMP/bin/cliclick" <<'EOF'
#!/bin/bash
echo "$*" >> "$CLICK_LOG"
[[ "${CLICLICK_FAIL:-0}" != 1 ]] || exit 1
if [[ "$1" = p ]]; then echo '250,250'; fi
EOF
cat >"$TMP/bin/sleep" <<'EOF'
#!/bin/bash
exit 0
EOF
chmod +x "$TMP/bin/"*
pass=0
fail() { echo "FAIL: $*" >&2; exit 1; }
expect_ok() { "$@" >"$TMP/out" 2>"$TMP/err" || { cat "$TMP/err" >&2; fail "$*"; }; pass=$((pass+1)); }
expect_fail() { if "$@" >"$TMP/out" 2>"$TMP/err"; then fail "unexpected success: $*"; fi; pass=$((pass+1)); }
assert_has() { grep -q "$1" "$2" || fail "missing '$1' in $2"; pass=$((pass+1)); }
assert_missing() { [[ ! -e "$1" ]] || fail "unexpected file $1"; pass=$((pass+1)); }
clock() { printf '%s\n' "$@" > "$CLOCK_FILE"; }
reset_state() { rm -rf "$STAY_ACTIVE_STATE_DIR"; mkdir -p "$STAY_ACTIVE_STATE_DIR"; : > "$CLICK_LOG"; }

# Basic CLI and existing safety guarantees.
expect_ok bash -n "$APP"
expect_ok bash "$APP" --version
assert_has 'v1.2.0' "$TMP/out"
expect_ok bash "$APP" --help
assert_has 'schedule-start' "$TMP/out"
expect_ok bash "$APP" help
expect_ok bash "$APP" log
assert_has 'No activity log' "$TMP/out"
expect_fail bash "$APP" invalid-command
expect_fail bash "$APP" status
expect_fail bash "$APP" stop
reset_state
mkdir "$STAY_ACTIVE_STATE_DIR/.stay_active_lock"
echo 'not-a-pid' > "$STAY_ACTIVE_STATE_DIR/.stay_active_pid"
expect_fail bash "$APP" stop
[[ -d "$STAY_ACTIVE_STATE_DIR/.stay_active_lock" ]] || fail 'stop removed an unverified lock'
pass=$((pass+1))
reset_state

# Input validation (no worker should be launched).
expect_fail env STAY_ACTIVE_MOUSE=9 bash "$APP" schedule-start
expect_fail env STAY_ACTIVE_MIN_IDLE_SECONDS=abc bash "$APP" schedule-start
expect_fail env DAILY_START_TIME_CENTRAL=25:00 bash "$APP" schedule-start
expect_fail env DAILY_STOP_TIME_CENTRAL=17:60 bash "$APP" schedule-start
expect_fail env DAILY_START_TIME_CENTRAL=17:00 DAILY_STOP_TIME_CENTRAL=08:00 bash "$APP" schedule-start
expect_fail env DAILY_START_TIME_CENTRAL=08:00 DAILY_STOP_TIME_CENTRAL=08:00 bash "$APP" schedule-start
assert_missing "$STAY_ACTIVE_STATE_DIR/.stay_active_pid"

# Already past end: no daemon, no lock. End is exclusive.
clock 17:00
expect_ok bash "$APP" schedule-start
assert_has 'nothing started' "$TMP/out"
assert_missing "$STAY_ACTIVE_STATE_DIR/.stay_active_pid"
clock 18:01
expect_ok bash "$APP" schedule-start
assert_missing "$STAY_ACTIVE_STATE_DIR/.stay_active_lock"

# Foreground worker deterministic time progression to avoid real-minute sleeps.
# 08:59 waits, 09:00 sends input, 17:00 exits for good.
reset_state
clock 07:59 09:00 09:00 17:00
expect_ok env DAILY_START_TIME_CENTRAL=08:00 DAILY_STOP_TIME_CENTRAL=17:00 bash "$APP" __run-scheduled
assert_has 'Scheduled end reached' "$STAY_ACTIVE_STATE_DIR/.stay_active_log"
assert_has 'kd:shift ku:shift' "$CLICK_LOG"

# Alias applies when primary stop variable absent.
reset_state
clock 09:00 09:01
expect_ok env DAILY_START_TIME_CENTRAL=08:00 DAILY_END_TIME_CENTRAL=09:01 bash "$APP" __run-scheduled
assert_has 'Scheduled end reached' "$STAY_ACTIVE_STATE_DIR/.stay_active_log"

# Primary stop setting overrides alias.
reset_state
clock 09:02
expect_ok env DAILY_START_TIME_CENTRAL=08:00 DAILY_STOP_TIME_CENTRAL=09:02 DAILY_END_TIME_CENTRAL=10:00 bash "$APP" __run-scheduled
assert_has 'Scheduled stop' "$STAY_ACTIVE_STATE_DIR/.stay_active_log"

# Idle reading failures fail closed (no synthetic input).
reset_state
clock 09:00
expect_fail env IDLE_VALUE=invalid bash "$APP" __run-scheduled
assert_has 'idle time' "$STAY_ACTIVE_STATE_DIR/.stay_active_log"
[[ ! -s "$CLICK_LOG" ]] || fail 'input generated after idle inspection failure'
pass=$((pass+1))

# Recent user activity is respected; no synthetic input.
reset_state
clock 09:00 09:01
expect_ok env IDLE_VALUE=0 DAILY_STOP_TIME_CENTRAL=09:01 bash "$APP" __run-scheduled
assert_has 'Skipped input' "$STAY_ACTIVE_STATE_DIR/.stay_active_log"
[[ ! -s "$CLICK_LOG" ]] || fail 'input generated with recent real activity'
pass=$((pass+1))

# Input errors terminate after three failures.
reset_state
clock 09:00 09:00 09:00 09:00 09:00 09:00 09:00
expect_fail env CLICLICK_FAIL=1 bash "$APP" __run-scheduled
assert_has 'cliclick failed (3/3)' "$STAY_ACTIVE_STATE_DIR/.stay_active_log"

# Cursor behavior is opt-in.
reset_state
clock 09:00 09:01
expect_ok env STAY_ACTIVE_MOUSE=1 DAILY_STOP_TIME_CENTRAL=09:01 bash "$APP" __run-scheduled
assert_has '^p$' "$CLICK_LOG"
assert_has 'm:' "$CLICK_LOG"

echo "PASS: $pass assertions (mocked macOS services; no real input generated)"
