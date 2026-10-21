#!/usr/bin/env bash
# Checks what `cca --allowlist` hands to claude, without starting it: a temp
# HOME, a copy of cca that starts no screen session, and a read of the
# launcher and the settings file it writes.
#
#   bash tests/allowlist.sh        # a second or two
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
sed -e "s#/usr/bin/screen#true#" -e "s#^open #true #" "$ROOT/cca" > "$TMP/cca"
mkdir -p "$TMP/home" "$TMP/repo"
echo hi > "$TMP/repo/README"
cat > "$TMP/allow.json" <<'JSON'
{"permissions":{"defaultMode":"dontAsk","allow":["Read","Bash(git log:*)"],"deny":["Bash(git push:*)"]}}
JSON
fail=0
check() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi; }
cca() { (cd "$TMP/repo" && HOME="$TMP/home" bash "$TMP/cca" "$@") 2>"$TMP/err"; }

cca "do it" --non-interactive --allowlist "$TMP/allow.json" --model opus >/dev/null
L="$TMP/home/.claude/launchers"
S="$L/agent-1.settings.json"
check "settings file written"            '[ -s "$S" ]'
check "allow rules kept"                 '[ "$(jq -c .permissions.allow "$S")" = "[\"Read\",\"Bash(git log:*)\"]" ]'
check "deny rules kept"                  '[ "$(jq -c .permissions.deny "$S")" = "[\"Bash(git push:*)\"]" ]'
check "Stop hook merged in"              'jq -e ".hooks.Stop[0].hooks[0].command | startswith(\"touch \")" "$S" >/dev/null'
check "claude gets the file and dontAsk" 'grep -q -- "--settings $S --permission-mode dontAsk" "$L/agent-1.command"'
check "only one --settings"              '[ "$(grep -o -- "--settings" "$L/agent-1.command" | wc -l)" -eq 1 ]'
check "no skip-permissions"              '! grep -q -- "--dangerously-skip-permissions" "$L/agent-1.command"'
check "no warning"                       '[ ! -s "$TMP/err" ]'
check "--allowlist never reaches claude" '! grep -q -- "--allowlist" "$L/agent-1.command"'
check "--model still passed"             'grep -q -- "--model opus" "$L/agent-1.command"'
rm -f "$TMP/home/.claude/agents/agent-1.lock"

cca "x" --allowlist "$TMP/allow.json" --dangerously-skip-permissions >/dev/null
check "refused with skip-permissions"    'grep -q "cannot go with" "$TMP/err"'
cca "x" --allowlist "$TMP/missing.json" >/dev/null
check "refused on a missing file"        'grep -q "not a readable JSON file" "$TMP/err"'
cca "x" --non-interactive --allowlist >/dev/null
check "refused without a file"           'grep -q "needs a settings file" "$TMP/err"'

exit $fail
