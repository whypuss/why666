# detect init system
is_systemd=$(type -P systemctl)
is_openrc=$(type -P rc-service)

install_service() {
    if [[ $is_systemd ]]; then
        install_service_systemd "$@"
    elif [[ $is_openrc ]]; then
        install_service_openrc "$@"
    fi
}

install_service_systemd() {
    case $1 in
    $is_app | $is_core)
        local svc_name=$is_app
        cat >/lib/systemd/system/${svc_name}.service <<EOF
[Unit]
Description=why666 (sing-box) Service
Documentation=https://github.com/${is_sh_repo}
After=network.target nss-lookup.target

[Service]
User=root
NoNewPrivileges=true
ExecStart=${is_core_bin} run -c ${is_config_json} -C ${is_conf_dir}
Restart=on-failure
RestartPreventExitStatus=23
LimitNPROC=10000
LimitNOFILE=1048576
PrivateTmp=true
ProtectSystem=full

[Install]
WantedBy=multi-user.target
EOF
        systemctl enable "$svc_name"
        systemctl daemon-reload
        ;;
    caddy)
        cat >/lib/systemd/system/caddy.service <<EOF
[Unit]
Description=Caddy
Documentation=https://caddyserver.com/docs/
After=network.target network-online.target
Requires=network-online.target

[Service]
Type=notify
User=root
Group=root
ExecStart=${is_caddy_bin} run --environ --config ${is_caddyfile} --adapter caddyfile
ExecReload=${is_caddy_bin} reload --config ${is_caddyfile} --adapter caddyfile
TimeoutStopSec=5s
LimitNPROC=10000
LimitNOFILE=1048576
PrivateTmp=true
ProtectSystem=full

[Install]
WantedBy=multi-user.target
EOF
        systemctl enable caddy
        systemctl daemon-reload
        ;;
    argo | $is_argo_service_name)
        local argo_mode=$2
        local argo_proto=${3:-http2}
        local argo_target=$4
        [[ $argo_proto != "quic" ]] && argo_proto="http2"
        local exec_cmd=""
        if [[ $argo_mode == "fixed" ]]; then
            mkdir -m 700 -p "$is_argo_dir"
            local token_file="$is_argo_dir/token"
            (umask 077 && printf '%s' "$argo_target" >"$token_file")
            chmod 600 "$token_file"
            exec_cmd="${is_argo_bin} tunnel --no-autoupdate --edge-ip-version auto --protocol ${argo_proto} run --token-file ${token_file}"
        else
            [[ ! $argo_target =~ ^[0-9]+$ ]] && return 1
            exec_cmd="/bin/sh -c 'exec ${is_argo_bin} tunnel --no-autoupdate --edge-ip-version auto --protocol ${argo_proto} --url http://127.0.0.1:${argo_target} >${is_argo_log} 2>&1'"
        fi
        cat >/lib/systemd/system/${is_argo_service_name}.service <<EOF
[Unit]
Description=why666 Cloudflare Argo Tunnel Service
Documentation=https://github.com/${is_sh_repo}
After=network.target network-online.target

[Service]
Type=simple
User=root
NoNewPrivileges=true
ExecStart=${exec_cmd}
Restart=on-failure
RestartSec=5s
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF
        systemctl enable "$is_argo_service_name"
        systemctl daemon-reload
        ;;
    esac
}

install_service_openrc() {
    case $1 in
    $is_app | $is_core)
        local svc_name=$is_app
        cat >/etc/init.d/${svc_name} <<EOF
#!/sbin/openrc-run

name="why666 (sing-box)"
description="why666 sing-box Service"

command="${is_core_bin}"
command_args="run -c ${is_config_json} -C ${is_conf_dir}"
command_background=true
pidfile="/run/\${RC_SVCNAME}.pid"
error_log="${is_log_dir}/error.log"

supervisor=supervise-daemon

depend() {
    need net
    after firewall
}
EOF
        chmod +x "/etc/init.d/${svc_name}"
        rc-update add "$svc_name" default
        ;;
    caddy)
        cat >/etc/init.d/caddy <<EOF
#!/sbin/openrc-run

name="Caddy"
description="Caddy web server"

command="${is_caddy_bin}"
command_args="run --environ --config ${is_caddyfile} --adapter caddyfile"
command_background=true
pidfile="/run/\${RC_SVCNAME}.pid"

supervisor=supervise-daemon

depend() {
    need net
    after firewall
}
EOF
        chmod +x /etc/init.d/caddy
        rc-update add caddy default
        ;;
    argo | $is_argo_service_name)
        local argo_mode=$2
        local argo_proto=${3:-http2}
        local argo_target=$4
        [[ $argo_proto != "quic" ]] && argo_proto="http2"
        local cmd_args=""
        if [[ $argo_mode == "fixed" ]]; then
            mkdir -m 700 -p "$is_argo_dir"
            local token_file="$is_argo_dir/token"
            (umask 077 && printf '%s' "$argo_target" >"$token_file")
            chmod 600 "$token_file"
            cmd_args="tunnel --no-autoupdate --edge-ip-version auto --protocol ${argo_proto} run --token-file ${token_file}"
        else
            [[ ! $argo_target =~ ^[0-9]+$ ]] && return 1
            cmd_args="tunnel --no-autoupdate --edge-ip-version auto --protocol ${argo_proto} --url http://127.0.0.1:${argo_target}"
        fi
        cat >/etc/init.d/${is_argo_service_name} <<EOF
#!/sbin/openrc-run

name="why666-argo"
description="why666 Cloudflare Argo Tunnel"

command="${is_argo_bin}"
command_args="${cmd_args}"
command_background=true
pidfile="/run/\${RC_SVCNAME}.pid"
output_log="${is_argo_log}"
error_log="${is_argo_log}"

supervisor=supervise-daemon

depend() {
    need net
    after firewall
}
EOF
        chmod +x "/etc/init.d/${is_argo_service_name}"
        rc-update add "$is_argo_service_name" default
        ;;
    esac
}
