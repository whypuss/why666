show_help() {
    case $1 in
    api | x25519 | tls | run | uuid | version)
        "$is_core_bin" help "$1" "${@:2}"
        ;;
    *)
        [[ $1 ]] && warn "未知选项 '$1'"
        msg "$is_app script $is_sh_ver (sing-box) by $author"
        msg "Usage: $is_app [options]... [args]... (短命令: yy)"
        msg
        help_info=(
            "基本:"
            "   v, version                                      显示当前版本"
            "   ip                                              返回当前主机的 IP"
            "   pbk                                             同等于 sing-box generate reality-keypair"
            "   get-port                                        返回一个可用的端口"
            "   ss2022                                          返回一个可用于 Shadowsocks 2022 的密码\n"
            "一般:"
            "   a, add [protocol] [args... | auto]              添加配置 (支持 reality/hy2/tuic/anytls/anyreality/naive/native/snell/ss/vmess/vless/trojan/socks)"
            "   c, change [name] [option] [args... | auto]      更改配置"
            "   d, del [name]                                   删除配置**"
            "   i, info [name]                                  查看配置"
            "   ls, list                                        列出所有配置与 Argo 状态"
            "   qr [name]                                       二维码信息"
            "   url [name]                                      URL 信息"
            "   log [level|none|del]                            查看或设置日志\n"
            "CF Argo 隧道:"
            "   argo                                            进入 CF Argo 交互管理菜单"
            "   argo quick [vmess|vless] [port|auto] [http2|quic] 一键开启临时隧道 (免域名)"
            "   argo fixed <domain> <token> [vmess|vless]       一键开启固定隧道"
            "   argo info | status | proto | restart | update | del  查看/切换TCP-UDP/管理 Argo\n"
            "AI 部署与自动化:"
            "   ai json                                         以结构化 JSON 导出所有节点与 Argo 信息"
            "   ai deploy --protocols \"...\" [--argo ...] [--json] 声明式无交互批量部署"
            "   ai doctor [--json]                              环境与 sing-box 配置全面体检"
            "   ai prompt                                       生成 AI Agent 代部署提示词\n"
            "更改快捷方式:"
            "   full [name] [...]                               更改多个参数"
            "   id [name] [uuid | auto]                         更改 UUID"
            "   host [name] [domain]                            更改域名"
            "   port [name] [port | auto]                       更改端口"
            "   path [name] [path | auto]                       更改路径"
            "   passwd [name] [password | auto]                 更改密码 / Snell PSK"
            "   user [name] [username]                          更改用户名 (Naive / Socks)"
            "   key [name] [Private key | auto] [Public key]    更改 REALITY 密钥"
            "   method [name] [method | auto]                   更改 Shadowsocks 加密方式"
            "   sni [name] [ip | domain]                        更改 serverName (SNI)"
            "   new [name] [...]                                更改协议"
            "   web [name] [domain]                             更改伪装网站\n"
            "进阶:"
            "   dns [...]                                       设置 DNS"
            "   dd, ddel [name...]                              删除多个配置**"
            "   fix [name] / fix-all                            修复单个 / 全部配置"
            "   fix-caddyfile / fix-config.json                 修复 Caddyfile / config.json"
            "   import                                          导入已有 sing-box / xray / v2ray 配置\n"
            "管理:"
            "   un, uninstall                                   卸载"
            "   u, update [core | sh | caddy | argo] [ver]      更新内核或脚本"
            "   U, update.sh                                    更新脚本"
            "   s, status                                       查看所有服务运行状态"
            "   start, stop, restart [caddy | argo]             启动, 停止, 重启"
            "   t, test                                         测试运行"
            "   reinstall                                       重装脚本\n"
            "测试与其他:"
            "   debug [name]                                    显示配置 JSON 明细"
            "   gen [...]                                       仅输出生成的 JSON, 不落盘"
            "   no-auto-tls [...]                               添加 *TLS/Naive 协议但禁止自动配置 TLS"
            "   bbr                                             一键启用 BBR + fq"
            "   bin [...]                                       直接透传 sing-box 原生命令"
            "   h, help                                         显示此帮助界面\n"
        )
        for v in "${help_info[@]}"; do
            msg "$v"
        done
        msg "谨慎使用 del, ddel, 此选项会直接删除配置无需确认."
        msg "GitHub: $(msg_ul "https://github.com/${is_sh_repo}")"
        ;;
    esac
}

about() {
    msg
    msg "项目名称: $is_app (基于 sing-box 的增强一键管理脚本)"
    msg "GitHub:   $(msg_ul "https://github.com/${is_sh_repo}")"
    msg "AI Skill: $(msg_ul "https://raw.githubusercontent.com/${is_sh_repo}/main/SKILL.md")"
    msg "Core:     $(msg_ul "https://github.com/${is_core_repo}")"
    msg
}
