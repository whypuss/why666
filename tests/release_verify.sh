#!/usr/bin/env bash
# Release packaging & tarball integrity gate for why666.
# Usage:
#   bash tests/release_verify.sh --dry-run
#   bash tests/release_verify.sh --tag v1.1.1 --out dist
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

DRY_RUN=0
EXPECTED_TAG=""
OUT_DIR="."

while [[ $# -gt 0 ]]; do
  case $1 in
    --dry-run) DRY_RUN=1; shift ;;
    --tag) EXPECTED_TAG=$2; shift 2 ;;
    --out) OUT_DIR=$2; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

pass() { printf '[PASS] %s\n' "$*"; }
fail() { printf '[FAIL] %s\n' "$*" >&2; exit 1; }

VER="$(grep -m1 '^is_sh_ver=' why666.sh | cut -d= -f2 | tr -d '[:space:]')"
[[ "$VER" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "Invalid why666.sh version: '$VER'"

if [[ -n "$EXPECTED_TAG" && "$EXPECTED_TAG" != "$VER" ]]; then
  fail "Release tag (${EXPECTED_TAG}) does not match why666.sh is_sh_ver (${VER})"
fi
pass "Release version check passed (${VER})"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

TARBALL="$TMP_DIR/code.tar.gz"
tar --exclude='.git' --exclude='.github' --exclude='.wrangler' --exclude='tests' --exclude='code.tar.gz' \
  -zcf "$TARBALL" install.sh why666.sh src README.md SKILL.md llms.txt LICENSE

# Inspect tarball contents
LIST="$(tar -tzf "$TARBALL")"
for req in install.sh why666.sh src/init.sh src/core.sh src/ai.sh src/argo.sh README.md SKILL.md llms.txt LICENSE; do
  printf '%s\n' "$LIST" | grep -qx "$req" || fail "Tarball missing required entry: $req"
done
for forbidden in .git .wrangler tests/ code.tar.gz; do
  if printf '%s\n' "$LIST" | grep -q "$forbidden"; then
    fail "Tarball contains forbidden artifact: $forbidden"
  fi
done

# Extract to isolated directory and verify syntax of packaged scripts
UNPACK="$TMP_DIR/unpack"
mkdir -p "$UNPACK"
tar -xzf "$TARBALL" -C "$UNPACK"
for f in "$UNPACK"/*.sh "$UNPACK"/src/*.sh; do
  bash -n "$f" || fail "Packaged script failed bash -n: $f"
done
pass "code.tar.gz contents and unpacked script syntax verified"

if [[ $DRY_RUN -eq 0 ]]; then
  mkdir -p "$OUT_DIR"
  cp "$TARBALL" "$OUT_DIR/code.tar.gz"
  if command -v sha256sum >/dev/null 2>&1; then
    (cd "$OUT_DIR" && sha256sum code.tar.gz > SHA256SUMS.txt)
  else
    (cd "$OUT_DIR" && shasum -a 256 code.tar.gz > SHA256SUMS.txt)
  fi
  pass "Wrote $OUT_DIR/code.tar.gz and $OUT_DIR/SHA256SUMS.txt"
else
  pass "Dry-run complete (no release artifacts left in workspace)"
fi
