# Import existing configs from sing-box / xray / v2ray
is_sb_legacy_conf=/etc/sing-box/conf
is_xray_conf=/etc/xray/conf
is_v2ray_conf=/etc/v2ray/conf

imported_count=0

if [[ -d $is_sb_legacy_conf ]]; then
    for f in "$is_sb_legacy_conf"/*.json; do
        [[ -f $f ]] || continue
        base=$(basename "$f")
        if [[ ! -f $is_conf_dir/$base ]]; then
            if [[ -x $is_core_bin ]] && ! "$is_core_bin" check -c "$f" &>/dev/null; then
                warn "跳过不兼容当前 sing-box 版本的旧配置: $base"
                continue
            fi
            cp -f "$f" "$is_conf_dir/$base"
            chmod 600 "$is_conf_dir/$base"
            msg "已导入 sing-box 配置: $(_green "$base")"
            ((imported_count++))
        fi
    done
fi

in_xray_conf() {
    local f=$1
    local proto orig_port tpass ssm ssp dport daddr suser spass sec ttype wpath whost hpath hhost sni pbk pvk
    proto=$(jq -r '.inbounds[0].protocol // empty' "$f" 2>/dev/null) || return

    reset_config_vars
    is_dont_auto_exit=1
    is_dont_test_host=1
    is_dont_show_info=1
    is_skip_restart=1

    orig_port=$(jq -r '.inbounds[0].port // empty' "$f")
    uuid=$(jq -r '.inbounds[0].settings.clients[0].id // empty' "$f")
    tpass=$(jq -r '.inbounds[0].settings.clients[0].password // empty' "$f")
    ssm=$(jq -r '.inbounds[0].settings.method // empty' "$f")
    ssp=$(jq -r '.inbounds[0].settings.password // empty' "$f")
    dport=$(jq -r '.inbounds[0].settings.port // empty' "$f")
    daddr=$(jq -r '.inbounds[0].settings.address // empty' "$f")
    suser=$(jq -r '.inbounds[0].settings.accounts[0].user // empty' "$f")
    spass=$(jq -r '.inbounds[0].settings.accounts[0].pass // empty' "$f")
    net=$(jq -r '.inbounds[0].streamSettings.network // empty' "$f")
    sec=$(jq -r '.inbounds[0].streamSettings.security // empty' "$f")
    ttype=$(jq -r '.inbounds[0].streamSettings.tcpSettings.header.type // empty' "$f")
    wpath=$(jq -r '.inbounds[0].streamSettings.wsSettings.path // empty' "$f")
    whost=$(jq -r '.inbounds[0].streamSettings.wsSettings.headers.Host // empty' "$f")
    hpath=$(jq -r '.inbounds[0].streamSettings.httpSettings.path // empty' "$f")
    hhost=$(jq -r '.inbounds[0].streamSettings.httpSettings.host[0] // empty' "$f")
    sni=$(jq -r '.inbounds[0].streamSettings.realitySettings.serverNames[0] // empty' "$f")
    pbk=$(jq -r '.inbounds[0].streamSettings.realitySettings.publicKey // empty' "$f")
    pvk=$(jq -r '.inbounds[0].streamSettings.realitySettings.privateKey // empty' "$f")

    if [[ $orig_port && $(is_test port "$orig_port") && ! $(is_test port_used "$orig_port") ]]; then
        port=$orig_port
    fi
    path="${wpath}${hpath}"
    host="${whost}${hhost}"
    [[ ! $uuid ]] && uuid=$tpass
    is_servername=$sni
    is_public_key=$pbk
    is_private_key=$pvk
    ss_method=$ssm
    ss_password=$ssp
    door_port=$dport
    door_addr=$daddr
    is_socks_user=$suser
    is_socks_pass=$spass

    if [[ $host ]]; then
        add "${proto}-${net}-tls"
    else
        case $proto in
        vmess | vless)
            [[ $ttype == "http" ]] && net=http
            [[ $sec == "reality" ]] && net=reality
            [[ $proto == "vless" && $net == "ws" ]] && net=vless-ws
            add "$net"
            ;;
        dokodemo-door) add door ;;
        *socks*) add socks ;;
        shadowsocks) add ss ;;
        *)
            msg "跳过不支持导入的配置: $f"
            return
            ;;
        esac
    fi
    msg "已转换导入: $(_green "$f")"
    ((imported_count++))
}

for dir in "$is_xray_conf" "$is_v2ray_conf"; do
    [[ -d $dir ]] || continue
    for f in "$dir"/*.json; do
        [[ -f $f ]] || continue
        [[ $(basename "$f") =~ (kcp|grpc|dynamic|quic) ]] && continue
        in_xray_conf "$f"
    done
done

is_dont_auto_exit=
is_dont_test_host=
is_dont_show_info=
is_skip_restart=

if [[ $imported_count -gt 0 ]]; then
    manage restart &
    msg "\n$(_green "导入完成, 共导入 ${imported_count} 个配置.")\n"
else
    err "没有找到可导入的配置 (/etc/sing-box/conf, /etc/xray/conf, /etc/v2ray/conf)."
fi
