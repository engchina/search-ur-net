#!/bin/bash

# UR-NET房屋检查系统 - Cron 定时任务设置脚本
# 作者: UR-NET检查系统
# 版本: 1.0
# 描述: 自动配置 cron 定时任务

# 设置脚本选项
set -e

# 获取脚本所在目录的绝对路径
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log() {
    local level=$1
    shift
    local message="$*"
    
    case $level in
        "INFO")
            echo -e "${GREEN}[INFO]${NC} $message"
            ;;
        "WARN")
            echo -e "${YELLOW}[WARN]${NC} $message"
            ;;
        "ERROR")
            echo -e "${RED}[ERROR]${NC} $message"
            ;;
        "DEBUG")
            echo -e "${BLUE}[DEBUG]${NC} $message"
            ;;
    esac
}

# 显示帮助信息
show_help() {
    cat << EOF
UR-NET房屋检查系统 - Cron 定时任务设置脚本

用法: $0 [选项]

选项:
    -i, --install     安装定时任务（日本时间8:00-19:00，每10分钟执行一次）
    -r, --remove      移除定时任务
    -s, --status      查看定时任务状态
    -l, --list        列出所有相关的定时任务
    -h, --help        显示此帮助信息

示例:
    $0 -i             # 安装定时任务
    $0 -r             # 移除定时任务
    $0 -s             # 查看状态
    $0 -l             # 列出任务

注意:
    - 定时任务在日本时间8:00-19:00期间每10分钟执行一次
    - 对应太平洋时间15:00-02:00（次日）
    - 日志文件保存在 logs/ 目录下
    - 结果文件保存在 results/ 目录下

EOF
}

# 检查 cron 服务
check_cron_service() {
    if ! command -v crontab &> /dev/null; then
        log "ERROR" "crontab 命令不存在，请安装 cron 服务"
        log "INFO" "Ubuntu/Debian: sudo apt-get install cron"
        log "INFO" "CentOS/RHEL: sudo yum install cronie"
        exit 1
    fi
    
    # 检查 cron 服务是否运行
    if systemctl is-active --quiet cron 2>/dev/null || systemctl is-active --quiet crond 2>/dev/null; then
        log "INFO" "Cron 服务正在运行"
    else
        log "WARN" "Cron 服务可能未运行"
        log "INFO" "请启动 cron 服务: sudo systemctl start cron"
    fi
}

# 安装定时任务
install_cron() {
    log "INFO" "开始安装定时任务..."
    
    # 检查脚本文件是否存在
    local script_path="$SCRIPT_DIR/run_scheduled.sh"
    if [[ ! -f "$script_path" ]]; then
        log "ERROR" "脚本文件不存在: $script_path"
        exit 1
    fi
    
    # 确保脚本有执行权限
    chmod +x "$script_path"
    
    # 创建 cron 任务条目 - 日本时间 8:00-19:00 (太平洋时间 15:00-02:00)
    # 分为两个时间段：15:00-23:59 和 00:00-02:00
    local cron_entry1="*/10 15-23 * * * $script_path >/dev/null 2>&1"
    local cron_entry2="*/10 0-2 * * * $script_path >/dev/null 2>&1"
    local cron_comment="# UR-NET房屋检查系统 - 日本时间8:00-19:00执行（每10分钟）"
    
    # 获取当前的 crontab
    local current_crontab=$(crontab -l 2>/dev/null || echo "")
    
    # 检查是否已经存在相同的任务
    if echo "$current_crontab" | grep -q "$script_path"; then
        log "WARN" "定时任务已存在，将先移除旧任务"
        remove_cron
    fi
    
    # 添加新的 cron 任务
    {
        echo "$current_crontab"
        echo "$cron_comment"
        echo "$cron_entry1"
        echo "$cron_entry2"
    } | crontab -
    
    log "INFO" "定时任务安装成功"
    log "INFO" "任务详情: 日本时间8:00-19:00，每10分钟执行一次"
    log "INFO" "太平洋时间: 15:00-02:00（次日）"
    log "INFO" "脚本路径: $script_path"
    log "INFO" "日志目录: $SCRIPT_DIR/logs/"
    log "INFO" "结果目录: $SCRIPT_DIR/results/"
}

# 移除定时任务
remove_cron() {
    log "INFO" "开始移除定时任务..."
    
    local script_path="$SCRIPT_DIR/run_scheduled.sh"
    
    # 获取当前的 crontab
    local current_crontab=$(crontab -l 2>/dev/null || echo "")
    
    if echo "$current_crontab" | grep -q "$script_path"; then
        # 移除包含脚本路径的行和相关注释
        local new_crontab=$(echo "$current_crontab" | grep -v "$script_path" | grep -v "# UR-NET房屋检查系统")
        
        if [[ -n "$new_crontab" ]]; then
            echo "$new_crontab" | crontab -
        else
            crontab -r 2>/dev/null || true
        fi
        
        log "INFO" "定时任务移除成功"
    else
        log "WARN" "未找到相关的定时任务"
    fi
}

# 查看定时任务状态
show_status() {
    log "INFO" "查看定时任务状态..."
    
    local script_path="$SCRIPT_DIR/run_scheduled.sh"
    local current_crontab=$(crontab -l 2>/dev/null || echo "")
    
    if echo "$current_crontab" | grep -q "$script_path"; then
        log "INFO" "定时任务状态: 已安装"
        echo ""
        echo "当前定时任务:"
        echo "$current_crontab" | grep -A1 -B1 "$script_path"
        echo ""
        
        # 显示最近的日志文件
        local log_dir="$SCRIPT_DIR/logs"
        if [[ -d "$log_dir" ]]; then
            local latest_log=$(ls -t "$log_dir"/scheduled_run_*.log 2>/dev/null | head -1)
            if [[ -n "$latest_log" ]]; then
                log "INFO" "最新日志文件: $latest_log"
                log "INFO" "最新日志内容（最后10行）:"
                echo "----------------------------------------"
                tail -10 "$latest_log" 2>/dev/null || echo "无法读取日志文件"
                echo "----------------------------------------"
            else
                log "INFO" "暂无执行日志"
            fi
        fi
        
        # 显示最近的结果文件
        local results_dir="$SCRIPT_DIR/results"
        if [[ -d "$results_dir" ]]; then
            local latest_result=$(ls -t "$results_dir"/ur_net_results_*.json 2>/dev/null | head -1)
            if [[ -n "$latest_result" ]]; then
                log "INFO" "最新结果文件: $latest_result"
                local file_size=$(stat -f%z "$latest_result" 2>/dev/null || stat -c%s "$latest_result" 2>/dev/null || echo "0")
                log "INFO" "文件大小: ${file_size} bytes"
            else
                log "INFO" "暂无结果文件"
            fi
        fi
    else
        log "INFO" "定时任务状态: 未安装"
    fi
}

# 列出所有相关的定时任务
list_cron() {
    log "INFO" "列出所有 cron 定时任务..."
    
    local current_crontab=$(crontab -l 2>/dev/null || echo "")
    
    if [[ -n "$current_crontab" ]]; then
        echo ""
        echo "当前用户的所有定时任务:"
        echo "========================================"
        echo "$current_crontab"
        echo "========================================"
        echo ""
    else
        log "INFO" "当前用户没有定时任务"
    fi
}

# 主函数
main() {
    case "${1:-}" in
        -i|--install)
            check_cron_service
            install_cron
            ;;
        -r|--remove)
            remove_cron
            ;;
        -s|--status)
            show_status
            ;;
        -l|--list)
            list_cron
            ;;
        -h|--help)
            show_help
            ;;
        "")
            log "ERROR" "请指定操作选项"
            show_help
            exit 1
            ;;
        *)
            log "ERROR" "未知选项: $1"
            show_help
            exit 1
            ;;
    esac
}

# 执行主函数
main "$@"