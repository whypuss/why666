#!/bin/bash

protocol_list=(
    AnyTLS
    VLESS-REALITY
    VLESS-HTTP2-REALITY
    Hysteria2
    TUIC
    AnyTLS-REALITY
    Naive
    Snell
    Shadowsocks
    Trojan
    VMess-WS
    VLESS-WS
    VMess-TCP
    VMess-HTTP
    VMess-QUIC
    VMess-H2-TLS
    VMess-WS-TLS
    VLESS-H2-TLS
    VLESS-WS-TLS
    Trojan-H2-TLS
    Trojan-WS-TLS
    VMess-HTTPUpgrade-TLS
    VLESS-HTTPUpgrade-TLS
    Trojan-HTTPUpgrade-TLS
    Socks
    Direct
)

ss_method_list=(
    aes-128-gcm
    aes-256-gcm
    chacha20-ietf-poly1305
    xchacha20-ietf-poly1305
    2022-blake3-aes-128-gcm
    2022-blake3-aes-256-gcm
    2022-blake3-chacha20-poly1305
)

mainmenu=(
    "添加配置"
    "更改配置"
    "查看配置"
    "删除配置"
    "CF Argo 隧道"
    "AI 部署与导出"
    "运行管理"
    "更新"
    "卸载"
    "帮助"
    "其他"
    "关于"
)

info_list=(
    "协议 (protocol)"
    "地址 (address)"
    "端口 (port)"
    "用户ID (id)"
    "传输协议 (network)"
    "伪装类型 (type)"
    "伪装域名 (host)"
    "路径 (path)"
    "传输层安全 (TLS)"
    "应用层协议协商 (Alpn)"
    "密码 (password)"
    "加密方式 (encryption)"
    "链接 (URL)"
    "目标地址 (remote addr)"
    "目标端口 (remote port)"
    "流控 (flow)"
    "SNI (serverName)"
    "指纹 (Fingerprint)"
    "公钥 (Public key)"
    "用户名 (Username)"
    "跳过证书验证 (allowInsecure)"
    "拥塞控制算法 (congestion_control)"
    "Short ID (sid)"
    "Snell 版本 (version)"
    "流量整形 (mode)"
)

change_list=(
    "更改协议"
    "更改端口"
    "更改域名"
    "更改路径"
    "更改密码"
    "更改 UUID"
    "更改加密方式"
    "更改目标地址"
    "更改目标端口"
    "更改密钥"
    "更改 SNI (serverName)"
    "更改伪装网站"
    "更改用户名 (Username)"
)

servername_list=(
    www.apple.com
    www.amazon.com
    www.ebay.com
    www.paypal.com
    www.cloudflare.com
    dash.cloudflare.com
    aws.amazon.com
)

# shuf fallback for systems without shuf (e.g., Alpine BusyBox)
if ! type -P shuf &>/dev/null; then
    shuf() {
        local min=0 max=100 n=1
        while [[ $# -gt 0 ]]; do
            case $1 in
            -i)
                IFS=- read -r min max <<<"$2"
                shift 2
                ;;
            -n)
                n=$2
                shift 2
                ;;
            *) shift ;;
            esac
        done
        local span=$((max - min + 1))
        local rnd=$((((RANDOM << 15) | RANDOM) & 0x3fffffff))
        echo $((rnd % span + min))
    }
fi

is_random_ss_method=${ss_method_list[$(shuf -i 4-6 -n1)]}
is_random_servername=${servername_list[$(shuf -i 0-$((${#servername_list[@]} - 1)) -n1)]}

_urlencode() {
    jq -rn --arg v "$1" '$v|@uri'
}

_urlencode_path() {
    jq -rn --arg v "$1" '$v|@uri|gsub("%2F";"/")'
}

reset_config_vars() {
    unset is_protocol port uuid password username ss_method ss_password \
        door_port door_addr net_type path host is_servername is_private_key \
        is_public_key is_short_id is_reality is_socks_user is_socks_pass \
        is_anytls_domain is_naive_domain is_naive_user is_naive_pass \
        is_naive_cert is_naive_key is_snell_ver is_snell_psk is_snell_mode \
        is_no_auto_tls is_tmp_https_port is_tcp_http is_insecure is_url \
        is_extra_urls is_surge_line is_config_name is_config_file \
        is_auto_get_config net inbound_json json_str is_new_json \
        is_use_tls is_socks is_use_port is_use_uuid is_use_host is_use_path \
        is_use_pass is_use_method is_use_door_addr is_use_door_port \
        is_use_servername is_use_socks_user is_use_socks_pass is_use_naive_user \
        is_use_naive_pass is_use_snell_ver is_use_snell_mode is_use_cert is_use_key \
        is_addr is_raw_addr is_used_port
}

msg() {
    [[ $is_quiet ]] && return
    echo -e "$*"
}

msg_ul() {
    echo -e "\e[4m$*\e[0m"
}

pause() {
    [[ $is_non_interactive ]] && return
    echo
    echo -ne "按 $(_green "Enter 回车键") 继续, 或按 $(_red "Ctrl + C") 取消."
    read -rs -d $'\n'
    echo
}

ver_ge() {
    local current=$1
    local required=$2
    [[ $(printf "%s\n%s\n" "$required" "$current" | sort -V | head -n1) == "$required" ]]
}

get_uuid() {
    if [[ -r /proc/sys/kernel/random/uuid ]]; then
        tmp_uuid=$(cat /proc/sys/kernel/random/uuid)
    elif [[ -x $is_core_bin ]]; then
        tmp_uuid=$($is_core_bin generate uuid)
    else
        tmp_uuid=$(od -x /dev/urandom | head -1 | awk '{OFS="-"; print $2$3,$4,$5,$6,$7$8$9}')
    fi
}

get_short_id() {
    if [[ -x $is_core_bin ]]; then
        tmp_short_id=$($is_core_bin generate rand --hex 4)
    else
        tmp_short_id=$(head -c 4 /dev/urandom | od -An -tx1 | tr -d ' \n')
    fi
}

get_ip() {
    [[ $ip || $is_no_auto_tls || $is_gen || $is_dont_get_ip ]] && return
    local _ip=""
    _ip=$(_fetch "https://one.one.one.one/cdn-cgi/trace" | grep '^ip=' | cut -d= -f2)
    [[ ! $_ip ]] && _ip=$(_fetch "https://api4.ipify.org")
    [[ ! $_ip ]] && _ip=$(_fetch "https://api64.ipify.org")
    [[ ! $_ip ]] && _ip=$(_fetch "https://icanhazip.com")
    ip=$(echo "$_ip" | tr -d '[:space:]')
    if [[ ! $ip ]]; then
        err "获取服务器 IP 失败.."
    fi
    return 0
}

get_port() {
    local configured_ports=""
    if [[ -d $is_conf_dir ]]; then
        configured_ports=$(grep -hEo '"listen_port"[[:space:]]*:[[:space:]]*[0-9]+' "$is_conf_dir"/*.json 2>/dev/null | grep -Eo '[0-9]+')
    fi
    is_count=0
    while :; do
        ((is_count++))
        if [[ $is_count -ge 200 ]]; then
            err "自动获取可用端口失败次数达到 200 次, 请检查端口占用情况."
        fi
        tmp_port=$(shuf -i 10000-65000 -n 1)
        if [[ ! $(is_test port_used "$tmp_port") && $tmp_port != "$port" ]]; then
            if [[ ! $configured_ports ]] || ! grep -qx "$tmp_port" <<<"$configured_ports"; then
                break
            fi
        fi
    done
}

get_pbk() {
    local _kp
    _kp=$($is_core_bin generate reality-keypair)
    is_private_key=$(awk '/PrivateKey/ {print $2}' <<<"$_kp" | tr -d '"[:space:]')
    is_public_key=$(awk '/PublicKey/ {print $2}' <<<"$_kp" | tr -d '"[:space:]')
}

show_list() {
    local i=0 v
    for v in "$@"; do
        ((i++))
        printf "%2d) %s\n" "$i" "$v"
    done
    echo
}

is_test() {
    case $1 in
    number)
        grep -E '^[1-9][0-9]*$' <<<"$2"
        ;;
    port)
        if [[ $(is_test number "$2") ]]; then
            [[ $2 -le 65535 ]] && echo ok
        fi
        ;;
    port_used)
        [[ $(is_port_used "$2") && ! $is_cant_test_port ]] && echo ok
        ;;
    domain)
        grep -E -i '^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$' <<<"$2"
        ;;
    path)
        grep -E -i '^/[a-zA-Z0-9._~:/?#@!$&'"'"'()*+,;=-]+$' <<<"$2"
        ;;
    uuid)
        grep -E -i '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' <<<"$2"
        ;;
    esac
}

is_port_used() {
    local check_p=$1
    local conf_ports=""
    if [[ -d $is_conf_dir ]]; then
        local f
        for f in "$is_conf_dir"/*.json; do
            [[ -f $f ]] || continue
            [[ $is_config_file && $(basename "$f") == "$is_config_file" ]] && continue
            local fp
            fp=$(jq -r '.inbounds[0].listen_port // empty' "$f" 2>/dev/null)
            [[ $fp == "$check_p" ]] && echo "$check_p" && return
        done
    fi
    if [[ $(type -P ss) ]]; then
        [[ ! $is_used_port ]] && is_used_port="$(ss -tunlp 2>/dev/null | sed -n 's/.*:\([0-9]\+\)[[:space:]].*/\1/p' | sort -nu)"
        tr ' ' '\n' <<<"$is_used_port" | grep -x "$check_p"
        return
    fi
    if [[ $(type -P netstat) ]]; then
        [[ ! $is_used_port ]] && is_used_port="$(netstat -tunlp 2>/dev/null | sed -n 's/.*:\([0-9]\+\)[[:space:]].*/\1/p' | sort -nu)"
        tr ' ' '\n' <<<"$is_used_port" | grep -x "$check_p"
        return
    fi
    is_cant_test_port=1
    msg "$is_warn 无法检测端口是否可用 (缺少 ss / netstat)."
}

ask() {
    case $1 in
    set_ss_method)
        is_tmp_list=("${ss_method_list[@]}")
        is_default_arg=$is_random_ss_method
        is_opt_msg="\n请选择加密方式:\n"
        is_opt_input_msg="(默认\e[92m $is_default_arg\e[0m):"
        is_ask_set=ss_method
        ;;
    set_protocol)
        is_tmp_list=("${protocol_list[@]}")
        [[ $is_no_auto_tls ]] && {
            is_tmp_list=()
            for v in "${protocol_list[@]}"; do
                [[ $v =~ -TLS$ || $v == "Naive" ]] && is_tmp_list+=("$v")
            done
        }
        is_opt_msg="\n请选择协议:\n"
        is_ask_set=is_new_protocol
        ;;
    set_change_list)
        is_tmp_list=()
        for v in "${is_can_change[@]}"; do
            is_tmp_list+=("${change_list[$v]}")
        done
        is_opt_msg="\n请选择更改:\n"
        is_ask_set=is_change_str
        is_opt_input_msg=$3
        ;;
    string)
        is_ask_set=$2
        is_opt_input_msg=$3
        ;;
    list)
        is_ask_set=$2
        [[ ${#is_tmp_list[@]} -eq 0 && $3 != "null" ]] && read -r -a is_tmp_list <<<"$3"
        is_opt_msg=$4
        is_opt_input_msg=$5
        ;;
    get_config_file)
        is_tmp_list=("${is_all_json[@]}")
        is_opt_msg="\n请选择配置:\n"
        is_ask_set=is_config_file
        ;;
    mainmenu)
        is_tmp_list=("${mainmenu[@]}")
        is_ask_set=is_main_pick
        is_emtpy_exit=1
        ;;
    esac
    [[ $is_opt_msg ]] && msg "$is_opt_msg"
    [[ ! $is_opt_input_msg ]] && is_opt_input_msg="请选择 [\e[91m1-${#is_tmp_list[@]}\e[0m]: "
    [[ ${#is_tmp_list[@]} -gt 0 ]] && show_list "${is_tmp_list[@]}"
    while :; do
        echo -ne "$is_opt_input_msg"
        if ! read -r REPLY; then
            err "非交互输入已终止 (EOF), 请通过命令行参数传入所需选项."
        fi
        [[ ! $REPLY && $is_emtpy_exit ]] && exit 0
        [[ ! $REPLY && $is_default_arg ]] && export "$is_ask_set=$is_default_arg" && break
        if [[ ${#is_tmp_list[@]} -eq 0 ]]; then
            if [[ $is_ask_set == *port* ]]; then
                [[ ! $(is_test port "$REPLY") ]] && {
                    msg "$is_err 请输入正确的端口, 可选(1-65535)"
                    continue
                }
                if [[ $(is_test port_used "$REPLY") && $is_ask_set != 'door_port' ]]; then
                    msg "$is_err 无法使用 ($REPLY) 端口, 端口已被占用."
                    continue
                fi
            fi
            if [[ ($is_ask_set == "host" || $is_ask_set == "is_new_host" || $is_ask_set == "is_naive_domain" || $is_ask_set == "is_anytls_domain" || $is_ask_set == "_dom") && ! $(is_test domain "$REPLY") ]]; then
                msg "$is_err 请输入合法的域名, 例如: proxy.example.com"
                continue
            fi
            if [[ $is_ask_set == *path* && ! $(is_test path "$REPLY") ]]; then
                [[ ! $tmp_uuid ]] && get_uuid
                msg "$is_err 请输入正确的路径, 例如: /$tmp_uuid"
                continue
            fi
            if [[ $is_ask_set == *uuid* && ! $(is_test uuid "$REPLY") ]]; then
                [[ ! $tmp_uuid ]] && get_uuid
                msg "$is_err 请输入正确的 UUID, 例如: $tmp_uuid"
                continue
            fi
            if [[ $is_ask_set == "is_snell_psk" && ${is_snell_ver:-6} == "6" && (${#REPLY} -lt 12 || ${#REPLY} -gt 255) ]]; then
                msg "$is_err Snell v6 要求 PSK 长度在 12-255 字节之间 (当前 ${#REPLY} 字节), 直接回车可使用随机 36 位 UUID."
                continue
            fi
            if [[ $is_ask_set == "y" ]]; then
                [[ ${REPLY,,} == "y" ]] && break
                msg "请输入 (y)"
                continue
            fi
            if [[ $REPLY ]]; then
                export "$is_ask_set=$REPLY"
                msg "使用: ${!is_ask_set}"
                break
            fi
        else
            if [[ $(is_test number "$REPLY") && $REPLY -le ${#is_tmp_list[@]} ]]; then
                is_ask_result=${is_tmp_list[$((REPLY - 1))]}
            fi
            if [[ $is_ask_result ]]; then
                export "$is_ask_set=$is_ask_result"
                msg "选择: ${!is_ask_set}"
                break
            fi
        fi
        msg "输入${is_err}"
    done
    unset is_opt_msg is_opt_input_msg is_tmp_list is_ask_result is_default_arg is_emtpy_exit
}

# Generate self-signed cert once for protocols that accept self-signed TLS
ensure_self_signed_tls() {
    is_tls_cer=$is_core_dir/bin/tls.cer
    is_tls_key=$is_core_dir/bin/tls.key
    if [[ ! -f $is_tls_cer || ! -f $is_tls_key ]]; then
        local is_tls_tmp=${is_tls_key}.tmp
        (umask 077 && "$is_core_bin" generate tls-keypair www.bing.com -m 456 >"$is_tls_tmp")
        (umask 077 && awk '/BEGIN PRIVATE KEY/,/END PRIVATE KEY/' "$is_tls_tmp" >"$is_tls_key")
        chmod 600 "$is_tls_key"
        awk '/BEGIN CERTIFICATE/,/END CERTIFICATE/' "$is_tls_tmp" >"$is_tls_cer"
        chmod 644 "$is_tls_cer"
        rm -f "$is_tls_tmp"
    fi
}

# Create server/caddy/config.json files
create() {
    case $1 in
    server)
        is_tls=none
        get new
        local listen_addr="::"
        if [[ $host ]]; then
            is_config_name=$2-${host}.json
            listen_addr="127.0.0.1"
        elif [[ $is_naive_domain ]]; then
            is_config_name=$2-${is_naive_domain}.json
        elif [[ $is_anytls_domain ]]; then
            is_config_name=$2-${is_anytls_domain}.json
        else
            is_config_name=$2-${port}.json
        fi
        is_json_file=$is_conf_dir/$is_config_name

        [[ $is_change || ! $inbound_json ]] && get protocol "$2"

        # Assemble final inbound JSON cleanly via jq
        local full_inbound
        full_inbound=$(jq -n \
            --arg tag "$is_config_name" \
            --arg type "$is_protocol" \
            --arg listen "$listen_addr" \
            --argjson port "$port" \
            --argjson body "$inbound_json" \
            '{tag: $tag, type: $type, listen: $listen, listen_port: $port} + $body')

        if [[ $is_reality && $is_public_key ]]; then
            is_new_json=$(jq -n \
                --argjson ib "$full_inbound" \
                --arg pbk_tag "public_key_${is_public_key}" \
                '{inbounds: [$ib], outbounds: [{tag: $pbk_tag, type: "direct"}]}')
        else
            is_new_json=$(jq -n --argjson ib "$full_inbound" '{inbounds: [$ib]}')
        fi

        [[ $is_test_json ]] && return

        if [[ $is_gen ]]; then
            msg
            jq . <<<"$is_new_json"
            msg
            return
        fi

        [[ $is_config_file ]] && is_no_del_msg=1 && del "$is_config_file"

        (umask 077 && printf '%s\n' "$is_new_json" >"$is_json_file")
        chmod 600 "$is_json_file"
        unset is_used_port

        if [[ $is_new_install && ! -f $is_config_json ]]; then
            create config.json
        fi

        if [[ $is_caddy && $host && ! $is_no_auto_tls ]]; then
            create caddy "$net"
        fi

        if [[ ! $is_skip_restart ]]; then
            manage restart </dev/null &>/dev/null &
        fi
        ;;
    caddy)
        load caddy.sh
        [[ $is_install_caddy ]] && caddy_config new
        [[ ! $(grep "$is_caddy_conf" "$is_caddyfile" 2>/dev/null) ]] && {
            echo "import $is_caddy_conf/*.conf" >>"$is_caddyfile"
        }
        mkdir -p "$is_caddy_conf"
        caddy_config "$2"
        manage restart caddy &
        ;;
    config.json)
        local ntp_obj="null" dns_obj="{}" route_obj="null"
        if [[ -f $is_config_json ]]; then
            [[ $(jq -r '.ntp.enabled // false' "$is_config_json" 2>/dev/null) == "true" ]] && ntp_obj='{"enabled":true,"server":"time.apple.com"}'
            dns_obj=$(jq -c '.dns // {}' "$is_config_json" 2>/dev/null)
            route_obj=$(jq -c '.route // null' "$is_config_json" 2>/dev/null)
        else
            [[ $is_ntp_on ]] && ntp_obj='{"enabled":true,"server":"time.apple.com"}'
        fi
        [[ ! $dns_obj ]] && dns_obj="{}"
        [[ ! $ntp_obj ]] && ntp_obj="null"
        [[ ! $route_obj ]] && route_obj="null"
        is_server_config_json=$(jq -n \
            --arg log_out "${is_log_dir}/access.log" \
            --argjson dns "$dns_obj" \
            --argjson ntp "$ntp_obj" \
            --argjson route "$route_obj" \
            '{log:{output:$log_out,level:"info",timestamp:true},dns:$dns,outbounds:[{tag:"direct",type:"direct"}]}
            + (if $ntp != null then {ntp:$ntp} else {} end)
            + (if $route != null then {route:$route} else {} end)')
        (umask 077 && printf '%s\n' "$is_server_config_json" >"$is_config_json")
        chmod 600 "$is_config_json"
        [[ ! $is_new_install && ! $is_skip_restart ]] && manage restart &
        ;;
    esac
}

change() {
    is_change=1
    is_dont_show_info=1
    if [[ $2 ]]; then
        case ${2,,} in
        full) is_change_id=full ;;
        new) is_change_id=0 ;;
        port) is_change_id=1 ;;
        host) is_change_id=2 ;;
        path) is_change_id=3 ;;
        pass | passwd | password | psk) is_change_id=4 ;;
        id | uuid) is_change_id=5 ;;
        ssm | method | ss-method | ss_method) is_change_id=6 ;;
        dda | door-addr | door_addr) is_change_id=7 ;;
        ddp | door-port | door_port) is_change_id=8 ;;
        key | publickey | privatekey) is_change_id=9 ;;
        sni | servername | servernames) is_change_id=10 ;;
        web | proxy-site) is_change_id=11 ;;
        user | username) is_change_id=12 ;;
        *)
            [[ $is_try_change ]] && return
            err "无法识别 ($2) 更改类型."
            ;;
        esac
    fi
    [[ $is_try_change ]] && return

    if [[ $is_dont_auto_exit ]]; then
        get info "$1"
    else
        if [[ $is_change_id ]]; then
            is_change_msg=${change_list[$is_change_id]}
            [[ $is_change_id == 'full' ]] && {
                [[ $3 ]] && is_change_msg="更改多个参数" || is_change_msg=""
            }
            [[ $is_change_msg ]] && _green "\n快速执行: $is_change_msg"
        fi
        info "$1"
        [[ $is_auto_get_config ]] && msg "\n自动选择: $is_config_file"
    fi

    is_old_net=$net
    [[ $is_tcp_http ]] && net=http
    [[ $host ]] && net=$is_protocol-$net-tls
    [[ $is_reality && $is_protocol == "vless" && $net_type =~ http ]] && net=rh2
    [[ $is_reality && $is_protocol == "anytls" ]] && net=anyreality
    [[ $is_protocol == "vless" && $net == "ws" && ! $host ]] && net=vless-ws

    [[ $3 == 'auto' ]] && is_auto=1
    is_dont_show_info=

    [[ ! $is_change_id ]] && {
        ask set_change_list
        is_change_id=${is_can_change[$((REPLY - 1))]}
    }

    case $is_change_id in
    full)
        add "$net" "${@:3}"
        ;;
    0)
        is_set_new_protocol=1
        add "${@:3}"
        ;;
    1)
        is_new_port=$3
        local _old_cfg_file=$is_config_file
        [[ $host && ! $is_caddy || $is_no_auto_tls ]] && err "($is_config_file) 不支持更改端口."
        if [[ $is_new_port && ! $is_auto ]]; then
            [[ ! $(is_test port "$is_new_port") ]] && err "请输入正确的端口, 可选(1-65535)"
            if [[ ! $is_caddy || ! $host ]] && [[ $(is_test port_used "$is_new_port") ]]; then
                err "无法使用 ($is_new_port) 端口"
            fi
        fi
        [[ $is_auto ]] && get_port && is_new_port=$tmp_port
        [[ ! $is_new_port ]] && ask string is_new_port "请输入新端口: "
        if [[ $is_caddy && $host ]]; then
            net=$is_old_net
            is_https_port=$is_new_port
            load caddy.sh
            caddy_config "$net"
            manage restart caddy &
            info
        elif [[ $is_protocol == "naive" ]]; then
            port=$is_new_port
            add naive
        else
            port=$is_new_port
            add "$net" "$is_new_port"
            if [[ $_old_cfg_file && -f $is_argo_conf && $(jq -r '.backend_config // empty' "$is_argo_conf" 2>/dev/null) == "$_old_cfg_file" ]]; then
                local _amode _aproto
                _amode=$(jq -r '.mode // "quick"' "$is_argo_conf" 2>/dev/null)
                _aproto=$(jq -r '.protocol // "http2"' "$is_argo_conf" 2>/dev/null)
                (umask 077 && jq --arg bf "$is_config_name" --argjson bp "$is_new_port" '.backend_config = $bf | .backend_port = $bp' "$is_argo_conf" >"${is_argo_conf}.tmp" && mv "${is_argo_conf}.tmp" "$is_argo_conf")
                chmod 600 "$is_argo_conf"
                if [[ $_amode == "quick" ]]; then
                    load systemd.sh
                    install_service argo quick "$_aproto" "$is_new_port" &>/dev/null
                    manage restart argo &>/dev/null &
                else
                    warn "已更改 Argo 后端端口为 ${is_new_port}, 请同步更新 Cloudflare Zero Trust Public Hostname 转发端口."
                fi
            fi
        fi
        ;;
    2)
        is_new_host=$3
        [[ $is_new_host && ! $(is_test domain "$is_new_host") ]] && err "($is_new_host) 不是合法的域名."
        if [[ $is_protocol == "naive" ]]; then
            [[ ! $is_new_host ]] && ask string is_new_host "请输入新域名: "
            is_naive_domain=$is_new_host
            add naive
        elif [[ $is_protocol == "anytls" ]]; then
            [[ ! $is_new_host ]] && ask string is_new_host "请输入新域名: "
            is_anytls_domain=$is_new_host
            add anytls
        else
            [[ ! $host ]] && err "($is_config_file) 不支持更改域名."
            [[ ! $is_new_host ]] && ask string is_new_host "请输入新域名: "
            old_host=$host
            add "$net" "$is_new_host"
        fi
        ;;
    3)
        is_new_path=$3
        [[ ! $path ]] && err "($is_config_file) 不支持更改路径."
        [[ $is_auto ]] && get_uuid && is_new_path=/$tmp_uuid
        [[ ! $is_new_path ]] && ask string is_new_path "请输入新路径: "
        if [[ $host ]]; then
            add "$net" auto auto "$is_new_path"
        else
            path=$is_new_path
            add "$net"
        fi
        ;;
    4)
        is_new_pass=$3
        if [[ $ss_password || $password || $is_snell_psk || $is_naive_pass ]]; then
            if [[ $is_auto ]]; then
                get_uuid && is_new_pass=$tmp_uuid
                [[ $ss_password ]] && is_new_pass=$(get ss2022)
            fi
        else
            err "($is_config_file) 不支持更改密码."
        fi
        [[ ! $is_new_pass ]] && ask string is_new_pass "请输入新密码: "
        if [[ $is_protocol == "snell" && ${is_snell_ver:-6} == "6" && (${#is_new_pass} -lt 12 || ${#is_new_pass} -gt 255) ]]; then
            err "Snell v6 要求 PSK 长度在 12-255 字节之间 (当前 ${#is_new_pass} 字节)."
        fi
        password=$is_new_pass
        ss_password=$is_new_pass
        is_socks_pass=$is_new_pass
        is_naive_pass=$is_new_pass
        is_snell_psk=$is_new_pass
        add "$net"
        ;;
    5)
        is_new_uuid=$3
        [[ ! $uuid ]] && err "($is_config_file) 不支持更改 UUID."
        [[ $is_auto ]] && get_uuid && is_new_uuid=$tmp_uuid
        [[ ! $is_new_uuid ]] && ask string is_new_uuid "请输入新 UUID: "
        uuid=$is_new_uuid
        add "$net"
        ;;
    6)
        is_new_method=$3
        [[ $net != 'ss' ]] && err "($is_config_file) 不支持更改加密方式."
        [[ $is_auto ]] && is_new_method=$is_random_ss_method
        [[ ! $is_new_method ]] && {
            ask set_ss_method
            is_new_method=$ss_method
        }
        ss_method=$is_new_method
        add "$net"
        ;;
    7)
        is_new_door_addr=$3
        [[ $net != 'direct' ]] && err "($is_config_file) 不支持更改目标地址."
        [[ ! $is_new_door_addr ]] && ask string is_new_door_addr "请输入新的目标地址: "
        door_addr=$is_new_door_addr
        add "$net"
        ;;
    8)
        is_new_door_port=$3
        [[ $net != 'direct' ]] && err "($is_config_file) 不支持更改目标端口."
        [[ ! $is_new_door_port ]] && {
            ask string door_port "请输入新的目标端口: "
            is_new_door_port=$door_port
        }
        door_port=$is_new_door_port
        add "$net"
        ;;
    9)
        is_new_private_key=$3
        is_new_public_key=$4
        [[ ! $is_reality ]] && err "($is_config_file) 不支持更改密钥."
        if [[ $is_auto ]]; then
            get_pbk
            add "$net"
        else
            [[ $is_new_private_key && ! $is_new_public_key ]] && err "无法找到 Public key."
            [[ ! $is_new_private_key ]] && ask string is_new_private_key "请输入新 Private key: "
            [[ ! $is_new_public_key ]] && ask string is_new_public_key "请输入新 Public key: "
            [[ $is_new_private_key == "$is_new_public_key" ]] && err "Private key 和 Public key 不能一样."
            is_private_key=$is_new_private_key
            is_public_key=$is_new_public_key
            add "$net"
        fi
        ;;
    10)
        is_new_servername=$3
        [[ ! $is_reality ]] && err "($is_config_file) 不支持更改 serverName."
        [[ $is_auto ]] && is_new_servername=$is_random_servername
        [[ ! $is_new_servername ]] && ask string is_new_servername "请输入新的 serverName: "
        is_servername=$is_new_servername
        add "$net"
        ;;
    11)
        is_new_proxy_site=$3
        [[ ! $is_caddy || ! $host ]] && err "($is_config_file) 不支持更改伪装网站."
        [[ ! -f $is_caddy_conf/${host}.conf.add ]] && err "无法配置伪装网站."
        [[ ! $is_new_proxy_site ]] && ask string is_new_proxy_site "请输入新的伪装网站 (例如 example.com): "
        proxy_site=$(sed 's#^.*//##;s#/$##' <<<"$is_new_proxy_site")
        load caddy.sh
        caddy_config proxy
        manage restart caddy &
        msg "\n已更新伪装网站为: $(_green "$proxy_site")\n"
        ;;
    12)
        if [[ $is_protocol == "naive" ]]; then
            is_new_user=$3
            [[ ! $is_new_user ]] && ask string is_new_user "请输入新用户名 (Username): "
            is_naive_user=$is_new_user
            add naive
        elif [[ $is_socks_user ]]; then
            is_new_user=$3
            [[ ! $is_new_user ]] && ask string is_new_user "请输入新用户名 (Username): "
            is_socks_user=$is_new_user
            add socks
        else
            err "($is_config_file) 不支持更改用户名 (Username)."
        fi
        ;;
    esac
    unset is_change is_change_id is_set_new_protocol is_auto old_host is_no_del_msg
}

del() {
    is_dont_get_ip=1
    [[ $is_conf_dir_empty ]] && return
    [[ ! $is_config_file ]] && get info "$1"
    if [[ $is_config_file ]]; then
        if [[ $is_main_start && ! $is_no_del_msg ]]; then
            msg "\n是否删除配置文件?: $is_config_file"
            pause
        fi
        rm -f "$is_conf_dir/$is_config_file"
        unset is_used_port
        [[ ! $is_new_json && ! $is_skip_restart ]] && manage restart &
        [[ ! $is_no_del_msg ]] && _green "\n已删除: $is_config_file\n"
        if [[ ! $is_change && -f $is_argo_conf && $(jq -r '.backend_config // empty' "$is_argo_conf" 2>/dev/null) == "$is_config_file" ]]; then
            warn "已删除 CF Argo 绑定的后端节点 ($is_config_file), 如需继续使用 Argo 请重新运行: $is_app argo"
        fi

        if [[ $is_caddy ]]; then
            is_del_host=$host
            if [[ $is_change ]]; then
                [[ ! $old_host ]] && unset is_dont_get_ip && return
                is_del_host=$old_host
            fi
            if [[ $is_del_host && $host != "$old_host" && -f $is_caddy_conf/$is_del_host.conf ]]; then
                rm -rf "$is_caddy_conf/$is_del_host.conf" "$is_caddy_conf/$is_del_host.conf.add"
                [[ ! $is_new_json ]] && manage restart caddy &
            fi
        fi
    fi
    if [[ ! $(ls "$is_conf_dir" 2>/dev/null | grep '\.json$') && ! $is_change ]]; then
        warn "当前配置目录为空! 你刚刚删除了最后一个配置文件."
        is_conf_dir_empty=1
    fi
    unset is_dont_get_ip
    if [[ $is_dont_auto_exit ]]; then
        unset is_config_file
    fi
    return 0
}

uninstall() {
    local rm_caddy=0
    if [[ ! $is_non_interactive ]]; then
        if [[ $is_caddy ]]; then
            is_tmp_list=("卸载 $is_app (含 Argo)" "卸载 $is_app (含 Argo) & Caddy")
            ask list is_do_uninstall
            [[ $REPLY == '2' ]] && rm_caddy=1
        else
            ask string y "是否卸载 ${is_app} (含 sing-box 及 Argo 隧道)? [y]: "
        fi
    fi

    manage stop &>/dev/null
    manage disable &>/dev/null
    manage stop argo &>/dev/null
    manage disable argo &>/dev/null

    rm -rf "$is_core_dir" "$is_log_dir" "$is_sh_bin" "$is_sh_short_bin" /usr/local/bin/w6
    if [[ $is_systemd ]]; then
        rm -f "/lib/systemd/system/${is_app}.service" "/lib/systemd/system/${is_argo_service_name}.service"
        systemctl daemon-reload &>/dev/null
    elif [[ $is_openrc ]]; then
        rm -f "/etc/init.d/${is_app}" "/etc/init.d/${is_argo_service_name}"
    fi
    sed -i "/alias $is_app=/d;/alias w6=/d;/alias yy=/d" /root/.bashrc 2>/dev/null

    if [[ $rm_caddy -eq 1 ]]; then
        manage stop caddy &>/dev/null
        manage disable caddy &>/dev/null
        if [[ $is_systemd ]]; then
            rm -rf "$is_caddy_dir" "$is_caddy_bin" /lib/systemd/system/caddy.service
            systemctl daemon-reload &>/dev/null
        elif [[ $is_openrc ]]; then
            rm -rf "$is_caddy_dir" "$is_caddy_bin" /etc/init.d/caddy
        fi
    fi
    [[ $is_install_sh ]] && return
    _green "\n卸载完成!"
    msg "反馈问题) $(msg_ul "https://github.com/${is_sh_repo}/issues")\n"
}

manage() {
    [[ $is_dont_auto_exit ]] && return
    local is_do is_do_msg is_test_run="" is_do_name is_run_bin is_do_name_msg
    case $1 in
    1 | start)
        is_do=start
        is_do_msg=启动
        is_test_run=1
        ;;
    2 | stop)
        is_do=stop
        is_do_msg=停止
        ;;
    3 | r | restart)
        is_do=restart
        is_do_msg=重启
        is_test_run=1
        ;;
    *)
        is_do=$1
        is_do_msg=$1
        ;;
    esac

    case $2 in
    caddy)
        is_do_name=caddy
        is_run_bin=$is_caddy_bin
        is_do_name_msg=Caddy
        ;;
    argo | cloudflared)
        is_do_name=$is_argo_service_name
        is_run_bin=$is_argo_bin
        is_do_name_msg="CF Argo"
        ;;
    *)
        is_do_name=$is_app
        is_run_bin=$is_core_bin
        is_do_name_msg=$is_core_name
        ;;
    esac

    if [[ $is_systemd ]]; then
        systemctl "$is_do" "$is_do_name" 2>/dev/null
    elif [[ $is_openrc ]]; then
        case $is_do in
        enable) rc-update add "$is_do_name" default 2>/dev/null ;;
        disable) rc-update del "$is_do_name" default 2>/dev/null ;;
        *) rc-service "$is_do_name" "$is_do" 2>/dev/null ;;
        esac
    fi

    if [[ $is_test_run && ! $is_new_install && ! $is_quiet ]]; then
        sleep 2
        if ! _is_svc_running "$is_do_name" "$is_run_bin"; then
            is_run_fail=${is_do_name_msg,,}
            if [[ ! $is_no_manage_msg ]]; then
                msg
                warn "($is_do_msg) $is_do_name_msg 失败"
                _yellow "检测到运行失败, 自动执行测试运行."
                get test-run
            fi
        fi
    fi
}

add() {
    is_lower=${1,,}
    is_new_protocol=""
    if [[ $is_lower ]]; then
        case $is_lower in
        argo | cf | cf-argo)
            load argo.sh
            argo_main "${@:2}"
            return
            ;;
        ws | tcp | quic | http)
            is_new_protocol=VMess-${is_lower^^}
            ;;
        vws-plain | vless-ws | vw)
            is_new_protocol=VLESS-WS
            ;;
        wss) is_new_protocol=VMess-WS-TLS ;;
        h2) is_new_protocol=VMess-H2-TLS ;;
        hu) is_new_protocol=VMess-HTTPUpgrade-TLS ;;
        vws) is_new_protocol=VLESS-WS-TLS ;;
        vh2) is_new_protocol=VLESS-H2-TLS ;;
        vhu) is_new_protocol=VLESS-HTTPUpgrade-TLS ;;
        tws) is_new_protocol=Trojan-WS-TLS ;;
        th2) is_new_protocol=Trojan-H2-TLS ;;
        thu) is_new_protocol=Trojan-HTTPUpgrade-TLS ;;
        r | reality | vless-reality)
            is_new_protocol=VLESS-REALITY
            ;;
        rh2 | vless-http2-reality)
            is_new_protocol=VLESS-HTTP2-REALITY
            ;;
        ss | ss2022 | shadowsocks)
            is_new_protocol=Shadowsocks
            ;;
        door | direct)
            is_new_protocol=Direct
            ;;
        tuic | tuic5)
            is_new_protocol=TUIC
            ;;
        hy | hy2 | hysteria*)
            is_new_protocol=Hysteria2
            ;;
        trojan)
            is_new_protocol=Trojan
            ;;
        anytls)
            is_new_protocol=AnyTLS
            ;;
        ar | anyreality | any-reality | anytls-reality)
            is_new_protocol=AnyTLS-REALITY
            ;;
        naive | native | nv | naiveproxy)
            is_new_protocol=Naive
            ;;
        snell | snell6 | snellv6 | sn)
            is_new_protocol=Snell
            [[ ! $is_snell_ver ]] && is_snell_ver=6
            ;;
        snell5 | snellv5)
            is_new_protocol=Snell
            is_snell_ver=5
            ;;
        socks | socks5)
            is_new_protocol=Socks
            ;;
        *)
            for v in "${protocol_list[@]}"; do
                [[ ${v,,} == "$is_lower" ]] && is_new_protocol=$v && break
            done
            [[ ! $is_new_protocol ]] && err "无法识别协议 ($1), 请使用: $is_app add [protocol] [args... | auto]"
            ;;
        esac
    fi

    [[ ! $is_new_protocol ]] && ask set_protocol

    # Version checks for modern sing-box protocols
    case ${is_new_protocol,,} in
    anytls*)
        if ! ver_ge "${is_core_ver:-0.0.0}" "1.12.0"; then
            err "当前 sing-box 版本 ($is_core_ver) 不支持 AnyTLS, 请先执行: $is_app update core"
        fi
        ;;
    snell)
        if ! ver_ge "${is_core_ver:-0.0.0}" "1.14.0"; then
            err "当前 sing-box 版本 ($is_core_ver) 不支持 Snell v5/v6, 请先执行: $is_app update core"
        fi
        ;;
    esac

    case ${is_new_protocol,,} in
    *-tls)
        is_use_tls=1
        is_use_host=$2
        is_use_uuid=$3
        is_use_path=$4
        is_add_opts="[host] [uuid] [/path]"
        ;;
    vmess* | vless-ws | tuic*)
        is_use_port=$2
        is_use_uuid=$3
        is_use_path=$4
        is_add_opts="[port] [uuid] [/path]"
        ;;
    trojan* | hysteria*)
        is_use_port=$2
        is_use_pass=$3
        is_add_opts="[port] [password]"
        ;;
    vless*reality*)
        is_reality=1
        is_use_port=$2
        is_use_uuid=$3
        is_use_servername=$4
        is_add_opts="[port] [uuid] [sni]"
        ;;
    anytls-reality)
        is_reality=1
        is_use_port=$2
        is_use_pass=$3
        is_use_servername=$4
        is_add_opts="[port] [password] [sni]"
        ;;
    anytls)
        is_use_port=$2
        is_use_pass=$3
        [[ $4 && $4 != "auto" ]] && is_anytls_domain=$4
        is_add_opts="[port] [password] [domain]"
        ;;
    naive)
        is_use_host=$2
        is_use_port=$3
        is_use_naive_user=$4
        is_use_naive_pass=$5
        is_use_cert=$6
        is_use_key=$7
        is_add_opts="[domain] [port] [username] [password] [cert_path] [key_path]"
        ;;
    snell)
        is_use_port=$2
        is_use_pass=$3
        is_use_snell_ver=$4
        is_use_snell_mode=$5
        is_add_opts="[port] [psk] [version:6|5] [mode:default|unshaped|unsafe-raw]"
        ;;
    shadowsocks)
        is_use_port=$2
        is_use_pass=$3
        is_use_method=$4
        is_add_opts="[port] [password] [method]"
        ;;
    direct)
        is_use_port=$2
        is_use_door_addr=$3
        is_use_door_port=$4
        is_add_opts="[port] [remote_addr] [remote_port]"
        ;;
    socks)
        is_socks=1
        is_use_port=$2
        is_use_socks_user=$3
        is_use_socks_pass=$4
        is_add_opts="[port] [username] [password]"
        ;;
    esac

    [[ $1 && ! $is_change ]] && {
        msg "\n使用协议: $(_cyan "$is_new_protocol")"
        is_err_tips="\n\n请使用: $(_green "$is_app add $1 $is_add_opts") 来添加 $is_new_protocol 配置"
    }

    # Remove old protocol args when switching protocols
    if [[ $is_set_new_protocol ]]; then
        case $is_old_net in
        h2 | ws | httpupgrade)
            old_host=$host
            [[ ! $is_use_tls ]] && unset host is_no_auto_tls
            ;;
        reality | anyreality)
            net_type=
            if [[ ! ${is_new_protocol,,} =~ reality ]]; then
                unset is_reality is_public_key is_private_key is_short_id is_servername
            fi
            ;;
        anytls)
            [[ ${is_new_protocol,,} != "anytls" ]] && unset is_anytls_domain
            ;;
        ss)
            [[ $(is_test uuid "$ss_password") ]] && uuid=$ss_password
            ;;
        naive)
            unset is_naive_domain is_naive_cert is_naive_key
            ;;
        snell)
            unset is_snell_ver is_snell_psk is_snell_mode
            ;;
        esac
        [[ ! $(is_test uuid "$uuid") ]] && uuid=
        [[ $(is_test uuid "$password") ]] && uuid=$password
    fi

    if [[ $is_no_auto_tls && ! $is_use_tls && ${is_new_protocol,,} != "naive" ]]; then
        err "$is_new_protocol 不支持手动配置 tls."
    fi

    if [[ $is_anytls_domain && ! $(is_test domain "$is_anytls_domain") ]]; then
        err "($is_anytls_domain) 不是一个合法的域名."
    fi

    # Parse positional args
    if [[ $2 ]]; then
        for v in is_use_port is_use_uuid is_use_host is_use_path is_use_pass is_use_method is_use_door_addr is_use_door_port is_use_servername is_use_socks_user is_use_socks_pass is_use_naive_user is_use_naive_pass is_use_snell_ver is_use_snell_mode is_use_cert is_use_key; do
            [[ ${!v} == 'auto' ]] && unset "$v"
        done

        if [[ $is_use_port ]]; then
            [[ ! $(is_test port "$is_use_port") ]] && err "($is_use_port) 不是一个有效的端口. $is_err_tips"
            [[ $(is_test port_used "$is_use_port") && ! $is_gen ]] && err "无法使用 ($is_use_port) 端口. $is_err_tips"
            port=$is_use_port
        fi
        if [[ $is_use_door_port ]]; then
            [[ ! $(is_test port "$is_use_door_port") ]] && err "($is_use_door_port) 不是一个有效的目标端口. $is_err_tips"
            door_port=$is_use_door_port
        fi
        if [[ $is_use_uuid ]]; then
            [[ ! $(is_test uuid "$is_use_uuid") ]] && err "($is_use_uuid) 不是一个有效的 UUID. $is_err_tips"
            uuid=$is_use_uuid
        fi
        if [[ $is_use_path ]]; then
            [[ ! $(is_test path "$is_use_path") ]] && err "($is_use_path) 不是有效的路径 (需以 / 开头). $is_err_tips"
            path=$is_use_path
        fi
        if [[ $is_use_method ]]; then
            local matched_method=""
            for v in "${ss_method_list[@]}"; do
                [[ ${v,,} == "${is_use_method,,}" ]] && matched_method=$v && break
            done
            if [[ ! $matched_method ]]; then
                warn "($is_use_method) 不是一个可用的加密方式."
                msg "可用如下:"
                for v in "${ss_method_list[@]}"; do msg "\t$v"; done
                err "$is_err_tips"
            fi
            ss_method=$matched_method
        fi
        if [[ $is_use_snell_ver ]]; then
            [[ $is_use_snell_ver != "5" && $is_use_snell_ver != "6" ]] && err "Snell 版本仅支持 5 或 6 (默认 6)."
            is_snell_ver=$is_use_snell_ver
        fi
        if [[ $is_use_snell_mode ]]; then
            case $is_use_snell_mode in
            default | unshaped | unsafe-raw) is_snell_mode=$is_use_snell_mode ;;
            *) err "Snell v6 mode 仅支持 default / unshaped / unsafe-raw." ;;
            esac
        fi
        if [[ $is_use_host ]]; then
            [[ ! $(is_test domain "$is_use_host") ]] && err "($is_use_host) 不是一个合法的域名. $is_err_tips"
        fi
        if [[ ${is_new_protocol,,} == "naive" ]]; then
            [[ $is_use_host ]] && is_naive_domain=$is_use_host
            [[ $is_use_naive_user ]] && is_naive_user=$is_use_naive_user
            [[ $is_use_naive_pass ]] && is_naive_pass=$is_use_naive_pass
            [[ $is_use_cert ]] && is_naive_cert=$is_use_cert
            [[ $is_use_key ]] && is_naive_key=$is_use_key
        else
            [[ $is_use_host ]] && host=$is_use_host
        fi
        [[ $is_use_pass ]] && ss_password=$is_use_pass && password=$is_use_pass && is_snell_psk=$is_use_pass
        [[ $is_use_door_addr ]] && door_addr=$is_use_door_addr
        [[ $is_use_servername ]] && is_servername=$is_use_servername
        [[ $is_use_socks_user ]] && is_socks_user=$is_use_socks_user
        [[ $is_use_socks_pass ]] && is_socks_pass=$is_use_socks_pass
    fi

    # NaiveProxy domain & TLS certificate handling
    if [[ ${is_new_protocol,,} == "naive" ]]; then
        if [[ ! $is_naive_domain ]]; then
            if [[ $is_non_interactive ]]; then
                err "NaiveProxy (native) 必须使用已解析到本机的真实域名以自动申请受信任 TLS 证书 (客户端不接受自签证书). 示例: $is_app add naive proxy.example.com 443. 无域名请改用 anytls / reality / hy2 / snell."
            fi
            msg "$(_yellow "提示: NaiveProxy 客户端基于 Chrome 网络栈强制校验合法 TLS 证书, 必须提供已解析到本机 IP 的域名 (无域名请按 Ctrl+C 改用 AnyTLS / REALITY / HY2 / Snell).")"
            ask string is_naive_domain "请输入 NaiveProxy 域名 (已解析到本机 IP): "
        fi
        # Auto-detect existing local cert if not explicitly given
        if [[ ! $is_naive_cert && -s /etc/why666/certs/${is_naive_domain}.crt && -s /etc/why666/certs/${is_naive_domain}.key ]]; then
            is_naive_cert="/etc/why666/certs/${is_naive_domain}.crt"
            is_naive_key="/etc/why666/certs/${is_naive_domain}.key"
        fi
        if [[ $is_naive_cert && ! -f $is_naive_cert ]]; then
            err "NaiveProxy 证书文件不存在: $is_naive_cert"
        fi
        if [[ $is_naive_key && ! -f $is_naive_key ]]; then
            err "NaiveProxy 私钥文件不存在: $is_naive_key"
        fi
        # When using built-in ACME, verify DNS unless skipped
        if [[ ! $is_naive_cert && ! $is_change && ! $is_gen && ! $is_no_auto_tls && ! $is_skip_dns_check ]]; then
            get_ip
            local _saved_host=$host
            host=$is_naive_domain
            get host-test
            host=$_saved_host
        fi
        # Default port for NaiveProxy ACME: 443 if free, else random
        if [[ ! $port ]]; then
            if [[ ! $(is_test port_used 443) ]]; then
                port=443
            else
                get_port
                port=$tmp_port
            fi
        fi
    fi

    # Snell PSK validation
    if [[ ${is_new_protocol,,} == "snell" ]]; then
        [[ ! $is_snell_ver ]] && is_snell_ver=6
        [[ ! $is_snell_mode ]] && is_snell_mode=default
        if [[ $is_snell_psk && $is_snell_ver == "6" && ${#is_snell_psk} -lt 12 ]]; then
            err "Snell v6 要求 PSK 长度在 12-255 字节之间 (当前 ${#is_snell_psk} 字节)."
        fi
    fi

    # AnyTLS with domain (ACME TLS)
    if [[ $is_anytls_domain && ! $is_change && ! $is_gen && ! $is_skip_dns_check ]]; then
        get_ip
        local _saved_host=$host
        host=$is_anytls_domain
        get host-test
        host=$_saved_host
    fi

    if [[ $is_use_tls ]]; then
        if [[ ! $is_no_auto_tls && ! $is_caddy && ! $is_gen && ! $is_dont_test_host ]]; then
            if [[ $(is_test port_used 80) || $(is_test port_used 443) ]]; then
                get_port
                is_http_port=$tmp_port
                get_port
                is_https_port=$tmp_port
                warn "端口 (80 或 443) 已被占用, Caddy 将使用非标准端口 HTTP:$is_http_port HTTPS:$is_https_port, 或使用 no-auto-tls"
                pause
            fi
            is_install_caddy=1
        fi
        [[ ! $host ]] && ask string host "请输入域名: "
        [[ ! $is_skip_dns_check ]] && get host-test
    else
        if [[ $is_main_start && ! $is_non_interactive ]]; then
            [[ ! $port ]] && {
                get_port
                is_default_arg=$tmp_port
                ask string port "请输入端口 (默认\e[92m $tmp_port\e[0m): "
            }
            case ${is_new_protocol,,} in
            socks)
                [[ ! $is_socks_user ]] && {
                    is_default_arg=why666
                    ask string is_socks_user "请设置用户名 (默认\e[92m why666\e[0m): "
                }
                [[ ! $is_socks_pass ]] && {
                    get_uuid
                    is_default_arg=$tmp_uuid
                    ask string is_socks_pass "请设置密码 (默认\e[92m 随机UUID\e[0m): "
                }
                ;;
            naive)
                [[ ! $is_naive_user ]] && {
                    is_default_arg=why666
                    ask string is_naive_user "请设置用户名 (默认\e[92m why666\e[0m): "
                }
                [[ ! $is_naive_pass ]] && {
                    get_uuid
                    is_default_arg=$tmp_uuid
                    ask string is_naive_pass "请设置密码 (默认\e[92m 随机UUID\e[0m): "
                }
                ;;
            snell)
                [[ ! $is_snell_psk ]] && {
                    get_uuid
                    is_default_arg=$tmp_uuid
                    ask string is_snell_psk "请设置 Snell PSK (v6 需 12-255 字节, 默认\e[92m 随机UUID\e[0m): "
                }
                ;;
            shadowsocks)
                [[ ! $ss_method ]] && ask set_ss_method
                [[ ! $ss_password ]] && {
                    is_default_arg=$(get ss2022)
                    ask string ss_password "请设置密码 (默认\e[92m 自动生成\e[0m): "
                }
                ;;
            esac
        fi
    fi

    if [[ $is_new_protocol == 'Direct' ]]; then
        [[ ! $door_addr ]] && ask string door_addr "请输入目标地址: "
        [[ ! $door_port ]] && ask string door_port "请输入目标端口: "
    fi

    # Re-validate Snell v6 PSK after interactive input (must be 12-255 bytes)
    if [[ ${is_new_protocol,,} == "snell" && ${is_snell_ver:-6} == "6" && $is_snell_psk ]]; then
        if [[ ${#is_snell_psk} -lt 12 || ${#is_snell_psk} -gt 255 ]]; then
            err "Snell v6 要求 PSK 长度在 12-255 字节之间 (当前 ${#is_snell_psk} 字节)."
        fi
    fi

    # Validate Shadowsocks 2022 password format
    if [[ $ss_method == *2022* && $ss_password ]]; then
        is_test_json=1
        create server Shadowsocks
        [[ ! $tmp_uuid ]] && get_uuid
        is_test_json_save=$is_conf_dir/tmp-test-$tmp_uuid.json
        printf '%s\n' "$is_new_json" >"$is_test_json_save"
        if ! "$is_core_bin" check -c "$is_test_json_save" &>/dev/null; then
            warn "Shadowsocks 协议 ($ss_method) 不支持密码 ($ss_password), 将自动生成合规的 SS2022 密钥."
            ss_password=""
            inbound_json=""
        fi
        is_test_json=
        is_new_json=
        rm -f "$is_test_json_save"
    fi

    if [[ $is_install_caddy ]]; then
        get install-caddy
    fi

    create server "$is_new_protocol"
    info
}

get() {
    case $1 in
    addr)
        if [[ $is_naive_domain ]]; then
            is_raw_addr=$is_naive_domain
            is_addr=$is_naive_domain
        elif [[ $is_anytls_domain ]]; then
            is_raw_addr=$is_anytls_domain
            is_addr=$is_anytls_domain
        elif [[ $host ]]; then
            is_raw_addr=$host
            is_addr=$host
        else
            get_ip
            is_raw_addr=$ip
            is_addr=$ip
            [[ $ip == *:* ]] && is_addr="[$ip]"
        fi
        ;;
    new)
        [[ ! $host && ! $is_naive_domain && ! $is_anytls_domain ]] && get_ip
        [[ ! $port ]] && get_port && port=$tmp_port
        [[ ! $uuid ]] && get_uuid && uuid=$tmp_uuid
        ;;
    file)
        if [[ $2 == */* || $2 == *..* ]]; then
            err "非法的配置文件名称: $2"
        fi
        if [[ $2 && -f "$is_conf_dir/$2" && $2 == *.json ]]; then
            is_config_file=$2
            return
        fi
        is_all_json=()
        local _f _b
        for _f in "$is_conf_dir"/*.json; do
            [[ -f $_f ]] || continue
            _b=$(basename "$_f")
            if [[ ! $2 ]] || grep -Fq -i -- "$2" <<<"$_b"; then
                is_all_json+=("$_b")
                [[ ${#is_all_json[@]} -ge 200 ]] && break
            fi
        done
        [[ ${#is_all_json[@]} -eq 0 ]] && err "无法找到相关的配置文件: ${2:-全部}"
        [[ ${#is_all_json[@]} -eq 1 ]] && is_config_file=${is_all_json[0]} && is_auto_get_config=1
        if [[ ! $is_config_file ]]; then
            [[ $is_dont_auto_exit ]] && return
            ask get_config_file
        fi
        ;;
    info)
        reset_config_vars
        get file "$2"
        if [[ $is_config_file ]]; then
            local fpath="$is_conf_dir/$is_config_file"
            [[ ! -f $fpath ]] && err "无法读取此文件: $is_config_file"
            is_json_str=$(cat "$fpath")
            jq empty <<<"$is_json_str" 2>/dev/null || err "JSON 格式错误: $is_config_file"

            is_protocol=$(jq -r '.inbounds[0].type // empty' <<<"$is_json_str")
            port=$(jq -r '.inbounds[0].listen_port // empty' <<<"$is_json_str")
            uuid=$(jq -r '.inbounds[0].users[0].uuid // empty' <<<"$is_json_str")
            password=$(jq -r '.inbounds[0].users[0].password // empty' <<<"$is_json_str")
            username=$(jq -r '.inbounds[0].users[0].username // empty' <<<"$is_json_str")
            ss_method=$(jq -r '.inbounds[0].method // empty' <<<"$is_json_str")
            ss_password=$(jq -r '.inbounds[0].password // empty' <<<"$is_json_str")
            door_port=$(jq -r '.inbounds[0].override_port // empty' <<<"$is_json_str")
            door_addr=$(jq -r '.inbounds[0].override_address // empty' <<<"$is_json_str")
            net_type=$(jq -r '.inbounds[0].transport.type // empty' <<<"$is_json_str")
            path=$(jq -r '.inbounds[0].transport.path // empty' <<<"$is_json_str")
            host=$(jq -r '.inbounds[0].transport.headers.host // .inbounds[0].transport.host // empty' <<<"$is_json_str")
            is_servername=$(jq -r '.inbounds[0].tls.server_name // empty' <<<"$is_json_str")
            is_private_key=$(jq -r '.inbounds[0].tls.reality.private_key // empty' <<<"$is_json_str")
            is_short_id=$(jq -r '.inbounds[0].tls.reality.short_id[0] // empty' <<<"$is_json_str")
            is_public_key=$(jq -r '(.outbounds // [])[] | select(.tag? | startswith("public_key_")) | .tag' <<<"$is_json_str" | head -n1)

            if [[ $is_private_key ]]; then
                is_reality=1
                net_type="${net_type}reality"
                is_public_key=${is_public_key#public_key_}
            fi

            is_socks_user=$username
            is_socks_pass=$password

            # AnyTLS ACME domain
            if [[ $is_protocol == 'anytls' && ! $is_reality ]]; then
                is_anytls_domain=$(jq -r '(.inbounds[0].tls.certificate_provider.domain[0] // .inbounds[0].tls.acme.domain[0]) // empty' <<<"$is_json_str")
            fi

            # NaiveProxy fields
            if [[ $is_protocol == 'naive' ]]; then
                is_naive_user=$username
                is_naive_pass=$password
                is_naive_domain=$(jq -r '(.inbounds[0].tls.server_name // .inbounds[0].tls.certificate_provider.domain[0] // .inbounds[0].tls.acme.domain[0]) // empty' <<<"$is_json_str")
                is_naive_cert=$(jq -r '.inbounds[0].tls.certificate_path // empty' <<<"$is_json_str")
                is_naive_key=$(jq -r '.inbounds[0].tls.key_path // empty' <<<"$is_json_str")
            fi

            # Snell fields
            if [[ $is_protocol == 'snell' ]]; then
                is_snell_ver=$(jq -r '.inbounds[0].version // 6' <<<"$is_json_str")
                is_snell_psk=$(jq -r '.inbounds[0].psk // empty' <<<"$is_json_str")
                is_snell_mode=$(jq -r '.inbounds[0].mode // empty' <<<"$is_json_str")
                password=$is_snell_psk
            fi

            is_config_name=$is_config_file

            if [[ $is_caddy && $host && -f $is_caddy_conf/$host.conf ]]; then
                is_tmp_https_port=$(grep -Eo "${host}:[1-9][0-9]*" "$is_caddy_conf/$host.conf" | head -n1 | sed 's/.*://')
            fi
            if [[ $host && ! -f $is_caddy_conf/$host.conf ]]; then
                is_no_auto_tls=1
            fi
            [[ $is_tmp_https_port ]] && is_https_port=$is_tmp_https_port

            local _proto_key="$is_protocol"
            [[ $net_type ]] && _proto_key="${is_protocol}-${net_type}"
            [[ $host ]] && _proto_key="${_proto_key}-tls"
            get protocol "$_proto_key"
        fi
        ;;
    protocol)
        get addr
        local is_lower=${2,,}
        net=""
        inbound_json=""
        ensure_self_signed_tls

        case $is_lower in
        vmess*)
            is_protocol=vmess
            if [[ $is_lower == *tcp* || (! $net_type && $is_lower == "vmess") ]]; then
                net=tcp
                inbound_json=$(jq -n --arg u "$uuid" '{users:[{uuid:$u}]}')
            fi
            ;;
        vless*)
            is_protocol=vless
            ;;
        tuic*)
            net=tuic
            is_protocol=tuic
            [[ ! $password ]] && password=$uuid
            inbound_json=$(jq -n \
                --arg u "$uuid" --arg p "$password" \
                --arg k "$is_tls_key" --arg c "$is_tls_cer" \
                '{users:[{uuid:$u,password:$p}],congestion_control:"bbr",tls:{enabled:true,alpn:["h3"],key_path:$k,certificate_path:$c}}')
            ;;
        trojan*)
            is_protocol=trojan
            [[ ! $password ]] && password=$uuid
            if [[ ! $host && $is_lower != *-tls* ]]; then
                net=trojan
                inbound_json=$(jq -n \
                    --arg p "$password" --arg k "$is_tls_key" --arg c "$is_tls_cer" \
                    '{users:[{password:$p}],tls:{enabled:true,key_path:$k,certificate_path:$c}}')
            fi
            ;;
        hysteria2*)
            net=hysteria2
            is_protocol=hysteria2
            [[ ! $password ]] && password=$uuid
            inbound_json=$(jq -n \
                --arg p "$password" --arg k "$is_tls_key" --arg c "$is_tls_cer" \
                '{users:[{password:$p}],tls:{enabled:true,alpn:["h3"],key_path:$k,certificate_path:$c}}')
            ;;
        shadowsocks*)
            net=ss
            is_protocol=shadowsocks
            [[ ! $ss_method ]] && ss_method=$is_random_ss_method
            if [[ ! $ss_password ]]; then
                ss_password=$uuid
                [[ $ss_method == *2022* ]] && ss_password=$(get ss2022)
            fi
            inbound_json=$(jq -n --arg m "$ss_method" --arg p "$ss_password" '{method:$m,password:$p}')
            ;;
        direct*)
            net=direct
            is_protocol=direct
            inbound_json=$(jq -n --argjson dp "$door_port" --arg da "$door_addr" '{override_port:$dp,override_address:$da}')
            ;;
        anytls-reality* | anytls*reality*)
            net=anyreality
            is_protocol=anytls
            is_reality=1
            [[ ! $password ]] && password=$uuid
            [[ ! $is_servername ]] && is_servername=$is_random_servername
            [[ ! $is_private_key ]] && get_pbk
            [[ ! $is_short_id ]] && get_short_id && is_short_id=$tmp_short_id
            inbound_json=$(jq -n \
                --arg p "$password" --arg sni "$is_servername" \
                --arg pk "$is_private_key" --arg sid "$is_short_id" \
                '{users:[{password:$p}],padding_scheme:[],tls:{enabled:true,server_name:$sni,reality:{enabled:true,handshake:{server:$sni,server_port:443},private_key:$pk,short_id:[$sid]}}}')
            ;;
        anytls*)
            net=anytls
            is_protocol=anytls
            [[ ! $password ]] && password=$uuid
            if [[ $is_anytls_domain ]]; then
                if ver_ge "${is_core_ver:-1.14.0}" "1.14.0"; then
                    inbound_json=$(jq -n \
                        --arg p "$password" --arg d "$is_anytls_domain" --arg adir "$is_acme_dir" \
                        '{users:[{password:$p}],tls:{enabled:true,server_name:$d,certificate_provider:{type:"acme",domain:[$d],data_directory:$adir}}}')
                else
                    inbound_json=$(jq -n \
                        --arg p "$password" --arg d "$is_anytls_domain" --arg adir "$is_acme_dir" \
                        '{users:[{password:$p}],tls:{enabled:true,server_name:$d,acme:{domain:[$d],data_directory:$adir}}}')
                fi
            else
                inbound_json=$(jq -n \
                    --arg p "$password" --arg k "$is_tls_key" --arg c "$is_tls_cer" \
                    '{users:[{password:$p}],tls:{enabled:true,key_path:$k,certificate_path:$c}}')
            fi
            ;;
        naive*)
            net=naive
            is_protocol=naive
            [[ ! $is_naive_user ]] && is_naive_user="why666"
            [[ ! $is_naive_pass ]] && is_naive_pass=$uuid
            password=$is_naive_pass
            username=$is_naive_user
            if [[ $is_naive_cert && $is_naive_key ]]; then
                inbound_json=$(jq -n \
                    --arg u "$is_naive_user" --arg p "$is_naive_pass" \
                    --arg d "$is_naive_domain" --arg c "$is_naive_cert" --arg k "$is_naive_key" \
                    '{users:[{username:$u,password:$p}],quic_congestion_control:"bbr",tls:{enabled:true,server_name:$d,certificate_path:$c,key_path:$k}}')
            else
                if ver_ge "${is_core_ver:-1.14.0}" "1.14.0"; then
                    inbound_json=$(jq -n \
                        --arg u "$is_naive_user" --arg p "$is_naive_pass" \
                        --arg d "$is_naive_domain" --arg adir "$is_acme_dir" \
                        '{users:[{username:$u,password:$p}],quic_congestion_control:"bbr",tls:{enabled:true,server_name:$d,certificate_provider:{type:"acme",domain:[$d],data_directory:$adir}}}')
                else
                    inbound_json=$(jq -n \
                        --arg u "$is_naive_user" --arg p "$is_naive_pass" \
                        --arg d "$is_naive_domain" --arg adir "$is_acme_dir" \
                        '{users:[{username:$u,password:$p}],quic_congestion_control:"bbr",tls:{enabled:true,server_name:$d,acme:{domain:[$d],data_directory:$adir}}}')
                fi
            fi
            ;;
        snell*)
            net=snell
            is_protocol=snell
            [[ ! $is_snell_ver ]] && is_snell_ver=6
            [[ ! $is_snell_psk ]] && is_snell_psk=$uuid
            password=$is_snell_psk
            if [[ $is_snell_ver == "6" ]]; then
                [[ ! $is_snell_mode ]] && is_snell_mode=default
                inbound_json=$(jq -n \
                    --argjson ver 6 --arg psk "$is_snell_psk" --arg mode "$is_snell_mode" \
                    '{version:$ver,psk:$psk,mode:$mode}')
            else
                inbound_json=$(jq -n \
                    --argjson ver 5 --arg psk "$is_snell_psk" \
                    '{version:$ver,psk:$psk}')
            fi
            ;;
        socks*)
            net=socks
            is_protocol=socks
            [[ ! $is_socks_user ]] && is_socks_user=why666
            [[ ! $is_socks_pass ]] && is_socks_pass=$uuid
            inbound_json=$(jq -n --arg u "$is_socks_user" --arg p "$is_socks_pass" '{users:[{username:$u,password:$p}]}')
            ;;
        *)
            err "无法识别协议: $2"
            ;;
        esac

        [[ $net ]] && return

        # Transport-based protocols (VMess / VLESS / Trojan)
        local users_json
        if [[ $is_protocol == "trojan" ]]; then
            users_json=$(jq -n --arg p "$password" '[{password:$p}]')
        else
            users_json=$(jq -n --arg u "$uuid" '[{uuid:$u}]')
        fi

        case $is_lower in
        *quic*)
            net=quic
            inbound_json=$(jq -n \
                --argjson users "$users_json" --arg k "$is_tls_key" --arg c "$is_tls_cer" \
                '{users:$users,tls:{enabled:true,alpn:["h3"],key_path:$k,certificate_path:$c},transport:{type:"quic"}}')
            ;;
        *ws*)
            net=ws
            [[ ! $path ]] && path="/$uuid"
            if [[ $host ]]; then
                inbound_json=$(jq -n \
                    --argjson users "$users_json" --arg path "$path" --arg h "$host" \
                    '{users:$users,transport:{type:"ws",path:$path,headers:{host:$h},early_data_header_name:"Sec-WebSocket-Protocol"}}')
            else
                inbound_json=$(jq -n \
                    --argjson users "$users_json" --arg path "$path" \
                    '{users:$users,transport:{type:"ws",path:$path,early_data_header_name:"Sec-WebSocket-Protocol"}}')
            fi
            ;;
        *reality*)
            net=reality
            is_reality=1
            [[ ! $is_servername ]] && is_servername=$is_random_servername
            [[ ! $is_private_key ]] && get_pbk
            local sid_val=${is_short_id:-""}
            if [[ $is_lower == *http* ]]; then
                inbound_json=$(jq -n \
                    --argjson users "$users_json" --arg sni "$is_servername" \
                    --arg pk "$is_private_key" --arg sid "$sid_val" \
                    '{users:$users,tls:{enabled:true,server_name:$sni,reality:{enabled:true,handshake:{server:$sni,server_port:443},private_key:$pk,short_id:[$sid]}},transport:{type:"http"}}')
            else
                users_json=$(jq -n --arg u "$uuid" '[{flow:"xtls-rprx-vision",uuid:$u}]')
                inbound_json=$(jq -n \
                    --argjson users "$users_json" --arg sni "$is_servername" \
                    --arg pk "$is_private_key" --arg sid "$sid_val" \
                    '{users:$users,tls:{enabled:true,server_name:$sni,reality:{enabled:true,handshake:{server:$sni,server_port:443},private_key:$pk,short_id:[$sid]}}}')
            fi
            ;;
        *httpupgrade* | *hu*)
            net=httpupgrade
            [[ ! $path ]] && path="/$uuid"
            inbound_json=$(jq -n \
                --argjson users "$users_json" --arg path "$path" --arg h "$host" \
                '{users:$users,transport:{type:"httpupgrade",path:$path,host:$h}}')
            ;;
        *h2* | *http*)
            if [[ $is_lower == *h2* || $host ]]; then
                net=h2
                [[ ! $path ]] && path="/$uuid"
                inbound_json=$(jq -n \
                    --argjson users "$users_json" --arg path "$path" --arg h "$host" \
                    '{users:$users,transport:{type:"http",path:$path,headers:{host:$h}}}')
            else
                net=http
                inbound_json=$(jq -n --argjson users "$users_json" '{users:$users,transport:{type:"http"}}')
            fi
            ;;
        *)
            err "无法识别传输协议: $is_config_file"
            ;;
        esac
        ;;
    host-test)
        [[ $is_no_auto_tls || $is_gen || $is_dont_test_host || $is_skip_dns_check ]] && return
        get_ip
        get ping
        if ! grep -Fq "$ip" <<<"$is_host_dns"; then
            if [[ $is_non_interactive ]]; then
                warn "域名 ($host) 尚未检测到解析至 ($ip), 已继续执行."
                return
            fi
            msg "\n请将 ($(_red_bg "$host")) 解析到 ($(_red_bg "$ip"))"
            msg "\n如果使用 Cloudflare, 请在 DNS 中关闭代理 (DNS only / 仅限 DNS)"
            ask string y "我已经确定解析 [y]: "
            get ping
            if ! grep -Fq "$ip" <<<"$is_host_dns"; then
                _cyan "\n测试结果: $is_host_dns"
                err "域名 ($host) 没有解析到 ($ip)"
            fi
        fi
        ;;
    ssss | ss2022)
        if [[ $ss_method == *128* ]]; then
            "$is_core_bin" generate rand 16 --base64
        else
            "$is_core_bin" generate rand 32 --base64
        fi
        ;;
    ping)
        local is_dns_type="a"
        [[ $ip == *:* ]] && is_dns_type="aaaa"
        is_host_dns=""
        if [[ $(type -P curl) ]]; then
            is_host_dns=$(curl -fsSL -H "accept: application/dns-json" "https://one.one.one.one/dns-query?name=$host&type=$is_dns_type" 2>/dev/null)
        elif [[ $(type -P wget) ]]; then
            is_host_dns=$(wget -qO- --header="accept: application/dns-json" "https://one.one.one.one/dns-query?name=$host&type=$is_dns_type" 2>/dev/null)
        fi
        ;;
    install-caddy)
        _green "\n安装 Caddy 实现自动配置 TLS.\n"
        load download.sh
        download caddy
        load systemd.sh
        install_service caddy &>/dev/null
        is_caddy=1
        _green "安装 Caddy 成功.\n"
        ;;
    reinstall)
        is_install_sh=$(cat "$is_sh_dir/install.sh")
        uninstall
        bash <<<"$is_install_sh"
        ;;
    test-run)
        if [[ $is_systemd ]]; then
            if ! systemctl list-units --full -all &>/dev/null; then
                _yellow "\n无法执行测试, 请检查 systemctl 状态.\n"
                return
            fi
        fi
        is_no_manage_msg=1
        if ! _is_svc_running "$is_app" "$is_core_bin"; then
            _yellow "\n测试运行 $is_core_name ..\n"
            manage start &>/dev/null
            if [[ $is_run_fail == "$is_core" ]]; then
                _red "$is_core_name 运行失败信息:"
                "$is_core_bin" check -c "$is_config_json" -C "$is_conf_dir"
            else
                _green "\n测试通过, 已启动 $is_core_name ..\n"
            fi
        else
            _green "\n$is_core_name 正在运行, 跳过测试\n"
        fi
        if [[ $is_caddy ]]; then
            if ! _is_svc_running caddy "$is_caddy_bin"; then
                _yellow "\n测试运行 Caddy ..\n"
                manage start caddy &>/dev/null
                if [[ $is_run_fail == 'caddy' ]]; then
                    _red "Caddy 运行失败信息:"
                    "$is_caddy_bin" validate --config "$is_caddyfile"
                else
                    _green "\n测试通过, 已启动 Caddy ..\n"
                fi
            else
                _green "\nCaddy 正在运行, 跳过测试\n"
            fi
        fi
        ;;
    esac
}

info() {
    if [[ $1 || ! $is_protocol ]]; then
        get info "$1"
    fi
    is_color=44
    is_url=""
    is_extra_urls=()
    is_surge_line=""

    case $net in
    ws | tcp | h2 | quic | http*)
        local _raw_host=${is_raw_addr:-$is_addr}
        if [[ $host ]]; then
            is_color=45
            is_can_change=(0 1 2 3 5)
            is_info_show=(0 1 2 3 4 6 7 8)
            if [[ $is_protocol == 'vmess' ]]; then
                is_vmess_url=$(jq -nc \
                    --arg ps "why666-$net-$host" --arg add "$_raw_host" --arg port "$is_https_port" \
                    --arg id "$uuid" --arg net "$net" --arg host "$host" --arg path "$path" \
                    '{v:"2",ps:$ps,add:$add,port:$port,id:$id,aid:"0",net:$net,host:$host,path:$path,tls:"tls"}')
                is_url="vmess://$(printf '%s' "$is_vmess_url" | _base64)"
            else
                local _cred=$uuid
                if [[ $is_protocol == "trojan" ]]; then
                    _cred=$password
                    is_can_change=(0 1 2 3 4)
                    is_info_show=(0 1 2 10 4 6 7 8)
                fi
                local _enc_cred _enc_path
                _enc_cred=$(_urlencode "$_cred")
                _enc_path=$(_urlencode_path "$path")
                is_url="$is_protocol://$_enc_cred@$host:$is_https_port?encryption=none&security=tls&type=$net&host=$host&sni=$host&path=$_enc_path#why666-$net-$host"
            fi
            [[ $is_caddy ]] && is_can_change+=(11)
            is_info_str=("$is_protocol" "$is_addr" "$is_https_port" "${_cred:-$uuid}" "$net" "$host" "$path" "tls")
        else
            is_type=none
            is_can_change=(0 1 5)
            is_info_show=(0 1 2 3 4)
            is_info_str=("$is_protocol" "$is_addr" "$port" "$uuid" "$net")
            if [[ $net == "ws" ]]; then
                is_can_change=(0 1 3 5)
                is_info_show=(0 1 2 3 4 7)
                is_info_str=("$is_protocol" "$is_addr" "$port" "$uuid" "$net" "$path")
            fi
            if [[ $net == "http" ]]; then
                is_tcp_http=1
                is_info_str=("$is_protocol" "$is_addr" "$port" "$uuid" "http")
            fi
            if [[ $net == "quic" ]]; then
                is_insecure=1
                is_info_show+=(8 9 20)
                is_info_str+=(tls h3 true)
            fi
            if [[ $is_protocol == "vless" ]]; then
                local _enc_path
                _enc_path=$(_urlencode_path "$path")
                is_url="vless://$uuid@$is_addr:$port?encryption=none&security=none&type=$net&path=$_enc_path#why666-vless-$net-$is_raw_addr"
            else
                if [[ $net == "quic" ]]; then
                    is_vmess_url=$(jq -nc \
                        --arg ps "why666-$net-$_raw_host" --arg add "$_raw_host" --arg port "$port" \
                        --arg id "$uuid" --arg net "$net" --arg type "$is_type" \
                        '{v:"2",ps:$ps,add:$add,port:$port,id:$id,aid:"0",net:$net,type:$type,tls:"tls",alpn:"h3"}')
                elif [[ $net == "ws" ]]; then
                    is_vmess_url=$(jq -nc \
                        --arg ps "why666-$net-$_raw_host" --arg add "$_raw_host" --arg port "$port" \
                        --arg id "$uuid" --arg net "$net" --arg path "$path" \
                        '{v:"2",ps:$ps,add:$add,port:$port,id:$id,aid:"0",net:$net,type:"none",path:$path,tls:""}')
                else
                    is_vmess_url=$(jq -nc \
                        --arg ps "why666-$net-$_raw_host" --arg add "$_raw_host" --arg port "$port" \
                        --arg id "$uuid" --arg net "$net" --arg type "$is_type" \
                        '{v:"2",ps:$ps,add:$add,port:$port,id:$id,aid:"0",net:$net,type:$type}')
                fi
                is_url="vmess://$(printf '%s' "$is_vmess_url" | _base64)"
            fi
        fi
        ;;
    ss)
        is_can_change=(0 1 4 6)
        is_info_show=(0 1 2 10 11)
        is_url="ss://$(printf '%s:%s' "$ss_method" "$ss_password" | _base64)@${is_addr}:${port}#why666-ss-${is_raw_addr:-$is_addr}"
        is_info_str=("$is_protocol" "$is_addr" "$port" "$ss_password" "$ss_method")
        ;;
    trojan)
        is_insecure=1
        is_can_change=(0 1 4)
        is_info_show=(0 1 2 10 4 8 20)
        local _enc_pass
        _enc_pass=$(_urlencode "$password")
        is_url="trojan://$_enc_pass@$is_addr:$port?type=tcp&security=tls&insecure=1&allowInsecure=1#why666-trojan-${is_raw_addr:-$is_addr}"
        is_info_str=("$is_protocol" "$is_addr" "$port" "$password" "tcp" "tls" "true")
        ;;
    hysteria2 | hy*)
        is_can_change=(0 1 4)
        is_info_show=(0 1 2 10 8 9 20)
        is_sha256=$(openssl x509 -noout -fingerprint -sha256 -in "$is_core_dir/bin/tls.cer" 2>/dev/null | sed 's/.*=//;s/://g')
        local _enc_pass
        _enc_pass=$(_urlencode "$password")
        is_url="hysteria2://$_enc_pass@$is_addr:$port?alpn=h3&insecure=1&allowInsecure=1&pinSHA256=$is_sha256#why666-hy2-${is_raw_addr:-$is_addr}"
        is_info_str=("$is_protocol" "$is_addr" "$port" "$password" "tls" "h3" "true (pinSHA256: $is_sha256)")
        ;;
    tuic)
        is_insecure=1
        is_can_change=(0 1 4 5)
        is_info_show=(0 1 2 3 10 8 9 20 21)
        local _enc_pass
        _enc_pass=$(_urlencode "$password")
        is_url="tuic://$uuid:$_enc_pass@$is_addr:$port?alpn=h3&insecure=1&allowInsecure=1&congestion_control=bbr#why666-tuic-${is_raw_addr:-$is_addr}"
        is_info_str=("$is_protocol" "$is_addr" "$port" "$uuid" "$password" "tls" "h3" "true" "bbr")
        ;;
    reality)
        is_color=41
        is_can_change=(0 1 5 9 10)
        is_info_show=(0 1 2 3 15 4 8 16 17 18)
        is_flow=xtls-rprx-vision
        is_net_type=tcp
        if [[ $net_type == *http* || ${is_new_protocol,,} == *http* ]]; then
            is_flow=""
            is_net_type=h2
            is_info_show=(0 1 2 3 4 8 16 17 18)
            is_info_str=("$is_protocol" "$is_addr" "$port" "$uuid" "$is_net_type" "reality" "$is_servername" "chrome" "$is_public_key")
        else
            is_info_str=("$is_protocol" "$is_addr" "$port" "$uuid" "$is_flow" "$is_net_type" "reality" "$is_servername" "chrome" "$is_public_key")
        fi
        local _sid_q=""
        [[ $is_short_id ]] && _sid_q="&sid=$is_short_id"
        is_url="vless://$uuid@$is_addr:$port?encryption=none&security=reality&flow=$is_flow&type=$is_net_type&sni=$is_servername&pbk=$is_public_key${_sid_q}&fp=chrome#why666-reality-${is_raw_addr:-$is_addr}"
        ;;
    anyreality)
        is_color=41
        is_can_change=(0 1 4 9 10)
        is_info_show=(0 1 2 10 8 16 17 18 22)
        is_info_str=("anytls-reality" "$is_addr" "$port" "$password" "reality" "$is_servername" "chrome" "$is_public_key" "$is_short_id")
        local _enc_pass
        _enc_pass=$(_urlencode "$password")
        is_url="anytls://$_enc_pass@$is_addr:$port?security=reality&sni=$is_servername&fp=chrome&pbk=$is_public_key&sid=$is_short_id#why666-anyreality-${is_raw_addr:-$is_addr}"
        ;;
    anytls)
        is_can_change=(0 1 2 4)
        local _enc_pass
        _enc_pass=$(_urlencode "$password")
        if [[ $is_anytls_domain ]]; then
            is_info_show=(0 1 2 10 8)
            is_info_str=("$is_protocol" "$is_anytls_domain" "$port" "$password" "tls (ACME)")
            is_url="anytls://$_enc_pass@$is_anytls_domain:$port?sni=$is_anytls_domain#why666-anytls-$is_anytls_domain"
        else
            is_insecure=1
            is_info_show=(0 1 2 10 8 20)
            is_info_str=("$is_protocol" "$is_addr" "$port" "$password" "tls" "true")
            is_url="anytls://$_enc_pass@$is_addr:$port?insecure=1&allowInsecure=1#why666-anytls-${is_raw_addr:-$is_addr}"
        fi
        ;;
    naive)
        is_color=42
        is_can_change=(0 1 2 12 4)
        local _tls_desc="tls (ACME)"
        [[ $is_naive_cert ]] && _tls_desc="tls (custom cert)"
        is_info_show=(0 1 2 19 10 8 21)
        is_info_str=("naive (H2+H3)" "$is_naive_domain" "$port" "$is_naive_user" "$is_naive_pass" "$_tls_desc" "bbr")
        local _enc_u _enc_p
        _enc_u=$(_urlencode "$is_naive_user")
        _enc_p=$(_urlencode "$is_naive_pass")
        local _nv_h2="naive+https://${_enc_u}:${_enc_p}@${is_naive_domain}:${port}?security=tls&sni=${is_naive_domain}#why666-naive-h2-${is_naive_domain}"
        local _nv_h3="naive+quic://${_enc_u}:${_enc_p}@${is_naive_domain}:${port}?congestion_control=bbr&security=tls&sni=${is_naive_domain}#why666-naive-h3-${is_naive_domain}"
        local _nv_sr2="http2://${_enc_u}:${_enc_p}@${is_naive_domain}:${port}?security=tls&sni=${is_naive_domain}&padding=1&tfo=1#why666-naive-h2-${is_naive_domain}"
        local _nv_sr3="http3://${_enc_u}:${_enc_p}@${is_naive_domain}:${port}?security=tls&sni=${is_naive_domain}&padding=1&tfo=1#why666-naive-h3-${is_naive_domain}"
        is_url="$_nv_h2"
        is_extra_urls=(
            "Naive H2 (V2rayN/Karing/Nekobox)|$_nv_h2"
            "Naive H3/QUIC (V2rayN/Karing/Nekobox)|$_nv_h3"
            "Shadowrocket H2|$_nv_sr2"
            "Shadowrocket H3|$_nv_sr3"
        )
        ;;
    snell)
        is_color=46
        is_can_change=(0 1 4)
        local _sn_mode=${is_snell_mode:-default}
        local _raw_host=${is_raw_addr:-$is_addr}
        local _enc_psk
        _enc_psk=$(_urlencode "$is_snell_psk")
        if [[ $is_snell_ver == "6" ]]; then
            is_info_show=(0 1 2 10 23 24)
            is_info_str=("snell" "$is_addr" "$port" "$is_snell_psk" "v6" "$_sn_mode")
            local _sn_url="snell://${_enc_psk}@${is_addr}:${port}?version=6&reuse=true&mode=${_sn_mode}#why666-snell6-${_raw_host}"
            local _sn_sr="snell://$(printf 'chacha20-ietf-poly1305:%s@%s:%s' "$is_snell_psk" "$is_addr" "$port" | _base64)?tfo=1&version=6&reuse=1&mode=${_sn_mode}&udp=1#why666-snell6-${_raw_host}"
            is_url="$_sn_url"
            is_extra_urls=(
                "Nekobox/sing-box|$_sn_url"
                "Shadowrocket|$_sn_sr"
            )
            is_surge_line="why666-snell = snell, ${_raw_host}, ${port}, psk=${is_snell_psk}, version=6, reuse=true"
        else
            is_info_show=(0 1 2 10 23)
            is_info_str=("snell" "$is_addr" "$port" "$is_snell_psk" "v5")
            local _sn_url="snell://${_enc_psk}@${is_addr}:${port}?version=5&reuse=true#why666-snell5-${_raw_host}"
            local _sn_sr="snell://$(printf 'chacha20-ietf-poly1305:%s@%s:%s' "$is_snell_psk" "$is_addr" "$port" | _base64)?tfo=1&version=5&reuse=1&udp=1#why666-snell5-${_raw_host}"
            is_url="$_sn_url"
            is_extra_urls=(
                "Nekobox/sing-box|$_sn_url"
                "Shadowrocket|$_sn_sr"
            )
            is_surge_line="why666-snell = snell, ${_raw_host}, ${port}, psk=${is_snell_psk}, version=5, reuse=true"
        fi
        ;;
    direct)
        is_can_change=(0 1 7 8)
        is_info_show=(0 1 2 13 14)
        is_info_str=("$is_protocol" "$is_addr" "$port" "$door_addr" "$door_port")
        ;;
    socks)
        is_can_change=(0 1 12 4)
        is_info_show=(0 1 2 19 10)
        is_info_str=("$is_protocol" "$is_addr" "$port" "$is_socks_user" "$is_socks_pass")
        is_url="socks://$(printf '%s:%s' "$is_socks_user" "$is_socks_pass" | _base64)@${is_addr}:${port}#why666-socks-${is_raw_addr:-$is_addr}"
        ;;
    esac

    [[ $is_dont_show_info || $is_gen || $is_dont_auto_exit || $is_quiet ]] && return

    msg "-------------- $is_config_name -------------"
    local i a tt
    for ((i = 0; i < ${#is_info_show[@]}; i++)); do
        a=${info_list[${is_info_show[$i]}]}
        if [[ ${#a} -ge 12 ]]; then
            tt='\t'
        else
            tt='\t\t'
        fi
        msg "$a ${tt}= \e[${is_color}m${is_info_str[$i]}\e[0m"
    done

    if [[ ${#is_extra_urls[@]} -gt 0 ]]; then
        msg "------------- ${info_list[12]} -------------"
        local item label val
        for item in "${is_extra_urls[@]}"; do
            label=${item%%|*}
            val=${item#*|}
            msg "$(_yellow "$label"):"
            msg "\e[4;${is_color}m${val}\e[0m"
        done
        [[ $is_surge_line ]] && {
            msg "$(_yellow "Surge 配置行"):"
            msg "\e[${is_color}m${is_surge_line}\e[0m"
        }
        [[ $net == "snell" ]] && {
            msg "$(_gray "提示: 部分 NekoBox (Mihomo) 版本导入 snell:// 链接时可能漏填 PSK, 若报 psk length 错误请点编辑节点手动填入上方密码.")"
        }
    elif [[ $is_url ]]; then
        msg "------------- ${info_list[12]} -------------"
        msg "\e[4;${is_color}m${is_url}\e[0m"
        [[ $is_insecure ]] && {
            warn "客户端导入自签证书节点时需开启: 跳过证书验证 (allowInsecure / insecure=true)"
        }
    fi

    if [[ $is_no_auto_tls ]]; then
        msg "------------- no-auto-tls INFO -------------"
        msg "端口(port): $port"
        msg "路径(path): $path"
    fi
    footer_msg
}

footer_msg() {
    [[ $is_core_stop && ! $is_new_json ]] && warn "$is_core_name 当前处于停止状态."
    [[ $is_caddy_stop && $host ]] && warn "Caddy 当前处于停止状态."
    msg "------------- END -------------"
    msg "命令: $(_green "$is_app") (短命令: $(_green "yy")) | CF Argo: $(_cyan "$is_app argo") | AI 导出: $(_cyan "$is_app ai json")"
    msg "仓库: $(msg_ul "https://github.com/${is_sh_repo}")\n"
}

url_qr() {
    is_dont_show_info=1
    info "$2"
    is_dont_show_info=
    if [[ $is_url ]]; then
        if [[ $1 == 'url' ]]; then
            msg "\n------------- $is_config_name & URL 链接 -------------"
            if [[ ${#is_extra_urls[@]} -gt 0 ]]; then
                local item label val
                for item in "${is_extra_urls[@]}"; do
                    label=${item%%|*}
                    val=${item#*|}
                    msg "\n$(_yellow "$label"):"
                    msg "\e[${is_color}m${val}\e[0m"
                done
                echo
            else
                msg "\n\e[${is_color}m${is_url}\e[0m\n"
            fi
            footer_msg
        else
            msg "\n------------- $is_config_name & QR code 二维码 -------------"
            msg
            if [[ $(type -P qrencode) ]]; then
                qrencode -t ANSIUTF8 "${is_url}" 2>/dev/null || qrencode -t ANSI "${is_url}"
            else
                msg "请安装 qrencode: $(_green "$cmd install -y qrencode")"
            fi
            msg "\n\e[${is_color}m${is_url}\e[0m\n"
            footer_msg
        fi
    else
        err "($is_config_name) 无法生成 URL / 二维码."
    fi
}

update() {
    case $1 in
    1 | core | $is_core)
        is_update_name=core
        is_show_name=$is_core_name
        is_run_ver=v${is_core_ver#v}
        is_update_repo=$is_core_repo
        ;;
    2 | sh)
        is_update_name=sh
        is_show_name="$is_app 脚本"
        is_run_ver=$is_sh_ver
        is_update_repo=$is_sh_repo
        ;;
    3 | caddy)
        [[ ! $is_caddy ]] && err "尚未安装 Caddy, 无需更新."
        is_update_name=caddy
        is_show_name="Caddy"
        is_run_ver=$is_caddy_ver
        is_update_repo=$is_caddy_repo
        ;;
    4 | argo | cloudflared)
        [[ ! $is_argo_installed ]] && err "尚未安装 Cloudflared, 请先运行 $is_app argo."
        is_update_name=argo
        is_show_name="Cloudflared"
        is_run_ver=$is_argo_ver
        is_update_repo=$is_argo_repo
        ;;
    *)
        err "无法识别 ($1), 请使用: $is_app update [core | sh | caddy | argo] [ver]"
        ;;
    esac
    if [[ $2 ]]; then
        if [[ $is_update_name == "argo" ]]; then
            is_new_ver=${2#v}
        else
            is_new_ver=v${2#v}
        fi
    fi
    [[ $is_run_ver == "$is_new_ver" ]] && {
        msg "\n自定义版本和当前 $is_show_name 版本一致, 无需更新.\n"
        exit 0
    }
    load download.sh
    if [[ $is_new_ver ]]; then
        msg "\n使用自定义版本更新 $is_show_name: $(_green "$is_new_ver")\n"
    else
        if [[ $is_update_name == "sh" ]]; then
            # If no GitHub release exists yet, pull latest main directly
            local _sh_api
            _sh_api=$(_fetch "https://api.github.com/repos/$is_sh_repo/releases/latest?v=$RANDOM")
            latest_ver=$(grep -m1 '"tag_name"' <<<"$_sh_api" | grep -Eo 'v[0-9.]+')
            if [[ ! $latest_ver ]]; then
                msg "\n从 main 分支拉取最新脚本...\n"
                download sh_main
                msg "脚本已更新至最新 main 版本.\n"
                exit 0
            fi
        else
            get_latest_version "$is_update_name"
        fi
        [[ $is_run_ver == "$latest_ver" ]] && {
            msg "\n$is_show_name 当前已经是最新版本 ($latest_ver).\n"
            exit 0
        }
        msg "\n发现 $is_show_name 新版本: $(_green "$latest_ver")\n"
        is_new_ver=$latest_ver
    fi
    download "$is_update_name" "$is_new_ver"
    msg "更新成功, 当前 $is_show_name 版本: $(_green "$is_new_ver")\n"
    msg "$(_green "更新说明: https://github.com/$is_update_repo/releases/tag/$is_new_ver")\n"
    if [[ $is_update_name != 'sh' ]]; then
        manage restart "$is_update_name" &
    fi
    return 0
}

is_main_menu() {
    msg "\n------------- $is_app script $is_sh_ver by $author -------------"
    msg "$is_core_name ${is_core_ver:-unknown}: $is_core_status"
    [[ $is_caddy ]] && msg "Caddy ${is_caddy_ver}: $is_caddy_status"
    [[ $is_argo_installed ]] && msg "CF Argo ${is_argo_ver}: $is_argo_status"
    msg "仓库(GitHub): $(msg_ul "https://github.com/${is_sh_repo}")"
    is_main_start=1
    ask mainmenu
    case $REPLY in
    1) add ;;
    2) change ;;
    3) info ;;
    4) del ;;
    5)
        load argo.sh
        argo_menu
        ;;
    6)
        load ai.sh
        ai_menu
        ;;
    7)
        ask list is_do_manage "启动 停止 重启"
        manage "$REPLY" &
        msg "\n管理状态执行: $(_green "$is_do_manage")\n"
        ;;
    8)
        is_tmp_list=("更新 $is_core_name" "更新脚本")
        [[ $is_caddy ]] && is_tmp_list+=("更新 Caddy")
        [[ $is_argo_installed ]] && is_tmp_list+=("更新 Cloudflared (Argo)")
        ask list is_do_update null "\n请选择更新:\n"
        case $is_do_update in
        *脚本*) update sh ;;
        *Caddy*) update caddy ;;
        *Argo*) update argo ;;
        *) update core ;;
        esac
        ;;
    9) uninstall ;;
    10)
        msg
        load help.sh
        show_help
        ;;
    11)
        ask list is_do_other "启用BBR 查看日志 测试运行 重装脚本 设置DNS 导入旧配置"
        case $REPLY in
        1)
            load bbr.sh
            _try_enable_bbr
            ;;
        2)
            load log.sh
            log_set
            ;;
        3) get test-run ;;
        4) get reinstall ;;
        5)
            load dns.sh
            dns_set
            ;;
        6) load import.sh ;;
        esac
        ;;
    12)
        load help.sh
        about
        ;;
    esac
}

main() {
    case $1 in
    a | add | gen | no-auto-tls)
        [[ $1 == 'gen' ]] && is_gen=1
        [[ $1 == 'no-auto-tls' ]] && is_no_auto_tls=1
        add "${@:2}"
        ;;
    argo | cf)
        load argo.sh
        argo_main "${@:2}"
        ;;
    ai)
        load ai.sh
        ai_main "${@:2}"
        ;;
    bin | pbk | check | completion | format | generate | geoip | geosite | merge | rule-set | run | tools)
        is_run_command=$1
        if [[ $1 == 'bin' ]]; then
            "$is_core_bin" "${@:2}"
        else
            [[ $is_run_command == 'pbk' ]] && "$is_core_bin" generate reality-keypair "${@:2}" && return
            "$is_core_bin" "$is_run_command" "${@:2}"
        fi
        ;;
    bbr)
        load bbr.sh
        _try_enable_bbr
        ;;
    c | config | change)
        change "${@:2}"
        ;;
    d | del | rm)
        del "$2"
        ;;
    dd | ddel | fix | fix-all)
        case $1 in
        fix)
            if [[ $2 ]]; then
                change "$2" full
            else
                is_change_id=full && change
            fi
            return
            ;;
        fix-all)
            is_dont_auto_exit=1
            msg
            for v in $(ls "$is_conf_dir" 2>/dev/null | grep '\.json$'); do
                msg "fix: $v"
                change "$v" full
            done
            _green "\nfix 完成.\n"
            ;;
        *)
            is_dont_auto_exit=1
            if [[ ! $2 ]]; then
                err "无法找到需要删除的参数"
            else
                for v in "${@:2}"; do
                    del "$v"
                done
            fi
            ;;
        esac
        is_dont_auto_exit=
        manage restart &
        if [[ $is_del_host ]]; then
            manage restart caddy &
        fi
        ;;
    dns)
        load dns.sh
        dns_set "${@:2}"
        ;;
    debug)
        is_debug=1
        get info "$2"
        jq . "$is_conf_dir/$is_config_file"
        warn "分享调试信息前请注意脱敏 uuid / password / private_key / host."
        ;;
    fix-config.json)
        create config.json
        ;;
    fix-caddyfile)
        if [[ $is_caddy ]]; then
            load caddy.sh
            caddy_config new
            manage restart caddy &
            _green "\nfix 完成.\n"
        else
            err "尚未安装 Caddy."
        fi
        ;;
    i | info | list | ls)
        if [[ $1 == "list" || $1 == "ls" ]]; then
            local files
            files=$(ls "$is_conf_dir" 2>/dev/null | grep '\.json$')
            if [[ ! $files ]]; then
                warn "当前没有节点配置."
            else
                msg "\n当前已配置节点列表:"
                echo "$files" | nl -w2 -s') '
                echo
            fi
            if [[ -f $is_argo_conf ]]; then
                msg "CF Argo 隧道: $(_green "已启用") ($(jq -r '.mode + " / " + .domain' "$is_argo_conf" 2>/dev/null))\n"
            fi
        else
            info "$2"
        fi
        ;;
    ip)
        get_ip
        msg "$ip"
        ;;
    in | import)
        load import.sh
        ;;
    log)
        load log.sh
        log_set "$2"
        ;;
    url | qr)
        url_qr "$@"
        ;;
    un | uninstall)
        uninstall
        ;;
    u | up | update | U | update.sh)
        is_update_name=$2
        is_update_ver=$3
        [[ ! $is_update_name ]] && is_update_name=core
        if [[ $1 == 'U' || $1 == 'update.sh' ]]; then
            is_update_name=sh
            is_update_ver=
        fi
        update "$is_update_name" "$is_update_ver"
        ;;
    ssss | ss2022)
        get "$@"
        ;;
    s | status)
        msg "\n$is_core_name ${is_core_ver}: $is_core_status"
        [[ $is_caddy ]] && msg "Caddy ${is_caddy_ver}: $is_caddy_status"
        [[ $is_argo_installed ]] && msg "CF Argo ${is_argo_ver}: $is_argo_status"
        msg
        ;;
    start | stop | r | restart)
        [[ $2 && $2 != 'caddy' && $2 != 'argo' ]] && err "无法识别 ($2), 请使用: $is_app $1 [caddy | argo]"
        manage "$1" "$2" &
        ;;
    t | test)
        get test-run
        ;;
    reinstall)
        get "$1"
        ;;
    get-port)
        get_port
        msg "$tmp_port"
        ;;
    main)
        is_main_menu
        ;;
    v | ver | version)
        local extra=""
        [[ $is_caddy_ver ]] && extra+=" / $(_blue "Caddy $is_caddy_ver")"
        [[ $is_argo_ver ]] && extra+=" / $(_magenta "Argo $is_argo_ver")"
        msg "\n$(_green "$is_core_name $is_core_ver") / $(_cyan "$is_app script $is_sh_ver")${extra}\n"
        ;;
    h | help | --help)
        load help.sh
        show_help "${@:2}"
        ;;
    *)
        is_try_change=1
        change test "$1"
        if [[ $is_change_id ]]; then
            unset is_try_change
            if [[ $2 ]]; then
                change "$2" "$1" "${@:3}"
            else
                change
            fi
        else
            err "无法识别 ($1), 获取帮助请使用: $is_app help"
        fi
        ;;
    esac
}
