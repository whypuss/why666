#!/usr/bin/env bash
# Comprehensive Linux end-to-end regression suite for why666 (systemd).
# Covers: full protocol matrix, no-auto-tls domain variants, CRUD modifications,
# boundary rejections, AI JSON/deploy/doctor contracts, live SOCKS5 traffic smoke test, and CF Argo.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

[[ $EUID -eq 0 ]] || { echo "[FAIL] tests/e2e_linux.sh must run as root" >&2; exit 1; }

pass() { printf '\n[PASS] %s\n' "$*"; }
fail() { printf '\n[FAIL] %s\n' "$*" >&2; exit 1; }
step() { printf '\n==================================================\n[STEP] %s\n==================================================\n' "$*"; }

assert_json_clean() {
  local raw=$1
  local desc=$2
  if printf '%s' "$raw" | grep -q $'\x1b'; then
    fail "$desc contains ANSI escape sequences in JSON output"
  fi
  printf '%s' "$raw" | jq -e . >/dev/null || fail "$desc is not valid JSON:\n$raw"
}

assert_singbox_valid() {
  /etc/why666/bin/sing-box check -c /etc/why666/config.json -C /etc/why666/conf \
    || fail "sing-box check failed!"
}

wait_for_singbox() {
  local i
  for i in $(seq 1 15); do
    if systemctl is-active --quiet why666 2>/dev/null || pgrep -x sing-box >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  systemctl status why666 --no-pager || true
  fail "sing-box service failed to become active"
}

step "1. Non-interactive install + 18-protocol batch deployment (--json)"
DEPLOY_OUT="$(timeout 120 bash install.sh --local-install --non-interactive --skip-dns-check \
  --protocols "anytls:21001,reality:21002,rh2:21003,hy2:21004,tuic:21005,anyreality:21006,snell:21007,snell5:21008,ss:21009,trojan:21010,ws:21011,vless-ws:21012,tcp:21013,http:21014,quic:21015,socks:21016:ciuser0:cipass0,door:21017:1.1.1.1:443,naive:naive.example.com:21018:demo:demopass123456" \
  --json)"
assert_json_clean "$DEPLOY_OUT" "install.sh --json"
printf '%s' "$DEPLOY_OUT" | jq -e '
  .ok == true
  and .meta.tool == "why666"
  and (.nodes | length) == 18
  and (.share_links | length) >= 16
  and all(.nodes[]; (.name | length) > 0 and (.protocol | length) > 0 and (.port | tonumber) > 0)
' >/dev/null || fail "Unexpected install.sh JSON contract:\n$DEPLOY_OUT"
assert_singbox_valid
pass "Batch install deployed 18 protocols cleanly with valid JSON schema"

step "2. Domain TLS protocol variants via no-auto-tls (all remaining protocols)"
timeout 30 yy no-auto-tls native native2.example.com 21019 demo2 demopass123456 >/dev/null
timeout 30 yy no-auto-tls wss wss.example.com >/dev/null
timeout 30 yy no-auto-tls h2 h2.example.com >/dev/null
timeout 30 yy no-auto-tls hu hu.example.com >/dev/null
timeout 30 yy no-auto-tls vws vws.example.com >/dev/null
timeout 30 yy no-auto-tls vh2 vh2.example.com >/dev/null
timeout 30 yy no-auto-tls vhu vhu.example.com >/dev/null
timeout 30 yy no-auto-tls tws tws.example.com >/dev/null
timeout 30 yy no-auto-tls th2 th2.example.com >/dev/null
timeout 30 yy no-auto-tls thu thu.example.com >/dev/null
assert_singbox_valid
COUNT_AFTER_TLS=$(ls /etc/why666/conf/*.json | wc -l | tr -d ' ')
[[ "$COUNT_AFTER_TLS" -eq 28 ]] || fail "Expected 28 configs after TLS variants, got $COUNT_AFTER_TLS"
pass "All 28 protocol/variant configs generated and validated by sing-box check"

step "3. Preview mode (yy gen) must not write files to /etc/why666/conf"
yy gen anytls 29991 >/dev/null
yy gen snell 29992 >/dev/null
COUNT_AFTER_GEN=$(ls /etc/why666/conf/*.json | wc -l | tr -d ' ')
[[ "$COUNT_AFTER_GEN" -eq 28 ]] || fail "yy gen unexpectedly mutated conf dir ($COUNT_AFTER_GEN != 28)"
pass "yy gen previewed cleanly without mutating disk"

step "4. Basic inspection & utility commands"
yy version >/dev/null
yy help >/dev/null
yy ls >/dev/null
yy status >/dev/null
yy info 21001 >/dev/null
yy url 21001 >/dev/null
[[ "$(yy get-port | tr -dc '0-9')" =~ ^[0-9]+$ ]] || fail "yy get-port failed"
yy pbk | grep -q "PrivateKey" || fail "yy pbk failed"
[[ -n "$(yy ss2022)" ]] || fail "yy ss2022 failed"
pass "Basic commands (version/help/ls/status/info/url/get-port/pbk/ss2022) passed"

step "5. CRUD modification regression (port/passwd/id/sni/key/method/path/user/fix)"
# Port change on AnyTLS 21001 -> 24443
yy port 21001 24443 >/dev/null
assert_singbox_valid
yy ai json | jq -e '.nodes | any(.protocol == "anytls" and .port == 24443)' >/dev/null \
  || fail "yy port failed to update AnyTLS port to 24443"

# Password change on Snell v6 21007 -> auto (must be >= 12 chars)
yy passwd 21007 auto >/dev/null
assert_singbox_valid
yy ai json | jq -e '.nodes | any(.port == 21007 and (.params.password | length) >= 12)' >/dev/null \
  || fail "yy passwd snell auto produced invalid PSK"

# UUID / SNI / Key change on VLESS-REALITY 21002
OLD_UUID=$(yy ai json | jq -r '.nodes[] | select(.port == 21002) | .params.uuid')
yy id 21002 auto >/dev/null
NEW_UUID=$(yy ai json | jq -r '.nodes[] | select(.port == 21002) | .params.uuid')
[[ -n "$NEW_UUID" && "$NEW_UUID" != "$OLD_UUID" ]] || fail "yy id reality auto did not change UUID"

yy sni 21002 www.cloudflare.com >/dev/null
yy ai json | jq -e '.nodes | any(.port == 21002 and .params.sni == "www.cloudflare.com")' >/dev/null \
  || fail "yy sni failed to update SNI"

OLD_PBK=$(yy ai json | jq -r '.nodes[] | select(.port == 21002) | .params.public_key')
yy key 21002 auto >/dev/null
NEW_PBK=$(yy ai json | jq -r '.nodes[] | select(.port == 21002) | .params.public_key')
[[ -n "$NEW_PBK" && "$NEW_PBK" != "$OLD_PBK" ]] || fail "yy key auto did not rotate REALITY keypair"

# Shadowsocks method change on 21009
yy method 21009 2022-blake3-aes-256-gcm >/dev/null
yy ai json | jq -e '.nodes | any(.port == 21009 and .params.method == "2022-blake3-aes-256-gcm")' >/dev/null \
  || fail "yy method failed"

# Path change on VMess-WS 21011
yy path 21011 /ci-ws-path >/dev/null
yy ai json | jq -e '.nodes | any(.port == 21011 and .params.path == "/ci-ws-path")' >/dev/null \
  || fail "yy path failed"

# Username change on Socks5 21016
yy user 21016 ciuser_new >/dev/null
yy ai json | jq -e '.nodes | any(.port == 21016 and .params.username == "ciuser_new")' >/dev/null \
  || fail "yy user failed"

# Fix single & fix-all
yy fix 24443 >/dev/null
yy fix-all >/dev/null
assert_singbox_valid
pass "All CRUD modifications and fix/fix-all preserved valid sing-box configs"

step "6. Boundary & invalid input rejection"
if timeout 15 yy add snell 21999 shortpsk 6 >/dev/null 2>&1; then
  fail "Snell v6 short PSK (<12 bytes) should have been rejected"
fi
if timeout 15 yy port 24443 99999 >/dev/null 2>&1; then
  fail "Out-of-range port 99999 should have been rejected"
fi
assert_singbox_valid
pass "Boundary validation rejected invalid Snell PSK and invalid port"

step "7. Single delete (del) & batch delete (ddel)"
yy del 21017 >/dev/null
yy ddel 21013 21014 21015 >/dev/null
sleep 1
assert_singbox_valid
COUNT_AFTER_DEL=$(ls /etc/why666/conf/*.json | wc -l | tr -d ' ')
[[ "$COUNT_AFTER_DEL" -eq 24 ]] || fail "Expected 24 configs after deleting 4, got $COUNT_AFTER_DEL"
pass "yy del & yy ddel removed exact targets without harming sibling configs"

step "8. Incremental AI deploy (yy ai deploy --json) & AI Doctor & AI JSON contract"
INC_OUT="$(yy ai deploy --protocols "anytls:25443" --json)"
assert_json_clean "$INC_OUT" "yy ai deploy --json"
printf '%s' "$INC_OUT" | jq -e '.ok == true and (.nodes | length) == 25 and (.nodes | any(.port == 25443))' >/dev/null \
  || fail "Incremental yy ai deploy did not preserve existing nodes or add port 25443"

DOC_OUT="$(yy ai doctor --json)"
assert_json_clean "$DOC_OUT" "yy ai doctor --json"
printf '%s' "$DOC_OUT" | jq -e '.config_valid == true and .config_count == 25' >/dev/null \
  || fail "yy ai doctor --json contract failed:\n$DOC_OUT"

AI_JSON="$(yy ai json)"
assert_json_clean "$AI_JSON" "yy ai json"
printf '%s' "$AI_JSON" | jq -e '
  .ok == true
  and (.nodes | length) == 25
  and (.share_links | length) >= 25
' >/dev/null || fail "yy ai json contract failed"
pass "Incremental yy ai deploy, yy ai doctor --json, and yy ai json contracts verified"

step "9. Live data-plane smoke test (real TCP traffic through sing-box Socks5 inbound)"
yy restart >/dev/null
sleep 2
wait_for_singbox

# Start a temporary localhost HTTP server and verify sing-box actually proxies traffic to it via Socks5:21016
python3 - <<'PY' &
import http.server, socketserver
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"WHY666_DATAPLANE_OK")
    def log_message(self, *args):
        pass
with socketserver.TCPServer(("127.0.0.1", 18089), H) as httpd:
    httpd.handle_request()
PY
ECHO_PID=$!
sleep 1

SOCKS_PASS=$(yy ai json | jq -r '.nodes[] | select(.port == 21016) | .params.password')
RESP=$(curl -fsS --max-time 10 --socks5-hostname "ciuser_new:${SOCKS_PASS}@127.0.0.1:21016" "http://127.0.0.1:18089/" || true)
kill "$ECHO_PID" 2>/dev/null || true
[[ "$RESP" == "WHY666_DATAPLANE_OK" ]] || fail "Live Socks5 data-plane test failed (got: '$RESP')"
pass "Live sing-box Socks5 data-plane forwarded real TCP traffic successfully"

step "10. Cloudflare Argo quick tunnel regression"
timeout 45 why666 argo quick vmess auto http2 || true
why666 argo status || true
ARGO_JSON="$(why666 ai json)"
assert_json_clean "$ARGO_JSON" "yy ai json (after argo)"
printf '%s' "$ARGO_JSON" | jq -e '.argo != null and .argo.enabled == true' >/dev/null \
  || fail "Expected .argo.enabled == true after argo quick"
pass "CF Argo quick tunnel config & JSON export verified"

echo ""
echo "=================================================="
echo "ALL LINUX E2E REGRESSION TESTS PASSED (10/10)"
echo "=================================================="
