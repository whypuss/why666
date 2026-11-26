#!/usr/bin/env bash
# Alpine Linux (BusyBox + OpenRC) compatibility regression test for why666.
# Guards against accidental GNU-only flag usage (sed/grep/base64/shuf) or OpenRC regressions.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

pass() { printf '[PASS] %s\n' "$*"; }
fail() { printf '[FAIL] %s\n' "$*" >&2; exit 1; }

echo "=== Alpine BusyBox / OpenRC compatibility test ==="
[[ $EUID -eq 0 ]] || fail "Must run as root inside Alpine container"
command -v apk >/dev/null 2>&1 || fail "Not an Alpine Linux environment"
command -v rc-service >/dev/null 2>&1 || fail "openrc (rc-service) must be installed"

OUT="$(timeout 120 bash install.sh --local-install --non-interactive --skip-dns-check \
  --protocols "anytls:22001,reality:22002,snell:22003,socks:22004:alpuser:alppass" \
  --json)"

printf '%s' "$OUT" | jq -e '.ok == true and (.nodes | length) == 4' >/dev/null \
  || fail "Alpine install.sh --json failed:\n$OUT"
pass "Alpine install.sh --json deployed 4 protocols cleanly"

[[ -f /etc/init.d/why666 && -x /etc/init.d/why666 ]] || fail "OpenRC init script /etc/init.d/why666 missing or not executable"
pass "OpenRC service script generated at /etc/init.d/why666"

/etc/why666/bin/sing-box check -c /etc/why666/config.json -C /etc/why666/conf \
  || fail "sing-box check failed on Alpine"
pass "sing-box config check passed on Alpine"

yy ls >/dev/null
yy port 22001 22101 >/dev/null
yy passwd 22003 auto >/dev/null
yy del 22004 >/dev/null

JSON_AFTER="$(yy ai json)"
printf '%s' "$JSON_AFTER" | jq -e '
  .ok == true
  and (.nodes | length) == 3
  and (.nodes | any(.port == 22101))
' >/dev/null || fail "Alpine CRUD/JSON check failed:\n$JSON_AFTER"

/etc/why666/bin/sing-box check -c /etc/why666/config.json -C /etc/why666/conf \
  || fail "sing-box check failed after Alpine CRUD"
pass "Alpine BusyBox CRUD & yy ai json passed"

echo "ALL ALPINE COMPATIBILITY TESTS PASSED"
