#!/bin/bash
# Cloudflare Argo Tunnel integration for why666 (Quick & Fixed tunnels)

argo_ensure_bin() {
    mkdir -p "$is_argo_dir" "$is_log_dir"
    if [[ ! -x $is_argo_bin ]]; then
        msg "$(_yellow "未检测到 cloudflared, 正在下载最新版本...")"
        load download.sh
        download argo
        is_argo_installed=1
        is_argo_ver=$("$is_argo_bin" version 2>/dev/null | awk '{print $3}' | head -n1)
        msg "$(_green "cloudflared 下载完成 ($is_argo_ver)")"
    fi
}

# Find or create a local plain WS inbound (VMess-WS or VLESS-WS) for Argo backend
argo_prepare_backend() {
    local want_type=${1,,}
    local want_port=$2
    [[ ! $want_type || $want_type == "auto" ]] && want_type="vmess"

    local matched_file=""
    local f t net_t has_host
    for f in "$is_conf_dir"/*.json; do
        [[ -f $f ]] || continue
        t=$(jq -r '.inbounds[0].type // empty' "$f" 2>/dev/null)
        net_t=$(jq -r '.inbounds[0].transport.type // empty' "$f" 2>/dev/null)
        has_host=$(jq -r '.inbounds[0].transport.headers.host // .inbounds[0].transport.host // empty' "$f" 2>/dev/null)
        if [[ $t == "$want_type" && $net_t == "ws" && ! $has_host ]]; then
            if [[ ! $want_port || $want_port == "auto" ]]; then
                matched_file=$(basename "$f")
                break
            else
                local fp
                fp=$(jq -r '.inbounds[0].listen_port // empty' "$f" 2>/dev/null)
                if [[ $fp == "$want_port" ]]; then
                    matched_file=$(basename "$f")
                    break
                fi
            fi
        fi
    done

    if [[ ! $matched_file ]]; then
        local proto_arg="ws"
        [[ $want_type == "vless" ]] && proto_arg="vless-ws"
        msg "$(_yellow "未检测到可用的本地 ${want_type^^}-WS 入站, 自动创建一个供 Argo 转发...")"
        local _prev_quiet=$is_quiet
        local _prev_dont_show=$is_dont_show_info
        is_dont_show_info=1
        reset_config_vars
        if [[ $want_port && $want_port != "auto" ]]; then
            add "$proto_arg" "$want_port"
        else
            add "$proto_arg"
        fi
        matched_file=$is_config_name
        is_quiet=$_prev_quiet
        is_dont_show_info=$_prev_dont_show
    fi

    local bf="$is_conf_dir/$matched_file"
    argo_backend_file=$matched_file
    argo_backend_type=$(jq -r '.inbounds[0].type' "$bf")
    argo_backend_port=$(jq -r '.inbounds[0].listen_port' "$bf")
    argo_backend_uuid=$(jq -r '.inbounds[0].users[0].uuid' "$bf")
    argo_backend_path=$(jq -r '.inbounds[0].transport.path // "/"' "$bf")
}

argo_save_conf() {
    mkdir -m 700 -p "$is_argo_dir"
    (
        umask 077
        jq -n \
            --arg mode "$argo_mode" \
            --arg proto "$argo_proto" \
            --arg bf "$argo_backend_file" \
            --arg bt "$argo_backend_type" \
            --argjson bp "$argo_backend_port" \
            --arg bu "$argo_backend_uuid" \
            --arg bpath "$argo_backend_path" \
            --arg dom "$argo_domain" \
            --arg tok "$argo_token" \
            --arg ip_tls "${argo_cdn_tls:-www.shopify.com}" \
            --arg ip_plain "${argo_cdn_plain:-icook.tw}" \
            '{
                mode: $mode,
                protocol: $proto,
                backend_config: $bf,
                backend_type: $bt,
                backend_port: $bp,
                backend_uuid: $bu,
                backend_path: $bpath,
                domain: $dom,
                token: $tok,
                cdn_ip_tls: $ip_tls,
                cdn_ip_plain: $ip_plain
            }' >"$is_argo_conf"
    )
    chmod 600 "$is_argo_conf"
}

argo_extract_quick_domain() {
    if [[ -f $is_argo_log ]]; then
        grep -aoE 'https://[a-zA-Z0-9-]+\.trycloudflare\.com' "$is_argo_log" 2>/dev/null | tail -n1 | sed 's#^https://##'
    fi
}

argo_build_links() {
    argo_link_tls=""
    argo_link_plain=""
    [[ ! -f $is_argo_conf ]] && return 1

    local mode proto bf bt bp bu bpath dom ip_tls ip_plain tag_proto
    mode=$(jq -r '.mode' "$is_argo_conf")
    proto=$(jq -r '.protocol // "http2"' "$is_argo_conf")
    bf=$(jq -r '.backend_config // empty' "$is_argo_conf")
    bt=$(jq -r '.backend_type' "$is_argo_conf")
    bp=$(jq -r '.backend_port' "$is_argo_conf")
    bu=$(jq -r '.backend_uuid' "$is_argo_conf")
    bpath=$(jq -r '.backend_path' "$is_argo_conf")
    dom=$(jq -r '.domain' "$is_argo_conf")
    ip_tls=$(jq -r '.cdn_ip_tls // "www.shopify.com"' "$is_argo_conf")
    ip_plain=$(jq -r '.cdn_ip_plain // "icook.tw"' "$is_argo_conf")

    # Sync live backend config parameters if backend file exists, or warn if deleted
    if [[ $bf ]]; then
        local bpath_file="$is_conf_dir/$bf"
        if [[ -f $bpath_file ]]; then
            local live_bt live_bp live_bu live_bpath
            live_bt=$(jq -r '.inbounds[0].type // empty' "$bpath_file" 2>/dev/null)
            live_bp=$(jq -r '.inbounds[0].listen_port // empty' "$bpath_file" 2>/dev/null)
            live_bu=$(jq -r '.inbounds[0].users[0].uuid // empty' "$bpath_file" 2>/dev/null)
            live_bpath=$(jq -r '.inbounds[0].transport.path // "/"' "$bpath_file" 2>/dev/null)
            [[ $live_bt ]] && bt=$live_bt
            [[ $live_bp ]] && bp=$live_bp
            [[ $live_bu ]] && bu=$live_bu
            [[ $live_bpath ]] && bpath=$live_bpath
        else
            warn "Argo 绑定的后端节点 ($bf) 已被删除, 请重新执行: $is_app argo $mode"
            return 1
        fi
    fi

    # Refresh quick tunnel domain from live log if changed after reboot
    if [[ $mode == "quick" ]]; then
        local live_dom
        live_dom=$(argo_extract_quick_domain)
        if [[ $live_dom && $live_dom != "$dom" ]]; then
            dom=$live_dom
            (umask 077 && jq --arg d "$dom" '.domain = $d' "$is_argo_conf" >"${is_argo_conf}.tmp" && mv "${is_argo_conf}.tmp" "$is_argo_conf")
            chmod 600 "$is_argo_conf"
        fi
    fi

    argo_cur_domain=$dom
    argo_cur_mode=$mode
    argo_cur_proto=$proto
    argo_cur_bt=$bt
    argo_cur_bp=$bp
    argo_cur_bf=$bf

    [[ ! $dom ]] && return 1

    tag_proto="TCP"
    [[ $proto == "quic" ]] && tag_proto="UDP"
    local host_tag
    host_tag=$(hostname -s 2>/dev/null || echo "why666")

    if [[ $bt == "vmess" ]]; then
        local j_tls j_plain
        j_tls=$(jq -nc \
            --arg ps "why666-vmess-argo-${tag_proto}-${host_tag}-443" \
            --arg add "$ip_tls" --arg port "443" --arg id "$bu" \
            --arg host "$dom" --arg path "$bpath" --arg sni "$dom" \
            '{v:"2",ps:$ps,add:$add,port:$port,id:$id,aid:"0",scy:"auto",net:"ws",type:"none",host:$host,path:$path,tls:"tls",sni:$sni,fp:"chrome"}')
        j_plain=$(jq -nc \
            --arg ps "why666-vmess-argo-${tag_proto}-${host_tag}-80" \
            --arg add "$ip_plain" --arg port "80" --arg id "$bu" \
            --arg host "$dom" --arg path "$bpath" \
            '{v:"2",ps:$ps,add:$add,port:$port,id:$id,aid:"0",scy:"auto",net:"ws",type:"none",host:$host,path:$path,tls:""}')
        argo_link_tls="vmess://$(printf '%s' "$j_tls" | _base64)"
        argo_link_plain="vmess://$(printf '%s' "$j_plain" | _base64)"
    else
        local enc_path
        enc_path=$(jq -rn --arg v "$bpath" '$v|@uri')
        argo_link_tls="vless://${bu}@${ip_tls}:443?encryption=none&security=tls&type=ws&host=${dom}&sni=${dom}&path=${enc_path}&fp=chrome#why666-vless-argo-${tag_proto}-${host_tag}-443"
        argo_link_plain="vless://${bu}@${ip_plain}:80?encryption=none&security=none&type=ws&host=${dom}&path=${enc_path}#why666-vless-argo-${tag_proto}-${host_tag}-80"
    fi
    return 0
}

argo_setup_quick() {
    local backend_type=${1:-vmess}
    local backend_port=${2:-auto}
    local tunnel_proto=${3:-http2}
    [[ $tunnel_proto != "quic" ]] && tunnel_proto="http2"

    argo_ensure_bin
    argo_prepare_backend "$backend_type" "$backend_port"

    argo_mode="quick"
    argo_proto="$tunnel_proto"
    argo_token=""
    argo_domain=""

    # Stop previous argo and clear old log
    manage stop argo &>/dev/null
    rm -f "$is_argo_log"

    load systemd.sh
    install_service argo quick "$argo_proto" "$argo_backend_port" &>/dev/null
    manage start argo &>/dev/null

    msg "$(_yellow "正在申请 Cloudflare Argo 临时隧道 (协议: $argo_proto, 后端: $argo_backend_type:$argo_backend_port)...")"
    local i=0
    while [[ $i -lt 25 ]]; do
        sleep 1
        argo_domain=$(argo_extract_quick_domain)
        [[ $argo_domain ]] && break
        ((i++))
    done

    if [[ ! $argo_domain ]]; then
        warn "等待 trycloudflare.com 临时域名超时, 请检查网络或执行: cat $is_argo_log"
        argo_save_conf
        return 1
    fi

    argo_save_conf
    if [[ ! $is_quiet ]]; then
        argo_info
    fi
    return 0
}

argo_setup_fixed() {
    local domain=$1
    local token=$2
    local backend_type=${3:-vmess}
    local backend_port=${4:-auto}
    local tunnel_proto=${5:-http2}
    [[ $tunnel_proto != "quic" ]] && tunnel_proto="http2"

    [[ ! $domain ]] && {
        [[ $is_non_interactive ]] && err "固定隧道缺少域名参数."
        ask string domain "请输入 Cloudflare Zero Trust 固定隧道域名: "
    }
    [[ ! $token ]] && {
        [[ $is_non_interactive ]] && err "固定隧道缺少 Token 参数."
        ask string token "请输入 Cloudflare Tunnel Token (eyJ...): "
    }

    argo_ensure_bin
    argo_prepare_backend "$backend_type" "$backend_port"

    argo_mode="fixed"
    argo_proto="$tunnel_proto"
    argo_domain="$domain"
    argo_token="$token"

    manage stop argo &>/dev/null
    load systemd.sh
    install_service argo fixed "$argo_proto" "$argo_token" &>/dev/null
    manage start argo &>/dev/null
    sleep 2

    argo_save_conf
    msg "$(_green "CF Argo 固定隧道已配置完成! 请确认在 Cloudflare Zero Trust 后台将 Public Hostname (${argo_domain}) 指向: http://127.0.0.1:${argo_backend_port}")"
    if [[ ! $is_quiet ]]; then
        argo_info
    fi
    return 0
}

argo_info() {
    if [[ ! -f $is_argo_conf ]]; then
        err "尚未配置 CF Argo 隧道, 请运行: $is_app argo quick 或 $is_app argo fixed <domain> <token>"
    fi
    argo_build_links || warn "未能获取 Argo 域名, 请查看日志: $is_argo_log"

    local st
    if _is_svc_running "$is_argo_service_name" "$is_argo_bin"; then
        st=$(_green "running")
    else
        st=$(_red_bg "stopped")
    fi

    msg "\n-------------- CF Argo 隧道信息 -------------"
    msg "状态 (status)\t\t= $st"
    msg "隧道模式 (mode)\t\t= \e[45m${argo_cur_mode}\e[0m"
    msg "传输协议 (protocol)\t= \e[45m${argo_cur_proto}\e[0m"
    msg "后端配置 (backend)\t= \e[45m${argo_cur_bf} (${argo_cur_bt^^} 127.0.0.1:${argo_cur_bp})\e[0m"
    msg "Argo 域名 (domain)\t= \e[45m${argo_cur_domain}\e[0m"
    if [[ $argo_link_tls ]]; then
        msg "------------- 443 TLS 优选节点 (可更换任意 CF 优选 IP/域名) -------------"
        msg "\e[4;45m${argo_link_tls}\e[0m"
        msg "------------- 80 无 TLS 优选节点 (可更换任意 CF 优选 IP/域名) -------------"
        msg "\e[4;44m${argo_link_plain}\e[0m"
    fi
    msg "------------- END -------------\n"
}

argo_switch_proto() {
    [[ ! -f $is_argo_conf ]] && err "尚未配置 CF Argo 隧道."
    local cur new_p
    cur=$(jq -r '.protocol // "http2"' "$is_argo_conf")
    if [[ $1 == "http2" || $1 == "quic" ]]; then
        new_p=$1
    else
        [[ $cur == "http2" ]] && new_p="quic" || new_p="http2"
    fi
    local mode bf bp tok
    mode=$(jq -r '.mode' "$is_argo_conf")
    bf=$(jq -r '.backend_config // empty' "$is_argo_conf")
    bp=$(jq -r '.backend_port' "$is_argo_conf")
    [[ $bf && -f $is_conf_dir/$bf ]] && bp=$(jq -r '.inbounds[0].listen_port // empty' "$is_conf_dir/$bf" 2>/dev/null || echo "$bp")
    tok=$(jq -r '.token // empty' "$is_argo_conf")

    manage stop argo &>/dev/null
    load systemd.sh
    if [[ $mode == "fixed" ]]; then
        (umask 077 && jq --arg p "$new_p" '.protocol = $p' "$is_argo_conf" >"${is_argo_conf}.tmp" && mv "${is_argo_conf}.tmp" "$is_argo_conf")
        chmod 600 "$is_argo_conf"
        install_service argo fixed "$new_p" "$tok" &>/dev/null
        manage start argo &>/dev/null
        sleep 2
    else
        (umask 077 && jq --arg p "$new_p" '.protocol = $p | .domain = ""' "$is_argo_conf" >"${is_argo_conf}.tmp" && mv "${is_argo_conf}.tmp" "$is_argo_conf")
        chmod 600 "$is_argo_conf"
        rm -f "$is_argo_log"
        install_service argo quick "$new_p" "$bp" &>/dev/null
        manage start argo &>/dev/null
        msg "$(_yellow "正在重新申请 Cloudflare Argo 临时隧道 ($new_p)...")"
        local i=0 new_dom=""
        while [[ $i -lt 25 ]]; do
            sleep 1
            new_dom=$(argo_extract_quick_domain)
            [[ $new_dom ]] && break
            ((i++))
        done
        if [[ $new_dom ]]; then
            (umask 077 && jq --arg d "$new_dom" '.domain = $d' "$is_argo_conf" >"${is_argo_conf}.tmp" && mv "${is_argo_conf}.tmp" "$is_argo_conf")
            chmod 600 "$is_argo_conf"
        else
            warn "等待新 trycloudflare.com 临时域名超时, 请稍后执行 $is_app argo info 查看."
        fi
    fi
    msg "\n已切换 CF Argo 隧道传输协议: $(_green "$cur -> $new_p")\n"
    argo_info
}

argo_del() {
    manage stop argo &>/dev/null
    manage disable argo &>/dev/null
    if [[ $is_systemd ]]; then
        rm -f "/lib/systemd/system/${is_argo_service_name}.service"
        systemctl daemon-reload &>/dev/null
    elif [[ $is_openrc ]]; then
        rm -f "/etc/init.d/${is_argo_service_name}"
    fi
    rm -rf "$is_argo_conf" "$is_argo_dir/token" "$is_argo_log"
    msg "\n$(_green "已关闭并移除 CF Argo 隧道配置 (保留本地 sing-box 入站配置).")\n"
}

argo_menu() {
    msg "\n------------- CF Argo 隧道管理 -------------"
    local menu_opts=(
        "一键添加 Argo 临时隧道 (免域名, VMess-WS)"
        "一键添加 Argo 临时隧道 (免域名, VLESS-WS)"
        "一键添加 Argo 固定隧道 (需 CF 域名 + Token)"
        "查看 Argo 隧道状态与节点链接"
        "切换 Argo 传输模式 (HTTP2/TCP <-> QUIC/UDP)"
        "重启 Argo 隧道"
        "更新 cloudflared 内核"
        "关闭并删除 Argo 隧道"
    )
    is_tmp_list=("${menu_opts[@]}")
    ask list is_argo_pick null ""
    case $REPLY in
    1) argo_setup_quick vmess auto http2 ;;
    2) argo_setup_quick vless auto http2 ;;
    3)
        ask string _dom "请输入 CF 固定隧道域名: "
        ask string _tok "请输入 CF Tunnel Token: "
        is_tmp_list=("vmess" "vless")
        ask list _bt null "\n请选择后端协议:\n"
        is_tmp_list=("http2" "quic")
        ask list _pr null "\n请选择隧道传输协议:\n"
        argo_setup_fixed "$_dom" "$_tok" "$_bt" auto "$_pr"
        ;;
    4) argo_info ;;
    5) argo_switch_proto ;;
    6)
        manage restart argo &>/dev/null
        sleep 2
        argo_info
        ;;
    7) update argo ;;
    8) argo_del ;;
    esac
}

argo_main() {
    case ${1,,} in
    "" | menu)
        argo_menu
        ;;
    quick | tmp | temp)
        argo_setup_quick "${2:-vmess}" "${3:-auto}" "${4:-http2}"
        ;;
    fixed | token)
        argo_setup_fixed "$2" "$3" "${4:-vmess}" "${5:-auto}" "${6:-http2}"
        ;;
    i | info | url)
        argo_info
        ;;
    s | status)
        if _is_svc_running "$is_argo_service_name" "$is_argo_bin"; then
            msg "\nCF Argo (${is_argo_ver}): $(_green running)\n"
        else
            msg "\nCF Argo: $(_red_bg stopped)\n"
        fi
        ;;
    proto | mode | switch)
        argo_switch_proto "$2"
        ;;
    start | stop | restart)
        manage "$1" argo &
        msg "\nCF Argo 执行: $(_green "$1")\n"
        ;;
    log)
        if [[ -f $is_argo_log ]]; then
            tail -n 50 "$is_argo_log"
        else
            err "未找到 Argo 日志文件 ($is_argo_log)."
        fi
        ;;
    u | update)
        update argo
        ;;
    d | del | rm | remove)
        argo_del
        ;;
    *)
        err "无法识别 argo 子命令 ($1), 用法: $is_app argo [quick|fixed|info|status|proto|restart|update|del]"
        ;;
    esac
}
