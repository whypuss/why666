caddy_config() {
    if [[ $1 != "new" ]]; then
        if [[ ! $host || ! $host =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?)+$ ]]; then
            err "Caddy 配置拒绝非法域名: ${host}"
        fi
    fi
    is_caddy_site_file=$is_caddy_conf/${host}.conf
    case $1 in
    new)
        mkdir -p "$is_caddy_dir" "$is_caddy_dir/sites" "$is_caddy_conf"
        cat >"$is_caddyfile" <<EOF
# Managed by why666 (https://github.com/${is_sh_repo})
# https://caddyserver.com/docs/caddyfile/options
{
  admin off
  http_port $is_http_port
  https_port $is_https_port
}
import $is_caddy_conf/*.conf
import $is_caddy_dir/sites/*.conf
EOF
        ;;
    *ws* | *http*)
        cat >"${is_caddy_site_file}" <<EOF
${host}:${is_https_port} {
    reverse_proxy ${path} 127.0.0.1:${port}
    import ${is_caddy_site_file}.add
}
EOF
        ;;
    *h2*)
        cat >"${is_caddy_site_file}" <<EOF
${host}:${is_https_port} {
    reverse_proxy ${path} h2c://127.0.0.1:${port}
    import ${is_caddy_site_file}.add
}
EOF
        ;;
    *grpc*)
        cat >"${is_caddy_site_file}" <<EOF
${host}:${is_https_port} {
    reverse_proxy /${path}/* h2c://127.0.0.1:${port}
    import ${is_caddy_site_file}.add
}
EOF
        ;;
    proxy)
        if [[ ! $proxy_site || ! $proxy_site =~ ^[a-zA-Z0-9.-]+(:[0-9]{1,5})?(/[a-zA-Z0-9._~/-]*)?$ ]]; then
            err "伪装网站地址格式不合法: ${proxy_site}"
        fi
        cat >"${is_caddy_site_file}.add" <<EOF
reverse_proxy https://${proxy_site} {
    header_up Host {upstream_hostport}
}
EOF
        ;;
    esac
    [[ $1 != "new" && $1 != "proxy" ]] && {
        [[ ! -f ${is_caddy_site_file}.add ]] && echo "# Managed by why666" >"${is_caddy_site_file}.add"
    }
}
