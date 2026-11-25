#!/bin/bash

author=whypuss
project=why666
# github=https://github.com/whypuss/why666

# bash fonts colors
red='\e[31m'
yellow='\e[33m'
gray='\e[90m'
green='\e[92m'
blue='\e[94m'
magenta='\e[95m'
cyan='\e[96m'
none='\e[0m'

_red() { echo -e "${red}$*${none}"; }
_gray() { echo -e "${gray}$*${none}"; }
_blue() { echo -e "${blue}$*${none}"; }
_cyan() { echo -e "${cyan}$*${none}"; }
_green() { echo -e "${green}$*${none}"; }
_yellow() { echo -e "${yellow}$*${none}"; }
_magenta() { echo -e "${magenta}$*${none}"; }
_red_bg() { echo -e "\e[41m$*${none}"; }

_rm() { rm -rf "$@"; }
_cp() { cp -rf "$@"; }
_sed() { sed -i "$@"; }
_mkdir() { mkdir -p "$@"; }

_base64() {
    if base64 -w 0 </dev/null &>/dev/null; then
        base64 -w 0
    else
        base64 | tr -d '\n'
    fi
}

is_err=$(_red_bg 错误!)
is_warn=$(_red_bg 警告!)

err() {
    if [[ $is_json_out ]]; then
        local _plain
        _plain=$(sed -E 's/\x1b\[[0-9;]*m//g; s/\\e\[[0-9;]*m//g' <<<"$*" | tr '\n' ' ' | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')
        if type -P jq &>/dev/null; then
            jq -nc --arg e "$_plain" '{ok:false,error:$e}'
        else
            printf '{"ok":false,"error":"%s"}\n' "${_plain//\"/\\\"}"
        fi
    else
        echo -e "\n$is_err $*\n" >&2
    fi
    [[ $is_dont_auto_exit ]] && return 1
    exit 1
}

warn() {
    [[ $is_quiet || $is_json_out ]] && return
    echo -e "\n$is_warn $*\n" >&2
}

load() {
    . "$is_sh_dir/src/$1"
}

_wget() {
    [[ $proxy ]] && export https_proxy=$proxy http_proxy=$proxy
    wget "$@"
}

_fetch() {
    [[ $proxy ]] && export https_proxy=$proxy http_proxy=$proxy
    local url=$1
    local out=$2
    if [[ $(type -P curl) ]]; then
        if [[ $out ]]; then
            curl -fsSL --retry 3 --connect-timeout 15 --max-time 60 "$url" -o "$out"
        else
            curl -fsSL --retry 2 --connect-timeout 10 --max-time 30 "$url"
        fi
    elif [[ $(type -P wget) ]]; then
        if [[ $out ]]; then
            wget -T 30 -t 3 -q -O "$out" "$url"
        else
            wget -T 20 -t 2 -qO- "$url"
        fi
    else
        return 1
    fi
}

# package manager
cmd=$(type -P apt-get || type -P dnf || type -P yum || type -P zypper || type -P apk)

# architecture
case $(uname -m) in
amd64 | x86_64)
    is_arch="amd64"
    ;;
*aarch64* | *armv8*)
    is_arch="arm64"
    ;;
*)
    err "此脚本仅支持 64 位系统 (amd64 / arm64)..."
    ;;
esac

is_app=why666
is_core=sing-box
is_core_name=sing-box
is_core_dir=/etc/$is_app
is_core_bin=$is_core_dir/bin/$is_core
is_core_repo=SagerNet/$is_core
is_conf_dir=$is_core_dir/conf
is_acme_dir=$is_core_dir/acme
is_argo_dir=$is_core_dir/argo
is_argo_bin=$is_core_dir/bin/cloudflared
is_argo_conf=$is_argo_dir/config.json
is_argo_log=/var/log/$is_app/argo.log
is_argo_service_name=${is_app}-argo
is_argo_repo=cloudflare/cloudflared
is_log_dir=/var/log/$is_app
is_sh_bin=/usr/local/bin/$is_app
is_sh_short_bin=/usr/local/bin/yy
is_sh_dir=$is_core_dir/sh
is_sh_repo=$author/$project
is_pkg="wget curl unzip tar qrencode bash openssl"
is_config_json=$is_core_dir/config.json
is_caddy_bin=/usr/local/bin/caddy
is_caddy_dir=/etc/caddy
is_caddy_repo=caddyserver/caddy
is_caddyfile=$is_caddy_dir/Caddyfile
is_caddy_conf=$is_caddy_dir/$is_app
is_systemd=$(type -P systemctl)
is_openrc=$(type -P rc-service)

if [[ $is_systemd ]]; then
    is_caddy_service=$(systemctl list-units --full -all 2>/dev/null | grep caddy.service)
    is_argo_service=$(systemctl list-units --full -all 2>/dev/null | grep "${is_argo_service_name}.service")
elif [[ $is_openrc ]]; then
    [[ -f /etc/init.d/caddy ]] && is_caddy_service=1
    [[ -f /etc/init.d/$is_argo_service_name ]] && is_argo_service=1
fi

is_http_port=80
is_https_port=443

_is_svc_running() {
    local svc=$1
    local bin=$2
    if [[ $is_systemd ]]; then
        systemctl is-active --quiet "$svc" 2>/dev/null && return 0
    elif [[ $is_openrc ]]; then
        rc-service "$svc" status &>/dev/null && return 0
    fi
    [[ $bin ]] && pgrep -x "$(basename "$bin")" &>/dev/null && return 0
    return 1
}

# sing-box core version & status
if [[ -x $is_core_bin ]]; then
    is_core_ver=$($is_core_bin version 2>/dev/null | head -n1 | cut -d " " -f3)
fi

if _is_svc_running "$is_app" "$is_core_bin"; then
    is_core_status=$(_green running)
else
    is_core_status=$(_red_bg stopped)
    is_core_stop=1
fi

# Caddy status
if [[ -f $is_caddy_bin && -d $is_caddy_dir && $is_caddy_service ]]; then
    is_caddy=1
    if [[ $is_systemd ]]; then
        [[ -f /lib/systemd/system/caddy.service && ! $(grep '\-\-adapter caddyfile' /lib/systemd/system/caddy.service) ]] && {
            load systemd.sh
            install_service caddy
            systemctl restart caddy &
        }
    fi
    is_caddy_ver=$($is_caddy_bin version 2>/dev/null | head -n1 | cut -d " " -f1)
    is_tmp_http_port=$(grep -E '^ {2,}http_port|^http_port' "$is_caddyfile" 2>/dev/null | grep -Eo '[0-9]+' | head -n1)
    is_tmp_https_port=$(grep -E '^ {2,}https_port|^https_port' "$is_caddyfile" 2>/dev/null | grep -Eo '[0-9]+' | head -n1)
    [[ $is_tmp_http_port ]] && is_http_port=$is_tmp_http_port
    [[ $is_tmp_https_port ]] && is_https_port=$is_tmp_https_port
    if _is_svc_running caddy "$is_caddy_bin"; then
        is_caddy_status=$(_green running)
    else
        is_caddy_status=$(_red_bg stopped)
        is_caddy_stop=1
    fi
fi

# Cloudflared Argo status
if [[ -x $is_argo_bin ]]; then
    is_argo_installed=1
    is_argo_ver=$($is_argo_bin version 2>/dev/null | awk '{print $3}' | head -n1)
    if _is_svc_running "$is_argo_service_name" "$is_argo_bin"; then
        is_argo_status=$(_green running)
    else
        is_argo_status=$(_red_bg stopped)
        is_argo_stop=1
    fi
fi

load core.sh
if [[ ${#args[@]} -eq 0 ]]; then
    main main
else
    main "${args[@]}"
fi
