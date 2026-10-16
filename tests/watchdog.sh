#!/usr/bin/env bash
# Runs the --non-interactive watchdog against a stub `claude`: no real Claude,
# no tokens. Each case gets a temp HOME, so the live ~/.claude slots are never
# used, and a copy of cca that writes its Stop marker into the temp dir and
# starts no screen session, so live agent-N sessions and markers are never
# touched. The generated launcher is then run in the foreground.
#
#   bash tests/watchdog.sh        # about two minutes
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
GRACE=5
MAX_BUSY=30
SID=00000000-0000-4000-8000-00000000cafe

sed -e "s#/usr/bin/screen#true#" -e "s#/tmp/cca-#$TMP/cca-#" "$ROOT/cca" > "$TMP/cca"

mkdir -p "$TMP/bin"
cat > "$TMP/bin/claude" <<'STUB'
#!/bin/bash
# Imitates an agent: does its STUB_MODE, then stops talking the way the Stop
# hook marks it, and waits to be killed.
mark="$(printf '%s' "$*" | grep -o 'touch [^"]*' | head -1 | cut -d' ' -f2)"
start=$(date +%s)
kids=""
trap 'echo "killed $(( $(date +%s) - start ))" >> "$STUB_LOG"; kill $kids 2>/dev/null; exit 143' TERM
transcript="$HOME/.claude/projects/-stub/$STUB_SID.jsonl"
turn() { mkdir -p "${transcript%/*}"; echo "{\"type\":\"system\",\"subtype\":\"turn_duration\",\"durationMs\":1$1}" >> "$transcript"; }
case "$STUB_MODE" in
  stop) ;;
  # A Bash-tool job: a shell in a process group of its own, child of claude.
  job) setsid bash -c "sleep $STUB_JOB; :" & echo $! > "$STUB_LOG.job" ;;
  # An MCP server: a long-running child in claude's own process group.
  mcp) node -e 'setInterval(() => {}, 1000)' & kids=$! ;;
  # A background subagent: no process, only the count claude writes per turn.
  subagent)
    turn ',"pendingBackgroundAgentCount":1'
    ( sleep 15; turn '' ) & ;;
  talk)
    touch "$mark"
    for _ in 1 2 3 4 5; do sleep 3; touch "$mark"; done
    echo exited >> "$STUB_LOG"
    exit 0 ;;
esac
touch "$mark"
sleep 100000 & kids="$kids $!"
wait
STUB
chmod +x "$TMP/bin/claude"

fail=0
# run NAME MODE MIN MAX [JOB_SECONDS]: the stub must be killed between MIN and
# MAX seconds after it starts; MIN=- means it must exit by itself instead.
run() {
  name="$1" mode="$2" min="$3" max="$4" job="${5:-0}"
  home="$TMP/$name/home" repo="$TMP/$name/repo" log="$TMP/$name/stub.log"
  mkdir -p "$home" "$repo"
  echo hi > "$repo/README"
  (cd "$repo" && HOME="$home" CCA_GRACE=$GRACE CCA_MAX_BUSY=$MAX_BUSY CCA_CLOSE_DELAY=1 \
    bash "$TMP/cca" "test prompt" --non-interactive --dangerously-skip-permissions --session-id "$SID" >/dev/null)
  HOME="$home" PATH="$TMP/bin:$PATH" STUB_MODE="$mode" STUB_JOB="$job" STUB_LOG="$log" STUB_SID="$SID" \
    bash "$home/.claude/launchers/agent-1.command" < /dev/null > "$TMP/$name/out" 2>&1
  got="$(cat "$log" 2>/dev/null)"
  ok=1
  if [ "$min" = - ]; then
    [ "$got" = exited ] || ok=0
  else
    secs="${got#killed }"
    case "$got" in killed\ *) [ "$secs" -ge "$min" ] && [ "$secs" -le "$max" ] || ok=0 ;; *) ok=0 ;; esac
  fi
  if [ -s "$log.job" ] && kill -0 "$(cat "$log.job")" 2>/dev/null; then
    ok=0; got="$got; background job still alive"; kill "$(cat "$log.job")"
  fi
  if [ "$ok" = 1 ]; then echo "PASS $name ($got)"; else echo "FAIL $name ($got, wanted $min..$max)"; fail=1; fi
  grep 'session ended' "$TMP/$name/out" | sed 's/^/     /'
}

run stop-is-killed-after-grace       stop     $GRACE 16
run background-job-holds-the-session job      $(( 20 + GRACE - 1 )) $(( 20 + GRACE + 11 )) 20
run hung-job-killed-at-max-busy      job      $(( MAX_BUSY - 1 )) $(( MAX_BUSY + 10 )) 1000
run agent-that-talks-is-not-killed   talk     - -
run mcp-server-does-not-count        mcp      $GRACE 16
run background-subagent-holds-it     subagent $(( 15 + GRACE - 1 )) $(( 15 + GRACE + 11 ))

grep -q CCA_MAX_BUSY "$TMP/hung-job-killed-at-max-busy/out" || { echo "FAIL hung job: no CCA_MAX_BUSY line"; fail=1; }
exit $fail
