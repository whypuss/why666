is_log_level_list=(
    trace
    debug
    info
    warn
    error
    fatal
    panic
    none
    del
)

log_set() {
    if [[ $1 ]]; then
        is_log_level_use=""
        for v in "${is_log_level_list[@]}"; do
            [[ ${1,,} == "$v" ]] && is_log_level_use=$v && break
        done
        [[ ! $is_log_level_use ]] && {
            err "无法识别 log 参数: $* \n请使用 $is_app log [${is_log_level_list[*]}] 进行设定.\n备注: del 仅删除日志文件; none 将禁用日志输出."
        }
        case $is_log_level_use in
        del)
            rm -rf "$is_log_dir"/*.log
            msg "\n$(_green "已临时删除 log 文件, 如需永久关闭请使用: $is_app log none")\n"
            ;;
        none)
            rm -rf "$is_log_dir"/*.log
            jq '.log={"disabled":true}' "$is_config_json" >"${is_config_json}.tmp" && mv "${is_config_json}.tmp" "$is_config_json"
            ;;
        *)
            jq --arg out "${is_log_dir}/access.log" --arg lvl "$is_log_level_use" \
                '.log={output:$out,level:$lvl,timestamp:true}' "$is_config_json" >"${is_config_json}.tmp" && mv "${is_config_json}.tmp" "$is_config_json"
            ;;
        esac
        manage restart &
        [[ $1 != 'del' ]] && msg "\n已更新 Log 设定为: $(_green "$is_log_level_use")\n"
    else
        if [[ -f $is_log_dir/access.log ]]; then
            msg "\n提醒: 按 $(_green "Ctrl + C") 退出\n"
            tail -f "$is_log_dir/access.log"
        else
            err "无法找到 log 文件 ($is_log_dir/access.log)."
        fi
    fi
}
