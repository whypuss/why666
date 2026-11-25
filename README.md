# why666

新一代自研 `sing-box` 多协议一键安装与管理脚本，主打极速多配置并行、现代代理协议全覆盖、Cloudflare Argo 一键隧道与 AI Agent 无交互部署。

**核心特性：**
- **极速多配置并行架构**：基于 `/etc/why666/conf/*.json` 独立多配置管理，秒级增删改查、Caddy 自动 TLS、完整兼容 `systemd` 与 `OpenRC`（Ubuntu / Debian / CentOS / Rocky / SUSE / Alpine，`amd64` / `arm64`），提供主命令 `why666` 与短命令 `yy`。
- **现代代理协议全栈原生支持**（由官方 `sing-box >= 1.14` 单核心驱动）：
  - **NaiveProxy**（支持 `naive` / `native` / `nv` 别名，TCP HTTP/2 + UDP HTTP/3 QUIC BBR，支持 sing-box 1.14 内置 ACME 自动签发或本地证书，输出 V2rayN/Karing/Nekobox/Shadowrocket 四种分享链接）
  - **Snell v6 / v5**（原生支持 Snell v6 流量整形 `default` / `unshaped` / `unsafe-raw`，同步输出 Nekobox/sing-box 链接、Shadowrocket 链接与 Surge 配置行）
  - **AnyTLS / AnyTLS-REALITY**（支持自签、ACME 域名证书与 REALITY 组合）
  - **VLESS-REALITY / Hysteria2 / TUIC / Shadowsocks-2022 / Trojan / VMess / VLESS-WS / Socks5 / Direct**
- **一键 Cloudflare Argo 隧道**：内置 `why666 argo`，支持 **临时隧道（免域名）** 与 **固定隧道（Token）**、自动拉起/绑定 VMess-WS 或 VLESS-WS 后端、一键切换 `http2 (TCP)` / `quic (UDP)`、自动输出 443 TLS + 80 无 TLS 优选节点。
- **AI 原生部署方式**：内置 `SKILL.md`、`llms.txt`、`--non-interactive`、`--json` 结构化导出、`why666 ai deploy` 声明式部署、`why666 ai doctor` 体检与 [在线完整使用说明书与命令生成器 (Cloudflare Pages)](https://whycat666.pages.dev/)。

---

## 一键安装

### 1. 标准交互安装（默认安装 AnyTLS）

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/whypuss/why666/main/install.sh)
```
或使用 `wget`：
```bash
bash <(wget -qO- https://raw.githubusercontent.com/whypuss/why666/main/install.sh)
```

安装完成后运行 `why666` 或 `yy` 即可呼出交互式菜单。

### 2. AI 部署方式（无交互 + 批量协议 + Argo + JSON 输出）

#### 方式一：让 AI Agent 自动帮你部署（推荐）
把本项目链接或以下一句话发给 **Claude Code / Antigravity / OpenClaw / Codex / Cursor** 等具备 SSH 工具的 AI Agent：

> 请阅读 https://raw.githubusercontent.com/whypuss/why666/main/SKILL.md ，登录我的服务器用 why666 无交互部署 VLESS-REALITY、Hysteria2、Snell v6 和 CF Argo 临时隧道，开启 BBR，校验通过后把节点链接发给我。

也可以在已安装服务器上运行 `why666 ai prompt` 获取完整提示词模板。

#### 方式二：一条命令无交互全自动部署（输出结构化 JSON）

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/whypuss/why666/main/install.sh) \
  --non-interactive \
  --protocols "reality,hy2,snell,anyreality" \
  --argo quick \
  --bbr \
  --json
```

含域名部署 NaiveProxy + CF Argo 固定隧道示例：
```bash
bash <(curl -fsSL https://raw.githubusercontent.com/whypuss/why666/main/install.sh) \
  --non-interactive \
  --protocols "reality,snell,naive:proxy.example.com:443" \
  --argo fixed \
  --argo-domain "argo.example.com" \
  --argo-token "你的CF_Tunnel_Token" \
  --bbr \
  --json
```

#### 方式三：环境变量单行模式

```bash
WHY666_PROTOCOLS="reality,hy2,snell" WHY666_ARGO="quick" WHY666_BBR=1 WHY666_JSON=1 \
  bash <(curl -fsSL https://raw.githubusercontent.com/whypuss/why666/main/install.sh)
```

---

## 常用快捷命令

### 协议管理

```bash
why666                           # 打开交互主菜单 (短命令: yy)
why666 add reality               # 一键添加 VLESS-REALITY
why666 add hy2                   # 一键添加 Hysteria2
why666 add tuic                  # 一键添加 TUIC v5
why666 add anytls                # 一键添加 AnyTLS (支持可选第3参域名启用ACME)
why666 add anyreality            # 一键添加 AnyTLS-REALITY
why666 add snell                 # 一键添加 Snell v6 (支持 why666 add snell [port] [psk] [6|5] [mode])
why666 add naive proxy.example.com 443   # 一键添加 NaiveProxy (也兼容 alias: native / nv)
why666 add ss                    # 一键添加 Shadowsocks 2022
why666 add wss proxy.example.com # 一键添加 VMess-WS-TLS (自动 Caddy TLS)
why666 add vws proxy.example.com # 一键添加 VLESS-WS-TLS (自动 Caddy TLS)

why666 ls                        # 列出所有节点与 Argo 状态
why666 info [名称]               # 查看节点详情与分享链接
why666 url [名称]                # 仅显示分享链接
why666 qr [名称]                 # 终端输出二维码
why666 change [名称] port auto   # 随机更换端口
why666 del [名称]                # 删除单个配置
```

### Cloudflare Argo 一键隧道

```bash
why666 argo                                        # 打开 CF Argo 管理菜单
why666 argo quick                                  # 一键开启免域名临时隧道 (自动创建/绑定 VMess-WS)
why666 argo quick vless auto quic                  # 临时隧道 + VLESS-WS 后端 + QUIC(UDP) 模式
why666 argo fixed argo.example.com <TOKEN> vmess   # 一键开启固定隧道
why666 argo info                                   # 查看 Argo 域名与 443/80 优选节点链接
why666 argo proto                                  # 一键切换 HTTP2 (TCP) <-> QUIC (UDP)
why666 argo update                                 # 更新 cloudflared 内核
why666 argo del                                    # 关闭并删除 Argo 隧道
```

### AI 工具与系统运维

```bash
why666 ai json                   # 导出全部节点与 Argo 为结构化 JSON
why666 ai deploy --protocols "snell,hy2" --json    # 已安装后声明式追加协议
why666 ai doctor [--json]        # 一键校验 sing-box 配置与全服务健康度
why666 ai prompt                 # 打印 AI Agent 代部署提示词

why666 status                    # 查看 sing-box / Caddy / Argo 状态
why666 update core               # 更新 sing-box 内核
why666 update sh                 # 更新 why666 脚本
why666 bbr                       # 一键开启 BBR + fq
why666 dns cf                    # 配置 sing-box DNS
why666 import                    # 导入已有 sing-box / xray / v2ray 配置
why666 uninstall                 # 完整卸载
```

---

## 支持协议总览

| 协议 | 命令简写 | 特点与说明 |
|---|---|---|
| AnyTLS | `anytls` | **默认推荐**，自签 TLS 或内置 ACME 域名证书 |
| VLESS-REALITY | `reality` / `r` | Vision 流控，无需域名和证书 |
| VLESS-HTTP2-REALITY | `rh2` | HTTP/2 + REALITY |
| NaiveProxy | `naive` / `native` / `nv` | 原生 H2 + H3/QUIC (BBR)，需已解析域名以自动申请受信任 TLS 证书 |
| Snell v6 / v5 | `snell` / `snell5` / `sn` | 原生 Snell v6 (支持 `default`/`unshaped`/`unsafe-raw`，PSK 需 12-255 字节) |
| AnyTLS-REALITY | `anyreality` / `ar` | AnyTLS + REALITY 组合，无需域名 |
| Hysteria2 | `hy2` / `hy` | QUIC 高速 UDP 协议，自动输出 `pinSHA256` 指纹 |
| TUIC v5 | `tuic` | QUIC + BBR |
| Shadowsocks 2022 | `ss` / `ss2022` | 默认 `2022-blake3-*` 算法 |
| Trojan | `trojan` | 标准 Trojan TLS |
| VMess-WS / VLESS-WS | `ws` / `vless-ws` (`vw`) | 纯 WS 入站，专为 CF Argo / 80 CDN 打造 |
| VMess/VLESS/Trojan-*-TLS | `wss`/`h2`/`hu`/`vws`/`vh2`/`vhu`/`tws`/`th2`/`thu` | 自动安装配置 Caddy TLS + 伪装站 |
| VMess-(TCP/HTTP/QUIC) | `tcp` / `http` / `quic` | 传统传输协议 |
| Socks5 / Direct | `socks` / `door` | 代理中转与端口转发 |

---

## 核心依赖组件

- [SagerNet/sing-box](https://github.com/SagerNet/sing-box) — 通用代理核心
- [cloudflare/cloudflared](https://github.com/cloudflare/cloudflared) — Cloudflare Tunnel 客户端
- [caddyserver/caddy](https://github.com/caddyserver/caddy) — 自动化 HTTPS 反向代理

## License

MIT License
