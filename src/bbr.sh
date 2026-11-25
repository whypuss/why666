_open_bbr() {
    if [[ -f /etc/sysctl.conf ]]; then
        sed -i '/net.ipv4.tcp_congestion_control/d' /etc/sysctl.conf 2>/dev/null
        sed -i '/net.core.default_qdisc/d' /etc/sysctl.conf 2>/dev/null
    fi
    if [[ -d /etc/sysctl.d ]]; then
        cat >/etc/sysctl.d/99-why666-bbr.conf <<EOF
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
EOF
        sysctl --system &>/dev/null || sysctl -p /etc/sysctl.d/99-why666-bbr.conf &>/dev/null
    else
        echo "net.core.default_qdisc = fq" >>/etc/sysctl.conf
        echo "net.ipv4.tcp_congestion_control = bbr" >>/etc/sysctl.conf
        sysctl -p &>/dev/null
    fi
    if [[ $(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null) != "bbr" ]]; then
        modprobe tcp_bbr &>/dev/null || true
        sysctl -w net.core.default_qdisc=fq &>/dev/null || true
        sysctl -w net.ipv4.tcp_congestion_control=bbr &>/dev/null || true
    fi
    if [[ $(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null) != "bbr" ]]; then
        err "当前虚拟化或内核环境不允许启用 BBR (如只读容器或缺失 tcp_bbr 模块)."
    fi
    [[ ! $is_quiet ]] && {
        echo
        _green "..已经启用 BBR 优化...."
        echo
    }
}

_try_enable_bbr() {
    local _ver _test1 _test2
    _ver=$(uname -r | grep -Eo '^[0-9]+\.[0-9]+')
    _test1=${_ver%%.*}
    _test2=${_ver#*.}
    if [[ $_test1 =~ ^[0-9]+$ && $_test2 =~ ^[0-9]+$ ]] && { [[ $_test1 -eq 4 && $_test2 -ge 9 ]] || [[ $_test1 -ge 5 ]]; }; then
        _open_bbr
    else
        err "当前内核 ($(uname -r)) 不支持启用 BBR 优化 (需 >= 4.9)."
    fi
}
