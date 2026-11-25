#!/bin/bash
# AI-Native Deployment, Structured JSON Export & Diagnostics for why666

ai_export_json() {
    local _prev_quiet=$is_quiet
    local _prev_dont_show=$is_dont_show_info
    local _prev_dont_exit=$is_dont_auto_exit
    is_quiet=1
    is_dont_show_info=1
    is_dont_auto_exit=1

    get_ip

    local sb_running=false caddy_running=false argo_running=false
    _is_svc_running "$is_app" "$is_core_bin" && sb_running=true
    [[ $is_caddy ]] && _is_svc_running caddy "$is_caddy_bin" && caddy_running=true
    [[ -x $is_argo_bin ]] && _is_svc_running "$is_argo_service_name" "$is_argo_bin" && argo_running=true

    local nodes_json="[]"
    local share_links_json="[]"
    local f fname

    for f in "$is_conf_dir"/*.json; do
        [[ -f $f ]] || continue
        fname=$(basename "$f")
        reset_config_vars
        is_config_file=$fname
        get info "$fname" >/dev/null 2>&1 || continue
        info >/dev/null 2>&1 || continue

        local urls_arr="[]"
        if [[ ${#is_extra_urls[@]} -gt 0 ]]; then
            local item lbl val
            for item in "${is_extra_urls[@]}"; do
                lbl=${item%%|*}
                val=${item#*|}
                urls_arr=$(jq --arg l "$lbl" --arg u "$val" '. + [{label:$l,url:$u}]' <<<"$urls_arr")
                share_links_json=$(jq --arg u "$val" '. + [$u]' <<<"$share_links_json")
            done
        elif [[ $is_url ]]; then
            urls_arr=$(jq -n --arg u "$is_url" '[{label:"default",url:$u}]')
            share_links_json=$(jq --arg u "$is_url" '. + [$u]' <<<"$share_links_json")
        fi

        local listen_p=${port:-0}
        [[ $host && $is_https_port ]] && listen_p=$is_https_port

        local node_obj
        node_obj=$(jq -n \
            --arg name "$fname" \
            --arg proto "$is_protocol" \
            --arg net "$net" \
            --arg addr "${is_raw_addr:-${is_addr:-$ip}}" \
            --argjson port "${listen_p:-0}" \
            --arg uuid "${uuid:-}" \
            --arg user "${is_naive_user:-${is_socks_user:-}}" \
            --arg pass "${password:-${ss_password:-}}" \
            --arg method "${ss_method:-}" \
            --arg sni "${is_servername:-${is_naive_domain:-${host:-}}}" \
            --arg pbk "${is_public_key:-}" \
            --arg sid "${is_short_id:-}" \
            --arg path "${path:-}" \
            --arg snell_ver "${is_snell_ver:-}" \
            --arg snell_mode "${is_snell_mode:-}" \
            --arg surge "${is_surge_line:-}" \
            --arg primary_url "${is_url:-}" \
            --argjson urls "$urls_arr" \
            '{
                name: $name,
                protocol: $proto,
                variant: $net,
                address: $addr,
                port: $port,
                url: $primary_url,
                urls: $urls,
                params: ({
                    uuid: $uuid,
                    username: $user,
                    password: $pass,
                    method: $method,
                    sni: $sni,
                    public_key: $pbk,
                    short_id: $sid,
                    path: $path,
                    snell_version: $snell_ver,
                    snell_mode: $snell_mode,
                    surge_line: $surge
                } | with_entries(select(.value != "")))
            }')
        nodes_json=$(jq --argjson n "$node_obj" '. + [$n]' <<<"$nodes_json")
    done

    local argo_json="null"
    if [[ -f $is_argo_conf ]]; then
        load argo.sh
        argo_build_links >/dev/null 2>&1 || true
        argo_json=$(jq -n \
            --argjson running "$argo_running" \
            --arg mode "${argo_cur_mode:-$(jq -r '.mode' "$is_argo_conf")}" \
            --arg proto "${argo_cur_proto:-$(jq -r '.protocol' "$is_argo_conf")}" \
            --arg domain "${argo_cur_domain:-$(jq -r '.domain' "$is_argo_conf")}" \
            --arg backend "${argo_cur_bf:-$(jq -r '.backend_config' "$is_argo_conf")}" \
            --arg tls_url "${argo_link_tls:-}" \
            --arg plain_url "${argo_link_plain:-}" \
            '{
                enabled: true,
                running: $running,
                mode: $mode,
                protocol: $proto,
                domain: $domain,
                backend: $backend,
                urls: {
                    tls_443: $tls_url,
                    plain_80: $plain_url
                }
            }')
        [[ $argo_link_tls ]] && share_links_json=$(jq --arg u "$argo_link_tls" '. + [$u]' <<<"$share_links_json")
        [[ $argo_link_plain ]] && share_links_json=$(jq --arg u "$argo_link_plain" '. + [$u]' <<<"$share_links_json")
    fi

    local os_pretty
    os_pretty=$(grep -m1 '^PRETTY_NAME=' /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"')

    is_quiet=$_prev_quiet
    is_dont_show_info=$_prev_dont_show
    is_dont_auto_exit=$_prev_dont_exit

    jq -n \
        --arg tool "$is_app" \
        --arg ver "$is_sh_ver" \
        --arg core_ver "${is_core_ver:-}" \
        --arg ip "${ip:-}" \
        --arg arch "$is_arch" \
        --arg os "${os_pretty:-linux}" \
        --argjson sb_ok "$sb_running" \
        --argjson caddy_ok "$caddy_running" \
        --argjson argo_ok "$argo_running" \
        --argjson nodes "$nodes_json" \
        --argjson argo "$argo_json" \
        --argjson links "$share_links_json" \
        '{
            ok: true,
            meta: {
                tool: $tool,
                script_version: $ver,
                sing_box_version: $core_ver,
                server_ip: $ip,
                arch: $arch,
                os: $os,
                services: {
                    sing_box: $sb_ok,
                    caddy: $caddy_ok,
                    argo: $argo_ok
                }
            },
            nodes: $nodes,
            argo: $argo,
            share_links: $links
        }'
}

ai_deploy() {
    local protocols_csv="" argo_mode="" argo_domain="" argo_token=""
    local argo_proto="http2" argo_backend="vmess"
    local do_bbr=0 do_json=0

    is_non_interactive=1

    while [[ $# -gt 0 ]]; do
        case $1 in
        --protocols)
            protocols_csv=$2
            shift 2
            ;;
        --argo)
            argo_mode=$2
            shift 2
            ;;
        --argo-domain)
            argo_domain=$2
            shift 2
            ;;
        --argo-token)
            argo_token=$2
            shift 2
            ;;
        --argo-proto)
            argo_proto=$2
            shift 2
            ;;
        --argo-backend)
            argo_backend=$2
            shift 2
            ;;
        --bbr)
            do_bbr=1
            shift 1
            ;;
        --skip-dns-check)
            is_skip_dns_check=1
            shift 1
            ;;
        --json)
            do_json=1
            is_quiet=1
            is_json_out=1
            shift 1
            ;;
        *)
            err "ai deploy 未知参数: $1"
            ;;
        esac
    done

    if [[ $do_bbr -eq 1 ]]; then
        load bbr.sh
        if [[ $do_json -eq 1 ]]; then
            _try_enable_bbr >/dev/null || true
        else
            _try_enable_bbr || true
        fi
    fi

    if [[ $protocols_csv ]]; then
        is_skip_restart=1
        local specs=()
        IFS=',' read -r -a specs <<<"$protocols_csv"
        local spec
        for spec in "${specs[@]}"; do
            spec=$(echo "$spec" | xargs)
            [[ ! $spec ]] && continue
            # Support syntax: proto or proto:arg1:arg2:...
            local parts=()
            IFS=':' read -r -a parts <<<"$spec"
            reset_config_vars
            is_dont_show_info=1
            if [[ $do_json -eq 1 ]]; then
                add "${parts[@]}" >/dev/null
            else
                add "${parts[@]}"
            fi
        done
        is_skip_restart=
        is_dont_show_info=
        manage restart </dev/null &>/dev/null
        sleep 1
    fi

    if [[ $argo_mode ]]; then
        load argo.sh
        case ${argo_mode,,} in
        quick | tmp | temp)
            if [[ $do_json -eq 1 ]]; then
                argo_setup_quick "$argo_backend" auto "$argo_proto" >/dev/null
            else
                argo_setup_quick "$argo_backend" auto "$argo_proto"
            fi
            ;;
        fixed | token)
            if [[ $do_json -eq 1 ]]; then
                argo_setup_fixed "$argo_domain" "$argo_token" "$argo_backend" auto "$argo_proto" >/dev/null
            else
                argo_setup_fixed "$argo_domain" "$argo_token" "$argo_backend" auto "$argo_proto"
            fi
            ;;
        *)
            err "不支持的 --argo 模式: $argo_mode (仅支持 quick 或 fixed)"
            ;;
        esac
    fi

    if [[ $do_json -eq 1 ]]; then
        ai_export_json
    else
        is_quiet=
        msg "\n$(_green "AI 自动化部署完成!") 当前全部配置如下:\n"
        local f
        for f in "$is_conf_dir"/*.json; do
            [[ -f $f ]] || continue
            reset_config_vars
            info "$(basename "$f")"
        done
        [[ -f $is_argo_conf ]] && {
            load argo.sh
            argo_info
        }
    fi
}

ai_doctor() {
    local as_json=0
    [[ $1 == "--json" ]] && as_json=1

    local check_out="" check_ok=true
    if ! check_out=$("$is_core_bin" check -c "$is_config_json" -C "$is_conf_dir" 2>&1); then
        check_ok=false
    fi
    local sb_ok=false caddy_ok=false argo_ok=false
    _is_svc_running "$is_app" "$is_core_bin" && sb_ok=true
    [[ $is_caddy ]] && _is_svc_running caddy "$is_caddy_bin" && caddy_ok=true
    if [[ -x $is_argo_bin ]] && _is_svc_running "$is_argo_service_name" "$is_argo_bin"; then
        argo_ok=true
        if [[ -f $is_argo_conf ]]; then
            local _abf
            _abf=$(jq -r '.backend_config // empty' "$is_argo_conf" 2>/dev/null)
            [[ $_abf && ! -f "$is_conf_dir/$_abf" ]] && argo_ok=false
        fi
    fi

    local bbr_cc
    bbr_cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "unknown")
    local conf_count
    conf_count=$(ls "$is_conf_dir"/*.json 2>/dev/null | wc -l | tr -d ' ')

    if [[ $as_json -eq 1 ]]; then
        jq -n \
            --arg ver "$is_sh_ver" \
            --arg core "${is_core_ver:-}" \
            --arg arch "$is_arch" \
            --arg bbr "$bbr_cc" \
            --argjson conf_count "${conf_count:-0}" \
            --argjson cfg_ok "$check_ok" \
            --arg cfg_msg "$check_out" \
            --argjson sb_ok "$sb_ok" \
            --argjson caddy_ok "$caddy_ok" \
            --argjson argo_ok "$argo_ok" \
            '{
                ok: ($cfg_ok and $sb_ok),
                script_version: $ver,
                sing_box_version: $core,
                arch: $arch,
                tcp_congestion_control: $bbr,
                config_count: $conf_count,
                config_valid: $cfg_ok,
                config_check_output: $cfg_msg,
                services: {sing_box: $sb_ok, caddy: $caddy_ok, argo: $argo_ok}
            }'
    else
        msg "\n------------- why666 环境与配置体检 -------------"
        msg "脚本版本:\t\t$is_sh_ver"
        msg "sing-box 版本:\t\t${is_core_ver:-unknown} ($is_arch)"
        msg "TCP 拥塞控制:\t\t$bbr_cc"
        msg "已配置节点数:\t\t$conf_count"
        msg "配置校验 (check):\t$([[ $check_ok == true ]] && _green PASS || _red FAIL)"
        [[ $check_ok == false ]] && _red "$check_out"
        msg "sing-box 服务:\t\t$([[ $sb_ok == true ]] && _green running || _red stopped)"
        msg "Caddy 服务:\t\t$([[ $caddy_ok == true ]] && _green running || _yellow inactive)"
        msg "CF Argo 服务:\t\t$([[ $argo_ok == true ]] && _green running || _yellow inactive)"
        msg "------------------------------------------------\n"
    fi
}

ai_prompt() {
    cat <<EOF

================ 复制下方提示词发给任意 AI Agent (Claude / Antigravity / OpenClaw / Codex) ================

请通过 SSH 登录我的 Linux VPS，使用开源项目 https://github.com/${is_sh_repo} （先阅读其 SKILL.md）为我完成无交互代理部署：
1. 安装 why666 (sing-box 最新版)，并启用 BBR；
2. 同时部署以下协议节点（可按需增删）：
   - VLESS-REALITY (reality)
   - Hysteria2 (hy2)
   - Snell v6 (snell)
   - AnyTLS-REALITY (anyreality)
   - 如我有域名，请额外部署 NaiveProxy (naive:你的域名:443)
3. 如需抗封锁 CDN 通道，同时启用 Cloudflare Argo 临时隧道 (--argo quick) 或固定隧道 (--argo fixed --argo-domain 域名 --argo-token Token)；
4. 全程使用非交互参数 (--non-interactive --json)，完成后执行 \`why666 ai doctor --json\` 验证配置通过且服务运行正常，最后以清晰的节点列表和可直接导入客户端的分享链接交付给我。

一键参考命令（可直接给 AI 执行）：
bash <(curl -fsSL https://raw.githubusercontent.com/${is_sh_repo}/main/install.sh) \\
  --non-interactive --protocols "reality,hy2,snell,anyreality" --argo quick --bbr --json

=============================================================================================================

EOF
}

ai_menu() {
    msg "\n------------- AI 部署与结构化导出 -------------"
    local menu_opts=(
        "导出全部节点为 JSON (供 AI Agent / 自动化解析)"
        "运行 AI 体检诊断 (why666 ai doctor)"
        "查看 AI Agent 一键代部署提示词模板"
        "查看 SKILL.md / llms.txt 接入地址"
    )
    is_tmp_list=("${menu_opts[@]}")
    ask list is_ai_pick null ""
    case $REPLY in
    1) ai_export_json ;;
    2) ai_doctor ;;
    3) ai_prompt ;;
    4)
        msg "\nSKILL.md: $(msg_ul "https://raw.githubusercontent.com/${is_sh_repo}/main/SKILL.md")"
        msg "llms.txt: $(msg_ul "https://raw.githubusercontent.com/${is_sh_repo}/main/llms.txt")"
        msg "一键命令生成器: $(msg_ul "https://${author}.github.io/${project}/")\n"
        ;;
    esac
}

ai_main() {
    case ${1,,} in
    "" | menu)
        ai_menu
        ;;
    json | export)
        ai_export_json
        ;;
    deploy)
        ai_deploy "${@:2}"
        ;;
    doctor | check)
        ai_doctor "${@:2}"
        ;;
    prompt)
        ai_prompt
        ;;
    *)
        err "无法识别 ai 子命令 ($1), 用法: $is_app ai [json | deploy | doctor | prompt]"
        ;;
    esac
}
