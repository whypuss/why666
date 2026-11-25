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

_extract_asset_sha256() {
    local api_json=$1
    local asset_name=$2
    [[ ! $api_json || ! $asset_name ]] && return 0
    if type -P jq &>/dev/null; then
        jq -r --arg n "$asset_name" '(.assets // [])[] | select(.name == $n) | .digest // empty' <<<"$api_json" 2>/dev/null | sed 's/^sha256://' | head -n1
    fi
}

get_latest_version() {
    local repo=""
    latest_api_resp=""
    case $1 in
    core)
        name=$is_core_name
        repo=$is_core_repo
        ;;
    sh)
        name="$is_app 脚本"
        repo=$is_sh_repo
        ;;
    caddy)
        name="Caddy"
        repo=$is_caddy_repo
        ;;
    argo | cloudflared)
        name="Cloudflared"
        repo=$is_argo_repo
        ;;
    esac
    url="https://api.github.com/repos/${repo}/releases/latest?v=$RANDOM"
    latest_api_resp=$(_fetch "$url" 2>/dev/null || true)
    latest_ver=$(grep -m1 '"tag_name"' <<<"$latest_api_resp" | grep -Eo 'v?[0-9][0-9.]+')
    if [[ ! $latest_ver && $repo ]]; then
        latest_ver=$(_resolve_latest_tag "$repo" | grep -Eo 'v?[0-9][0-9.]+')
    fi
    [[ ! $latest_ver ]] && {
        err "获取 ${name} 最新版本失败."
    }
    unset name url
}

download() {
    latest_ver=$2
    latest_api_resp=""
    if [[ ! $latest_ver && $1 != "sh_main" ]]; then
        if [[ $1 == "argo" || $1 == "cloudflared" ]]; then
            # Best-effort API lookup for digest; fall back to direct /releases/latest/download if rate-limited
            latest_api_resp=$(_fetch "https://api.github.com/repos/${is_argo_repo}/releases/latest?v=$RANDOM" 2>/dev/null || true)
            latest_ver=$(grep -m1 '"tag_name"' <<<"$latest_api_resp" | grep -Eo '[0-9][0-9.]+')
        else
            get_latest_version "$1"
        fi
    fi
    tmpdir=$(mktemp -d -t why666-dl.XXXXXX 2>/dev/null)
    if [[ ! $tmpdir || ! -d $tmpdir ]]; then
        local _rand
        _rand=$(od -An -tx4 -N8 /dev/urandom 2>/dev/null | tr -d ' \n')
        tmpdir="/tmp/why666-dl-$$-${_rand:-$RANDOM}"
        mkdir -m 700 -p "$tmpdir" || err "无法创建安全临时目录 ($tmpdir)."
    fi
    chmod 700 "$tmpdir"
    local expected_sha="" asset_file=""
    case $1 in
    core)
        name=$is_core_name
        asset_file="${is_core}-${latest_ver#v}-linux-${is_arch}.tar.gz"
        tmpfile=$tmpdir/$is_core.tar.gz
        link="https://github.com/${is_core_repo}/releases/download/${latest_ver}/${asset_file}"
        expected_sha=$(_extract_asset_sha256 "$latest_api_resp" "$asset_file")
        download_file "$expected_sha"
        tar zxf "$tmpfile" --strip-components 1 -C "$is_core_dir/bin"
        chmod +x "$is_core_bin"
        ;;
    sh)
        name="$is_app 脚本"
        asset_file="code.tar.gz"
        tmpfile=$tmpdir/sh.tar.gz
        link="https://github.com/${is_sh_repo}/releases/download/${latest_ver}/${asset_file}"
        expected_sha=$(_extract_asset_sha256 "$latest_api_resp" "$asset_file")
        if _fetch "$link" "$tmpfile" && _verify_sha256 "$tmpfile" "$expected_sha"; then
            tar zxf "$tmpfile" -C "$is_sh_dir"
        else
            link="https://github.com/${is_sh_repo}/archive/refs/heads/main.tar.gz"
            download_file
            tar zxf "$tmpfile" --strip-components 1 -C "$is_sh_dir"
        fi
        ln -sf "$is_sh_dir/$is_app.sh" "$is_sh_bin"
        ln -sf "$is_sh_dir/$is_app.sh" "$is_sh_short_bin"
        rm -f /usr/local/bin/w6
        sed -i "/alias w6=/d;/alias yy=/d" /root/.bashrc 2>/dev/null
        echo "alias yy=$is_sh_bin" >>/root/.bashrc 2>/dev/null
        chmod +x "$is_sh_bin" "$is_sh_short_bin" "$is_sh_dir/$is_app.sh"
        ;;
    sh_main)
        name="$is_app 脚本 (main)"
        tmpfile=$tmpdir/sh.tar.gz
        link="https://github.com/${is_sh_repo}/archive/refs/heads/main.tar.gz"
        download_file
        tar zxf "$tmpfile" --strip-components 1 -C "$is_sh_dir"
        ln -sf "$is_sh_dir/$is_app.sh" "$is_sh_bin"
        ln -sf "$is_sh_dir/$is_app.sh" "$is_sh_short_bin"
        rm -f /usr/local/bin/w6
        sed -i "/alias w6=/d;/alias yy=/d" /root/.bashrc 2>/dev/null
        echo "alias yy=$is_sh_bin" >>/root/.bashrc 2>/dev/null
        chmod +x "$is_sh_bin" "$is_sh_short_bin" "$is_sh_dir/$is_app.sh"
        ;;
    caddy)
        name="Caddy"
        asset_file="caddy_${latest_ver#v}_linux_${is_arch}.tar.gz"
        tmpfile=$tmpdir/caddy.tar.gz
        link="https://github.com/${is_caddy_repo}/releases/download/${latest_ver}/${asset_file}"
        expected_sha=$(_extract_asset_sha256 "$latest_api_resp" "$asset_file")
        if [[ ! $expected_sha ]]; then
            local csums
            csums=$(_fetch "https://github.com/${is_caddy_repo}/releases/download/${latest_ver}/caddy_${latest_ver#v}_checksums.txt" 2>/dev/null || true)
            expected_sha=$(awk -v f="$asset_file" '$2 == f {print $1; exit}' <<<"$csums")
        fi
        download_file "$expected_sha"
        tar zxf "$tmpfile" -C "$tmpdir"
        cp -f "$tmpdir/caddy" "$is_caddy_bin"
        chmod +x "$is_caddy_bin"
        ;;
    argo | cloudflared)
        name="Cloudflared"
        asset_file="cloudflared-linux-${is_arch}"
        tmpfile=$tmpdir/cloudflared
        if [[ $latest_ver ]]; then
            link="https://github.com/${is_argo_repo}/releases/download/${latest_ver#v}/${asset_file}"
        else
            link="https://github.com/${is_argo_repo}/releases/latest/download/${asset_file}"
        fi
        expected_sha=$(_extract_asset_sha256 "$latest_api_resp" "$asset_file")
        download_file "$expected_sha"
        mv -f "$tmpfile" "$is_argo_bin"
        chmod +x "$is_argo_bin"
        ;;
    esac
    rm -rf "$tmpdir"
    unset latest_ver latest_api_resp
}

download_file() {
    local expected_sha=$1
    if ! _fetch "$link" "$tmpfile"; then
        rm -rf "$tmpdir"
        err "\n下载 ${name} 失败: ${link}\n"
    fi
    if [[ $expected_sha ]] && ! _verify_sha256 "$tmpfile" "$expected_sha"; then
        rm -rf "$tmpdir"
        err "\n${name} SHA256 完整性校验失败, 已拒绝安装: ${link}\n"
    fi
}
