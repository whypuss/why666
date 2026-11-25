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
_blue() { echo -e "${blue}$*${none}"; }
_cyan() { echo -e "${cyan}$*${none}"; }
_green() { echo -e "${green}$*${none}"; }
_yellow() { echo -e "${yellow}$*${none}"; }
_magenta() { echo -e "${magenta}$*${none}"; }
_red_bg() { echo -e "\e[41m$*${none}"; }

is_err=$(_red_bg 错误!)
is_warn=$(_red_bg 警告!)

err() {
    echo -e "\n$is_err $*\n" >&2
    exit 1
}

warn() {
    [[ $is_json_out ]] && return
    echo -e "\n$is_warn $*\n" >&2
}

# root check
[[ $EUID != 0 ]] && err "当前非 ${yellow}ROOT用户.${none}"

# package manager: apt-get, dnf, yum, zypper or apk
cmd=$(type -P apt-get || type -P dnf || type -P yum || type -P zypper || type -P apk)
[[ ! $cmd ]] && err "此脚本仅支持 ${yellow}(Ubuntu / Debian / CentOS / Rocky / AlmaLinux / SUSE / Alpine)${none}."

# init system: systemd or openrc
is_systemd=$(type -P systemctl)
is_openrc=$(type -P rc-service)
[[ ! $is_systemd && ! $is_openrc ]] && {
    err "此系统缺少 ${yellow}(systemctl 或 rc-service)${none}, 请安装 systemd 或确认 OpenRC 已启用."
}

# downloader check
is_wget=$(type -P wget)
is_curl=$(type -P curl)

# architecture
case $(uname -m) in
amd64 | x86_64)
    is_arch=amd64
    ;;
*aarch64* | *armv8*)
    is_arch=arm64
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
is_log_dir=/var/log/$is_app
is_sh_bin=/usr/local/bin/$is_app
is_sh_short_bin=/usr/local/bin/yy
is_sh_dir=$is_core_dir/sh
is_sh_repo=$author/$project
is_pkg="wget curl tar bash openssl"
[[ $cmd =~ apk ]] && is_pkg="$is_pkg gcompat jq ca-certificates"
is_config_json=$is_core_dir/config.json

# AI / non-interactive env vars
is_non_interactive=${WHY666_NON_INTERACTIVE:-}
is_json_out=${WHY666_JSON:-}
is_ai_protocols=${WHY666_PROTOCOLS:-}
is_ai_argo=${WHY666_ARGO:-}
is_ai_argo_domain=${WHY666_ARGO_DOMAIN:-}
is_ai_argo_token=${WHY666_ARGO_TOKEN:-}
is_ai_argo_proto=${WHY666_ARGO_PROTO:-http2}
is_ai_argo_backend=${WHY666_ARGO_BACKEND:-vmess}
is_ai_bbr=${WHY666_BBR:-}
is_no_default=${WHY666_NO_DEFAULT:-}
is_skip_dns_check=${WHY666_SKIP_DNS_CHECK:-}
is_default_proto=${WHY666_DEFAULT_PROTO:-anytls}

tmp_var_lists=(
    tmpcore
    tmpsh
    tmpjq
    is_core_ok
    is_sh_ok
    is_jq_ok
    is_pkg_ok
)

tmpdir=""

init_tmpdir() {
    tmpdir=$(mktemp -d -t why666.XXXXXX 2>/dev/null)
    if [[ ! $tmpdir || ! -d $tmpdir ]]; then
        local _rand
        _rand=$(od -An -tx4 -N8 /dev/urandom 2>/dev/null | tr -d ' \n')
        tmpdir="/tmp/why666-$$-${_rand:-$RANDOM}"
        mkdir -m 700 -p "$tmpdir" || err "无法创建安全临时目录 ($tmpdir)."
    fi
    chmod 700 "$tmpdir"
    trap '[[ $tmpdir && -d $tmpdir ]] && rm -rf "$tmpdir"' EXIT INT TERM
    for i in ${tmp_var_lists[*]}; do
        export "$i=$tmpdir/$i"
    done
}

load() {
    . "$is_sh_dir/src/$1"
}

_wget() {
    [[ $proxy ]] && export https_proxy=$proxy http_proxy=$proxy
    if [[ $(type -P wget) ]]; then
        wget "$@"
    else
        return 1
    fi
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

_resolve_latest_tag() {
    local repo=$1
    local final_url=""
    [[ $proxy ]] && export https_proxy=$proxy http_proxy=$proxy
    if [[ $(type -P curl) ]]; then
        final_url=$(curl -fsSLI -o /dev/null -w '%{url_effective}' --connect-timeout 10 --max-time 20 "https://github.com/${repo}/releases/latest" 2>/dev/null)
    elif [[ $(type -P wget) ]]; then
        final_url=$(wget --spider -S -T 15 -t 2 "https://github.com/${repo}/releases/latest" 2>&1 | awk '/^[[:space:]]*Location:/ {u=$2} END {print u}' | tr -d '\r')
    fi
    if [[ $final_url == */releases/tag/* ]]; then
        echo "${final_url##*/releases/tag/}" | tr -d '[:space:]/'
    fi
}

_verify_sha256() {
    local file=$1
    local expected=${2,,}
    [[ ! $expected ]] && return 0
    local actual=""
    if [[ $(type -P sha256sum) ]]; then
        actual=$(sha256sum "$file" 2>/dev/null | awk '{print tolower($1)}')
    elif [[ $(type -P shasum) ]]; then
        actual=$(shasum -a 256 "$file" 2>/dev/null | awk '{print tolower($1)}')
    elif [[ $(type -P openssl) ]]; then
        actual=$(openssl dgst -sha256 "$file" 2>/dev/null | awk '{print tolower($NF)}')
    else
        return 0
    fi
    [[ $actual == "$expected" ]]
}

msg() {
    [[ $is_json_out ]] && return
    case $1 in
    warn) local color=$yellow ;;
    err) local color=$red ;;
    ok) local color=$green ;;
    *) local color=$none ;;
    esac
    echo -e "${color}$(date +'%T')${none}) ${2}"
}

show_help() {
    cat <<EOF
why666 一键安装脚本 (基于 sing-box 多协议管理引擎)

Usage: $0 [options]

基础选项:
  -f, --core-file <path>          自定义 sing-box 压缩包路径, e.g., -f /root/sing-box-linux-amd64.tar.gz
  -l, --local-install             使用当前目录作为本地脚本源安装
  -p, --proxy <addr>              使用代理下载, e.g., -p http://127.0.0.1:7890
  -v, --core-version <ver>        自定义 sing-box 版本, e.g., -v v1.14.4
  -h, --help                      显示此帮助界面

AI / 无交互自动化部署选项:
  -y, --non-interactive           完全无交互模式 (适合 AI Agent / CI / 批量脚本)
  --protocols <list>              逗号分隔协议列表, e.g., "reality,hy2,snell,naive:a.example.com"
  --argo <mode>                   启用 CF Argo 隧道: quick | fixed
  --argo-domain <domain>          CF Argo 固定隧道域名 (配合 --argo fixed)
  --argo-token <token>            CF Argo 固定隧道 Token (配合 --argo fixed)
  --argo-proto <http2|quic>       CF Argo 隧道传输协议 (默认 http2)
  --argo-backend <vmess|vless>    CF Argo 后端本地协议 (默认 vmess)
  --bbr                           安装后自动启用 BBR 优化
  --skip-dns-check                跳过域名解析预检 (适合 CDN 或自动化场景)
  --no-default                    仅安装框架, 不自动创建默认节点
  --json                          以结构化 JSON 输出最终部署结果 (隐含 -y)

环境变量快捷方式:
  WHY666_PROTOCOLS="reality,hy2,snell" WHY666_ARGO="quick" WHY666_JSON=1 bash install.sh
EOF
    exit 0
}

install_pkg() {
    local cmd_not_found=""
    for i in $*; do
        [[ ! $(type -P "$i") ]] && cmd_not_found="$cmd_not_found $i"
    done
    if [[ ! -f /etc/ssl/certs/ca-certificates.crt && ! -f /etc/pki/tls/certs/ca-bundle.crt && ! -f /etc/ssl/ca-bundle.pem ]]; then
        cmd_not_found="$cmd_not_found ca-certificates"
    fi
    if [[ $cmd_not_found ]]; then
        msg warn "安装依赖包 >${cmd_not_found}"
        if [[ $cmd =~ apk ]]; then
            apk update &>/dev/null
            apk add --no-cache $cmd_not_found &>/dev/null
        elif [[ $cmd =~ zypper ]]; then
            $cmd --non-interactive refresh &>/dev/null
            $cmd --non-interactive install $cmd_not_found &>/dev/null
        else
            export DEBIAN_FRONTEND=noninteractive
            $cmd install -y $cmd_not_found </dev/null &>/dev/null
            if [[ $? != 0 ]]; then
                [[ $cmd =~ yum ]] && yum install epel-release -y </dev/null &>/dev/null
                $cmd update -y </dev/null &>/dev/null
                $cmd install -y $cmd_not_found </dev/null &>/dev/null
            fi
        fi
        [[ $? == 0 ]] && >"$is_pkg_ok"
    else
        >"$is_pkg_ok"
    fi
}

download() {
    local link="" name="" tmpfile="" is_ok="" expected_sha=""
    case $1 in
    core)
        local api_resp=""
        if [[ ! $is_core_ver ]]; then
            api_resp=$(_fetch "https://api.github.com/repos/${is_core_repo}/releases/latest?v=$RANDOM" 2>/dev/null || true)
            is_core_ver=$(grep -m1 '"tag_name"' <<<"$api_resp" | grep -Eo 'v[0-9.]+')
            if [[ ! $is_core_ver ]]; then
                is_core_ver=$(_resolve_latest_tag "$is_core_repo" | grep -Eo 'v[0-9.]+')
            fi
        fi
        if [[ $is_core_ver ]]; then
            local core_asset="${is_core}-${is_core_ver#v}-linux-${is_arch}.tar.gz"
            link="https://github.com/${is_core_repo}/releases/download/${is_core_ver}/${core_asset}"
            if [[ $api_resp ]] && [[ $(type -P jq) ]]; then
                expected_sha=$(jq -r --arg n "$core_asset" '(.assets // [])[] | select(.name == $n) | .digest // empty' <<<"$api_resp" 2>/dev/null | sed 's/^sha256://' | head -n1)
            fi
        fi
        name=$is_core_name
        tmpfile=$tmpcore
        is_ok=$is_core_ok
        ;;
    sh)
        name="$is_app 脚本"
        tmpfile=$tmpsh
        is_ok=$is_sh_ok
        link="https://github.com/${is_sh_repo}/releases/latest/download/code.tar.gz"
        msg warn "下载 ${name} > ${link}"
        if _fetch "$link" "$tmpfile"; then
            mv -f "$tmpfile" "$is_ok"
            return 0
        fi
        # Fallback to main branch archive if no release artifact yet
        link="https://github.com/${is_sh_repo}/archive/refs/heads/main.tar.gz"
        msg warn "回退下载 ${name} (main) > ${link}"
        if _fetch "$link" "$tmpfile"; then
            echo "1" >"$tmpdir/sh_strip"
            mv -f "$tmpfile" "$is_ok"
            return 0
        fi
        return 1
        ;;
    jq)
        link="https://github.com/jqlang/jq/releases/download/jq-1.7.1/jq-linux-${is_arch}"
        [[ $is_arch == "amd64" ]] && expected_sha="5942c9b0934e510ee61eb3e30273f1b3fe2590df93933a93d7c58b81d19c8ff5"
        [[ $is_arch == "arm64" ]] && expected_sha="4dd2d8a0661df0b22f1bb9a1f9830f06b6f3b8f7d91211a1ef5d7c4f06a8b4a5"
        name="jq"
        tmpfile=$tmpjq
        is_ok=$is_jq_ok
        ;;
    esac

    [[ $link ]] && {
        msg warn "下载 ${name} > ${link}"
        if _fetch "$link" "$tmpfile"; then
            if [[ $expected_sha ]] && ! _verify_sha256 "$tmpfile" "$expected_sha"; then
                msg err "${name} SHA256 校验失败, 已拒绝安装."
                rm -f "$tmpfile"
                return 1
            fi
            mv -f "$tmpfile" "$is_ok"
        fi
    }
}

get_ip() {
    local _ip=""
    _ip=$(_fetch "https://one.one.one.one/cdn-cgi/trace" | grep '^ip=' | cut -d= -f2)
    [[ ! $_ip ]] && _ip=$(_fetch "https://api4.ipify.org")
    [[ ! $_ip ]] && _ip=$(_fetch "https://api64.ipify.org")
    [[ ! $_ip ]] && _ip=$(_fetch "https://icanhazip.com")
    ip=$(echo "$_ip" | tr -d '[:space:]')
}

check_status() {
    [[ ! -f $is_pkg_ok ]] && {
        msg err "安装依赖包失败"
        if [[ $cmd =~ apk ]]; then
            msg err "请尝试手动安装依赖包: apk update && apk add $is_pkg"
        else
            msg err "请尝试手动安装依赖包: $cmd update -y && $cmd install -y $is_pkg"
        fi
        is_fail=1
    }

    if [[ $is_wget || $is_curl ]]; then
        [[ ! -f $is_core_ok ]] && {
            msg err "下载 ${is_core_name} 失败"
            is_fail=1
        }
        [[ ! -f $is_sh_ok ]] && {
            msg err "下载 ${is_app} 脚本失败"
            is_fail=1
        }
        [[ ! -f $is_jq_ok ]] && {
            msg err "下载 jq 失败"
            is_fail=1
        }
    else
        [[ ! $is_fail ]] && {
            is_wget=$(type -P wget)
            is_curl=$(type -P curl)
            [[ ! $is_core_file ]] && download core &
            [[ ! $local_install ]] && download sh &
            [[ $jq_not_found ]] && download jq &
            get_ip
            wait
            check_status
        }
    fi

    [[ $is_fail ]] && exit_and_del_tmpdir
}

pass_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
        -f | --core-file)
            [[ -z $2 ]] && err "($1) 缺少必需参数, 示例: [$1 /root/$is_core-linux-amd64.tar.gz]"
            [[ ! -f $2 ]] && err "($2) 不是一个常规的文件."
            is_core_file=$2
            shift 2
            ;;
        -l | --local-install)
            [[ ! -f ${PWD}/src/core.sh || ! -f ${PWD}/$is_app.sh ]] && err "当前目录 (${PWD}) 非完整的脚本目录."
            local_install=1
            shift 1
            ;;
        -p | --proxy)
            [[ -z $2 ]] && err "($1) 缺少必需参数, 示例: [$1 http://127.0.0.1:7890]"
            proxy=$2
            shift 2
            ;;
        -v | --core-version)
            [[ -z $2 ]] && err "($1) 缺少必需参数, 示例: [$1 v1.14.4]"
            is_core_ver=v${2#v}
            shift 2
            ;;
        -y | --non-interactive)
            is_non_interactive=1
            shift 1
            ;;
        --protocols)
            [[ -z $2 ]] && err "($1) 缺少参数, 示例: [--protocols reality,hy2,snell]"
            is_ai_protocols=$2
            is_non_interactive=1
            shift 2
            ;;
        --argo)
            [[ -z $2 ]] && err "($1) 缺少参数: quick 或 fixed"
            is_ai_argo=$2
            shift 2
            ;;
        --argo-domain)
            [[ -z $2 ]] && err "($1) 缺少参数"
            is_ai_argo_domain=$2
            shift 2
            ;;
        --argo-token)
            [[ -z $2 ]] && err "($1) 缺少参数"
            is_ai_argo_token=$2
            shift 2
            ;;
        --argo-proto)
            [[ -z $2 ]] && err "($1) 缺少参数: http2 或 quic"
            is_ai_argo_proto=$2
            shift 2
            ;;
        --argo-backend)
            [[ -z $2 ]] && err "($1) 缺少参数: vmess 或 vless"
            is_ai_argo_backend=$2
            shift 2
            ;;
        --bbr)
            is_ai_bbr=1
            shift 1
            ;;
        --skip-dns-check)
            is_skip_dns_check=1
            shift 1
            ;;
        --no-default)
            is_no_default=1
            shift 1
            ;;
        --json)
            is_json_out=1
            is_non_interactive=1
            shift 1
            ;;
        -h | --help)
            show_help
            ;;
        *)
            echo -e "\n${is_err} ($*) 为未知参数...\n" >&2
            show_help
            ;;
        esac
    done
    [[ $is_core_ver && $is_core_file ]] && err "无法同时自定义 ${is_core_name} 版本和 ${is_core_name} 文件."
}

exit_and_del_tmpdir() {
    [[ $tmpdir && -d $tmpdir ]] && rm -rf "$tmpdir"
    [[ ! $1 ]] && {
        if [[ $is_json_out ]]; then
            echo '{"ok":false,"error":"why666 installation failed"}'
        else
            msg err "安装过程出现错误..."
            echo -e "反馈问题) https://github.com/${is_sh_repo}/issues\n"
        fi
        exit 1
    }
    exit 0
}

main() {
    [[ $# -gt 0 ]] && pass_args "$@"

    # check old installation
    [[ -f $is_sh_bin && -d $is_core_dir/bin && -d $is_sh_dir && -d $is_conf_dir ]] && {
        if [[ $is_non_interactive ]]; then
            # In AI/non-interactive mode, allow passing directly to ai deploy if already installed
            if [[ $is_ai_protocols || $is_ai_argo || $is_ai_bbr ]]; then
                local _deploy_args=()
                [[ $is_ai_protocols ]] && _deploy_args+=(--protocols "$is_ai_protocols")
                [[ $is_ai_argo ]] && _deploy_args+=(--argo "$is_ai_argo")
                [[ $is_ai_argo_domain ]] && _deploy_args+=(--argo-domain "$is_ai_argo_domain")
                [[ $is_ai_argo_token ]] && _deploy_args+=(--argo-token "$is_ai_argo_token")
                [[ $is_ai_argo_proto ]] && _deploy_args+=(--argo-proto "$is_ai_argo_proto")
                [[ $is_ai_argo_backend ]] && _deploy_args+=(--argo-backend "$is_ai_argo_backend")
                [[ $is_ai_bbr ]] && _deploy_args+=(--bbr)
                [[ $is_skip_dns_check ]] && _deploy_args+=(--skip-dns-check)
                [[ $is_json_out ]] && _deploy_args+=(--json)
                exec "$is_sh_bin" ai deploy "${_deploy_args[@]}"
            elif [[ $is_json_out ]]; then
                exec "$is_sh_bin" ai json
            fi
        fi
        err "检测到 ${is_app} 已安装, 如需重装请使用 ${green}${is_app} reinstall${none} 命令."
    }

    if [[ ! $is_non_interactive && ! $is_json_out ]]; then
        clear 2>/dev/null || true
        echo
        echo "........... $is_app script (sing-box) by $author .........."
        echo
    fi

    msg warn "开始安装 $is_app ..."
    [[ $is_core_ver ]] && msg warn "${is_core_name} 版本: ${yellow}$is_core_ver${none}"
    [[ $proxy ]] && msg warn "使用代理: ${yellow}$proxy${none}"

    init_tmpdir
    [[ $is_core_file ]] && {
        cp -f "$is_core_file" "$is_core_ok"
        msg warn "${yellow}${is_core_name} 文件使用 > $is_core_file${none}"
    }
    [[ $local_install ]] && {
        >"$is_sh_ok"
        msg warn "${yellow}本地获取安装脚本 > $PWD${none}"
    }

    if [[ $is_systemd ]]; then
        timedatectl set-ntp true &>/dev/null
        [[ $? != 0 ]] && is_ntp_on=1
    fi

    # Install dependent packages
    if [[ $cmd =~ apk ]]; then
        apk update &>/dev/null
        apk add --no-cache $is_pkg &>/dev/null
        [[ $? == 0 ]] && >"$is_pkg_ok"
    else
        install_pkg $is_pkg &
    fi

    # Check jq
    if [[ $(type -P jq) ]]; then
        >"$is_jq_ok"
    else
        jq_not_found=1
    fi

    # Concurrent download if wget/curl available
    [[ $is_wget || $is_curl ]] && {
        [[ ! $is_core_file ]] && download core &
        [[ ! $local_install ]] && download sh &
        [[ $jq_not_found ]] && download jq &
        get_ip
    }

    wait
    check_status

    # Verify custom core archive
    if [[ $is_core_file ]]; then
        mkdir -p "$tmpdir/testzip"
        tar zxf "$is_core_ok" --strip-components 1 -C "$tmpdir/testzip" &>/dev/null
        [[ $? != 0 || ! -f $tmpdir/testzip/$is_core ]] && {
            msg err "${is_core_name} 文件无法通过测试."
            exit_and_del_tmpdir
        }
    fi

    [[ ! $ip ]] && {
        msg err "获取服务器 IP 失败."
        exit_and_del_tmpdir
    }

    # Deploy scripts
    mkdir -p "$is_sh_dir"
    if [[ $local_install ]]; then
        cp -rf "$PWD"/* "$is_sh_dir"
    else
        if [[ -f $tmpdir/sh_strip ]]; then
            tar zxf "$is_sh_ok" --strip-components 1 -C "$is_sh_dir"
        else
            tar zxf "$is_sh_ok" -C "$is_sh_dir"
        fi
    fi

    # Deploy sing-box core
    mkdir -p "$is_core_dir/bin"
    if [[ $is_core_file ]]; then
        cp -rf "$tmpdir/testzip"/* "$is_core_dir/bin"
    else
        tar zxf "$is_core_ok" --strip-components 1 -C "$is_core_dir/bin"
    fi

    # Add shell aliases (idempotent)
    touch /root/.bashrc
    sed -i "/alias $is_app=/d;/alias w6=/d;/alias yy=/d" /root/.bashrc
    echo "alias yy=$is_sh_bin" >>/root/.bashrc
    echo "alias $is_app=$is_sh_bin" >>/root/.bashrc

    # Symlink binaries
    rm -f /usr/local/bin/w6
    ln -sf "$is_sh_dir/$is_app.sh" "$is_sh_bin"
    ln -sf "$is_sh_dir/$is_app.sh" "$is_sh_short_bin"

    # Install jq if downloaded (use /usr/local/bin to avoid conflicting with distro package manager)
    if [[ $jq_not_found && -f $is_jq_ok ]]; then
        mkdir -p /usr/local/bin
        mv -f "$is_jq_ok" /usr/local/bin/jq
        chmod 0755 /usr/local/bin/jq
    fi

    chmod +x "$is_core_bin" "$is_sh_bin" "$is_sh_short_bin"

    mkdir -p "$is_log_dir"
    mkdir -m 700 -p "$is_core_dir" "$is_conf_dir" "$is_core_dir/argo" "$is_core_dir/acme"
    chmod 700 "$is_core_dir" "$is_conf_dir" "$is_core_dir/argo" "$is_core_dir/acme"

    msg ok "生成系统服务与主配置..."
    load systemd.sh
    is_new_install=1
    install_service "$is_app" &>/dev/null

    # Generate base config.json cleanly
    if [[ $is_ntp_on ]]; then
        (umask 077 && jq -n --arg log_out "${is_log_dir}/access.log" \
            '{log:{output:$log_out,level:"info",timestamp:true},dns:{},ntp:{enabled:true,server:"time.apple.com"},outbounds:[{tag:"direct",type:"direct"}]}' \
            >"$is_config_json")
    else
        (umask 077 && jq -n --arg log_out "${is_log_dir}/access.log" \
            '{log:{output:$log_out,level:"info",timestamp:true},dns:{},outbounds:[{tag:"direct",type:"direct"}]}' \
            >"$is_config_json")
    fi
    chmod 600 "$is_config_json"

    # Handle post-install provisioning via installed why666 binary (full init.sh env)
    if [[ $is_ai_protocols || $is_ai_argo || $is_ai_bbr || $is_json_out ]]; then
        local _deploy_args=()
        if [[ $is_ai_protocols ]]; then
            _deploy_args+=(--protocols "$is_ai_protocols")
        elif [[ ! $is_no_default && ! $is_ai_argo ]]; then
            _deploy_args+=(--protocols "$is_default_proto")
        fi
        [[ $is_ai_argo ]] && _deploy_args+=(--argo "$is_ai_argo")
        [[ $is_ai_argo_domain ]] && _deploy_args+=(--argo-domain "$is_ai_argo_domain")
        [[ $is_ai_argo_token ]] && _deploy_args+=(--argo-token "$is_ai_argo_token")
        [[ $is_ai_argo_proto ]] && _deploy_args+=(--argo-proto "$is_ai_argo_proto")
        [[ $is_ai_argo_backend ]] && _deploy_args+=(--argo-backend "$is_ai_argo_backend")
        [[ $is_ai_bbr ]] && _deploy_args+=(--bbr)
        [[ $is_skip_dns_check ]] && _deploy_args+=(--skip-dns-check)
        [[ $is_json_out ]] && _deploy_args+=(--json)
        "$is_sh_bin" ai deploy "${_deploy_args[@]}"
    elif [[ ! $is_no_default ]]; then
        # Default install: add AnyTLS (ready out of the box)
        is_new_install=1 "$is_sh_bin" add "$is_default_proto"
    fi

    wait
    exit_and_del_tmpdir ok
}

main "$@"
