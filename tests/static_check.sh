#!/usr/bin/env bash
# Fast static quality & contract gate for why666 (runs on both macOS and Linux).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

pass() { printf '[PASS] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*"; }
fail() { printf '[FAIL] %s\n' "$*" >&2; exit 1; }

echo "=== 1. Bash syntax check (bash -n) ==="
sh_files=()
for f in *.sh src/*.sh tests/*.sh; do
  [[ -f "$f" ]] || continue
  bash -n "$f" || fail "bash -n failed: $f"
  sh_files+=("$f")
done
[[ ${#sh_files[@]} -gt 0 ]] || fail "No shell scripts found"
pass "Checked ${#sh_files[@]} shell scripts with bash -n"

echo "=== 2. Merge conflict markers & line-ending hygiene ==="
if grep -rnE '^(<<<<<<< |=======$|>>>>>>> )' *.sh src/ tests/ docs/ README.md SKILL.md llms.txt 2>/dev/null; then
  fail "Detected unresolved git merge conflict markers"
fi
for f in "${sh_files[@]}"; do
  if LC_ALL=C grep -q $'\r' "$f"; then
    fail "CRLF line endings found in shell script: $f (use LF only)"
  fi
done
pass "No conflict markers or CRLF issues in shell scripts"

echo "=== 3. ShellCheck static analysis (error-level blocking) ==="
if command -v shellcheck >/dev/null 2>&1; then
  shellcheck --shell=bash --severity=error --format=gcc "${sh_files[@]}" || fail "shellcheck found error-level issues"
  pass "shellcheck --severity=error passed across ${#sh_files[@]} scripts"
else
  warn "shellcheck not installed locally; CI will enforce shellcheck"
fi

echo "=== 4. Module dependency check (load *.sh targets exist) ==="
missing_loads=0
while IFS= read -r target; do
  [[ -z "$target" ]] && continue
  if [[ ! -f "src/$target" ]]; then
    echo "Missing loaded module: src/$target" >&2
    missing_loads=$((missing_loads + 1))
  fi
done < <(grep -hoE '\bload[[:space:]]+[A-Za-z0-9._-]+\.sh\b' *.sh src/*.sh | awk '{print $2}' | sort -u)
[[ $missing_loads -eq 0 ]] || fail "$missing_loads missing src/*.sh modules referenced by load"
pass "All referenced load *.sh modules exist under src/"

echo "=== 5. Version, path constants & brand contract consistency ==="
ver=$(grep -m1 '^is_sh_ver=' why666.sh | cut -d= -f2 | tr -d '[:space:]')
[[ "$ver" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "Invalid is_sh_ver in why666.sh: '$ver'"

grep -q '^author=whypuss$' install.sh || fail "install.sh author mismatch"
grep -q '^project=why666$' install.sh || fail "install.sh project mismatch"
grep -q '^is_sh_short_bin=/usr/local/bin/yy$' install.sh || fail "install.sh short command mismatch"
grep -q '^author=whypuss$' src/init.sh || fail "src/init.sh author mismatch"
grep -q '^project=why666$' src/init.sh || fail "src/init.sh project mismatch"
grep -q '^is_sh_short_bin=/usr/local/bin/yy$' src/init.sh || fail "src/init.sh short command mismatch"

for doc in README.md SKILL.md llms.txt docs/index.html; do
  [[ -f "$doc" ]] || fail "Required documentation file missing: $doc"
done
grep -q 'https://github.com/whypuss/why666' README.md || fail "README.md missing GitHub link"
grep -q 'https://github.com/whypuss/why666' SKILL.md || fail "SKILL.md missing GitHub link"
grep -q 'https://github.com/whypuss/why666' llms.txt || fail "llms.txt missing GitHub link"
grep -q 'https://whycat666.pages.dev/' README.md || fail "README.md missing docs URL"
grep -q "brand-badge\">${ver}<" docs/index.html || fail "docs/index.html badge version does not match why666.sh (${ver})"
grep -q "why666 ${ver} ·" docs/index.html || fail "docs/index.html footer version does not match why666.sh (${ver})"
pass "Version (${ver}), constants, and docs links are consistent"

echo "=== 6. Docs HTML & inline JS validation (docs/index.html) ==="
grep -q '<span>https://github.com/whypuss/why666</span>' docs/index.html || fail "docs/index.html missing full GitHub URL in hero"
grep -q 'id="quickNodesCmd">yy ai json</pre>' docs/index.html || fail "docs/index.html missing top yy ai json quick command"

if command -v node >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1; then
  python3 - <<'PY'
import re, subprocess, tempfile

html = open("docs/index.html", encoding="utf-8").read()
scripts = re.findall(r"<script>([\s\S]*?)</script>", html)
assert len(scripts) == 1, f"Expected 1 inline <script> block, got {len(scripts)}"
with tempfile.NamedTemporaryFile("w", suffix=".js", encoding="utf-8") as tf:
    tf.write(scripts[0])
    tf.flush()
    res = subprocess.run(["node", "--check", tf.name], capture_output=True, text=True)
    if res.returncode != 0:
        raise SystemExit("Inline JS syntax error:\n" + res.stderr)
PY
  pass "docs/index.html inline JavaScript syntax verified with node --check"
else
  warn "node or python3 unavailable; skipped inline JS syntax check"
fi

echo "=== 7. Core protocol & reset_config_vars sanity check ==="
for proto in AnyTLS VLESS-REALITY Hysteria2 TUIC AnyTLS-REALITY Naive Snell Shadowsocks Trojan Socks Direct; do
  grep -qE "^[[:space:]]+${proto}$" src/core.sh || fail "Missing core protocol in protocol_list: $proto"
done
grep -q '^reset_config_vars()' src/core.sh || fail "reset_config_vars() missing in src/core.sh"
pass "Core protocol definitions intact"

echo "ALL STATIC CHECKS PASSED"
