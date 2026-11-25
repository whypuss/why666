---
name: why666-deploy
description: Use this skill to automatically install, configure, diagnose, and manage the why666 sing-box proxy stack on Linux servers (Ubuntu/Debian/CentOS/Rocky/SUSE/Alpine), including VLESS-REALITY, Hysteria2, TUIC, AnyTLS, AnyTLS-REALITY, NaiveProxy (H2/H3), Snell v5/v6, Shadowsocks-2022, and Cloudflare Argo tunnels without interactive prompts.
---

# why666 AI Agent Deployment Skill

`why666` is a high-efficiency multi-config `sing-box` (>= 1.14) management script built with first-class non-interactive CLI flags, Cloudflare Argo tunnel automation, and structured JSON output for AI Agents.

## Core Rules for AI Agents

1. **Always use non-interactive mode**: Pass `--non-interactive` (`-y`) or `--json` (which implies `-y`) so commands never block on `read` prompts.
2. **Always request `--json` when installing or inspecting**: Parse the returned JSON (`nodes`, `argo`, `share_links`, `meta`) instead of scraping ANSI terminal output.
3. **Verify before reporting done**: Run `why666 ai doctor --json` and confirm `"ok": true`, `"config_valid": true`, and `"services.sing_box": true`.
4. **NaiveProxy requires a real domain + valid TLS cert**: Do not deploy `naive` without a domain pointed to the server (unless passing existing `cert_path` and `key_path`). `naive` and `native` are accepted aliases.
5. **Snell v6 requires sing-box >= 1.14.0** and a PSK of 12-255 bytes (auto-generated UUID is valid by default).

## One-Shot Automated Installation

### Option A: CLI Flags (Recommended)

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/whypuss/why666/main/install.sh) \
  --non-interactive \
  --protocols "reality,hy2,snell,anyreality" \
  --argo quick \
  --bbr \
  --json
```

### Option B: Environment Variables (Single-line friendly)

```bash
WHY666_PROTOCOLS="reality,hy2,snell" WHY666_ARGO="quick" WHY666_BBR=1 WHY666_JSON=1 \
  bash <(curl -fsSL https://raw.githubusercontent.com/whypuss/why666/main/install.sh)
```

### Option C: Fixed Cloudflare Argo Tunnel + NaiveProxy

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/whypuss/why666/main/install.sh) \
  --non-interactive \
  --protocols "reality,snell,naive:proxy.example.com:443" \
  --argo fixed \
  --argo-domain "argo.example.com" \
  --argo-token "eyJhIjoi..." \
  --argo-proto http2 \
  --argo-backend vmess \
  --bbr \
  --json
```

## Protocol Specification Syntax (`--protocols`)

Comma-separated specs. Each spec is `protocol` or `protocol:arg1:arg2:...` (`auto` leaves a field randomized):

| Alias | Protocol | Positional Args (`:` separated in `--protocols`, space separated in `why666 add`) | Notes |
|---|---|---|---|
| `anytls` | AnyTLS | `[port] [password] [domain]` | Default protocol; self-signed without domain, ACME with domain |
| `reality` / `r` | VLESS-REALITY (Vision) | `[port] [uuid] [sni]` | Zero cert warning, no domain needed |
| `hy2` / `hy` | Hysteria2 | `[port] [password]` | UDP/QUIC, self-signed TLS + `pinSHA256` |
| `snell` / `sn` | Snell v6 (default) | `[port] [psk] [version:6\|5] [mode:default\|unshaped\|unsafe-raw]` | Requires sing-box >= 1.14.0 |
| `snell5` | Snell v5 | `[port] [psk]` | Compatible with Surge/Mihomo v5 |
| `naive` / `native` / `nv` | NaiveProxy (H2 + H3/QUIC) | `<domain> [port] [user] [pass] [cert_path] [key_path]` | Built-in ACME by default; needs real domain |
| `anyreality` / `ar` | AnyTLS-REALITY | `[port] [password] [sni]` | No domain needed |
| `tuic` | TUIC v5 | `[port] [uuid]` | UDP/QUIC + BBR |
| `ss` / `ss2022` | Shadowsocks 2022 | `[port] [password] [method]` | Defaults to 2022-blake3 |
| `trojan` | Trojan | `[port] [password]` | Self-signed TLS |
| `ws` | VMess-WS (plain) | `[port] [uuid] [/path]` | Ideal backend for CF Argo |
| `vless-ws` / `vw` | VLESS-WS (plain) | `[port] [uuid] [/path]` | Ideal backend for CF Argo |
| `wss` / `vws` / `tws` | VMess/VLESS/Trojan-WS-TLS | `<domain> [uuid] [/path]` | Auto-installs Caddy TLS |
| `socks` | Socks5 | `[port] [user] [pass]` | Local/upstream relay |

## Post-Install Management Commands (Non-Interactive)

```bash
# Add additional protocols after install
why666 ai deploy --protocols "snell:20006,hy2:20443" --json

# Enable or reconfigure Cloudflare Argo tunnel
why666 argo quick vmess auto http2
why666 argo quick vless auto quic
why666 argo fixed argo.example.com "eyJhIjoi..." vmess auto http2
why666 argo proto quic    # switch HTTP2 (TCP) <-> QUIC (UDP)
why666 argo info
why666 argo del

# Export complete inventory & share links as JSON
why666 ai json

# Health check & sing-box config validation
why666 ai doctor --json

# Single config operations
why666 ls
why666 add snell
why666 add naive proxy.example.com 443
why666 del <config-filename-or-keyword>
why666 update core
why666 bbr
```

## Expected JSON Output Schema (`why666 ai json`)

```json
{
  "ok": true,
  "meta": {
    "tool": "why666",
    "script_version": "v1.0.0",
    "sing_box_version": "1.14.4",
    "server_ip": "1.2.3.4",
    "arch": "amd64",
    "os": "Ubuntu 24.04 LTS",
    "services": { "sing_box": true, "caddy": false, "argo": true }
  },
  "nodes": [
    {
      "name": "Snell-12345.json",
      "protocol": "snell",
      "variant": "snell",
      "address": "1.2.3.4",
      "port": 12345,
      "url": "snell://...",
      "urls": [{ "label": "Nekobox/sing-box", "url": "snell://..." }],
      "params": { "password": "...", "snell_version": "6", "snell_mode": "default", "surge_line": "..." }
    }
  ],
  "argo": {
    "enabled": true,
    "running": true,
    "mode": "quick",
    "protocol": "http2",
    "domain": "xxxx.trycloudflare.com",
    "backend": "VMess-WS-12346.json",
    "urls": { "tls_443": "vmess://...", "plain_80": "vmess://..." }
  },
  "share_links": ["..."]
}
```

## Troubleshooting Checklist

- **Service failed to start**: Run `why666 ai doctor --json` and inspect `config_check_output`. Also check `journalctl -u why666 -n 50 --no-pager` (or `/var/log/why666/error.log` on Alpine).
- **NaiveProxy ACME cert fails**: Ensure DNS A/AAAA points directly to the VPS (Cloudflare Proxy OFF) and port `80` or `443` is not occupied; or pass custom cert paths `naive:domain:port:user:pass:/path/cert.crt:/path/priv.key`.
- **Argo quick tunnel domain empty**: Wait 5-10 seconds and check `why666 argo log` or switch transport with `why666 argo proto quic` (some VPS networks block HTTP2/QUIC selectively).
- **Firewall blocking ports**: Check `ufw status` / `firewall-cmd --list-ports` / cloud security groups for TCP & UDP ports (Hysteria2, TUIC, Naive H3 require UDP).
