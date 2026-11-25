is_dns_list=(
    1.1.1.1
    8.8.8.8
    h3://dns.google/dns-query
    h3://cloudflare-dns.com/dns-query
    h3://family.cloudflare-dns.com/dns-query
    set
    none
)

dns_set() {
    if [[ $(printf "1.11.99\n%s\n" "$is_core_ver" | sort -V | head -n1) == '1.11.99' ]]; then
        is_dns_new=1
    fi
    if [[ $1 ]]; then
        case ${1,,} in
        11 | 1111) is_dns_use=${is_dns_list[0]} ;;
        88 | 8888) is_dns_use=${is_dns_list[1]} ;;
        gg | google) is_dns_use=${is_dns_list[2]} ;;
        cf | cloudflare) is_dns_use=${is_dns_list[3]} ;;
        nosex | family) is_dns_use=${is_dns_list[4]} ;;
        set)
            if [[ $2 ]]; then
                is_dns_use=${2,,}
            else
                ask string is_dns_use "请输入 DNS: "
            fi
            ;;
        none) is_dns_use=none ;;
        *) err "无法识别 DNS 参数: $*" ;;
        esac
    else
        is_tmp_list=("${is_dns_list[@]}")
        ask list is_dns_use null "\n请选择 DNS:\n"
        if [[ $is_dns_use == "set" ]]; then
            ask string is_dns_use "请输入 DNS: "
        fi
    fi
    is_dns_use_bak=$is_dns_use
    if [[ $is_dns_use == "none" ]]; then
        jq '.dns={} | del(.route.default_domain_resolver)' "$is_config_json" >"${is_config_json}.tmp" && mv "${is_config_json}.tmp" "$is_config_json"
        chmod 600 "$is_config_json"
    else
        if [[ $is_dns_new ]]; then
            dns_set_server "$is_dns_use"
            jq --arg t "$is_dns_type" --arg s "$is_dns_use" --arg p "${is_dns_port:-}" --arg path "${is_dns_path:-}" \
                '(.dns.servers = [
                    ({tag:"dns",type:$t,server:$s,domain_resolver:"local"}
                    + (if $p != "" then {server_port: ($p | tonumber)} else {} end)
                    + (if $path != "" then {path: $path} else {} end)),
                    {tag:"local",type:"local"}
                ]) | .route.default_domain_resolver="dns"' \
                "$is_config_json" >"${is_config_json}.tmp" && mv "${is_config_json}.tmp" "$is_config_json"
            chmod 600 "$is_config_json"
        else
            jq --arg s "$is_dns_use" \
                '.dns.servers=[{address:$s,address_resolver:"local"},{tag:"local",address:"local"}]' \
                "$is_config_json" >"${is_config_json}.tmp" && mv "${is_config_json}.tmp" "$is_config_json"
            chmod 600 "$is_config_json"
        fi
    fi
    manage restart &
    msg "\n已更新 DNS 为: $(_green "$is_dns_use_bak")\n"
}

dns_set_server() {
    is_dns_port=""
    is_dns_path=""
    local input=$1
    if grep -q '://' <<<"$input"; then
        local _scheme _rest _hostport _path=""
        _scheme=$(awk -F '://' '{print tolower($1)}' <<<"$input")
        _rest=${input#*://}
        if [[ $_rest == */* ]]; then
            _hostport=${_rest%%/*}
            _path="/${_rest#*/}"
        else
            _hostport=$_rest
        fi
        case $_scheme in
        tcp | udp | tls | https | quic | h3)
            is_dns_type=$_scheme
            ;;
        *)
            err "无法识别 DNS 类型: $_scheme"
            ;;
        esac
        if [[ $_hostport =~ ^\[([0-9a-fA-F:]+)\](:([0-9]+))?$ ]]; then
            is_dns_use=${BASH_REMATCH[1]}
            is_dns_port=${BASH_REMATCH[3]}
        elif [[ $_hostport =~ ^([^:]+):([0-9]+)$ ]]; then
            is_dns_use=${BASH_REMATCH[1]}
            is_dns_port=${BASH_REMATCH[2]}
        else
            is_dns_use=$_hostport
        fi
        if [[ ($_scheme == "https" || $_scheme == "h3") && $_path && $_path != "/dns-query" ]]; then
            is_dns_path=$_path
        fi
    else
        if [[ $input =~ ^\[([0-9a-fA-F:]+)\]:([0-9]+)$ ]]; then
            is_dns_use=${BASH_REMATCH[1]}
            is_dns_port=${BASH_REMATCH[2]}
        elif [[ $input =~ ^([^:]+):([0-9]+)$ ]]; then
            is_dns_use=${BASH_REMATCH[1]}
            is_dns_port=${BASH_REMATCH[2]}
        else
            is_dns_use=$input
        fi
        is_dns_type=udp
    fi
}
