#!/usr/bin/env bash

# add_zsh_plugins.sh - 智能添加插件到 .zshrc 的 plugins 配置

set -euo pipefail

usage() {
    echo "用法: $0 [插件列表]"
    echo "示例: $0 zsh-autosuggestions zsh-syntax-highlighting"
    echo "       $0 \"plugin1 plugin2\""
    exit 1
}

# 检查参数
if [[ $# -eq 0 ]]; then
    echo "错误: 需要至少一个插件参数"
    usage
fi

# 获取要添加的插件（支持空格分隔的多个插件）
PLUGINS_TO_ADD="$*"

# 主处理函数
add_plugins() {
    local zshrc_file="$HOME/.zshrc"
    local backup_file="$zshrc_file.bak"
    local tmp_file="$zshrc_file.tmp"
    
    # 检查文件存在
    if [[ ! -f "$zshrc_file" ]]; then
        echo "错误: $zshrc_file 不存在"
        exit 2
    fi
    
    # 创建备份
    cp -f "$zshrc_file" "$backup_file"
    
    # 使用 AWK 处理文件
    awk -v plugins="$PLUGINS_TO_ADD" '
    BEGIN {
        # 将要添加的插件转换为数组
        split(plugins, to_add, " ")
        to_add_count = length(to_add)
    }
    /^[[:space:]]*plugins[[:space:]]*=[[:space:]]*\(/ {
        # 提取括号位置
        start = index($0, "(")
        end = index($0, ")")
        if (start && end && start < end) {
            # 提取插件区域
            inside = substr($0, start+1, end-start-1)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", inside)
            
            # 处理插件列表
            delete arr
            delete seen
            idx = 0
            
            # 添加现有插件
            n = split(inside, temp, /[[:space:]]+/)
            for (i = 1; i <= n; i++) {
                if (temp[i]) {
                    plugin_name = temp[i]
                    if (!seen[plugin_name]++) {
                        arr[++idx] = plugin_name
                    }
                }
            }
            
            # 添加新插件
            for (j = 1; j <= to_add_count; j++) {
                plugin_name = to_add[j]
                if (plugin_name && !seen[plugin_name]) {
                    seen[plugin_name] = 1
                    arr[++idx] = plugin_name
                }
            }
            
            # 重建插件字符串
            new_inside = ""
            for (i = 1; i <= idx; i++) {
                new_inside = (new_inside ? new_inside " " : "") arr[i]
            }
            
            # 重建整行内容
            before = substr($0, 1, start)
            after = substr($0, end)
            $0 = before new_inside after
        }
    }
    { print }
    ' "$zshrc_file" > "$tmp_file"
    
    # 替换原文件
    mv -f "$tmp_file" "$zshrc_file"
    
    echo "成功更新 $zshrc_file"
    echo "原始文件已备份至: $backup_file"
}

# 执行主函数
add_plugins

# 可选：显示变更
echo -e "\n变更内容:"
diff --color=always -u "$HOME/.zshrc.bak" "$HOME/.zshrc" || true
