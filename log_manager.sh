#!/bin/bash

# UR-NET房屋检查系统 - 日志管理和监控脚本
# 作者: UR-NET检查系统
# 版本: 1.0
# 描述: 管理日志文件、监控系统状态、清理旧文件

# 设置脚本选项
set -e

# 获取脚本所在目录的绝对路径
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 配置参数
LOG_DIR="$SCRIPT_DIR/logs"
RESULTS_DIR="$SCRIPT_DIR/results"
MAX_LOG_DAYS=7      # 保留日志天数
MAX_RESULT_DAYS=30  # 保留结果天数
MAX_LOG_SIZE="100M" # 单个日志文件最大大小

# 日志函数
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $level in
        "INFO")
            echo -e "${GREEN}[$timestamp][INFO]${NC} $message"
            ;;
        "WARN")
            echo -e "${YELLOW}[$timestamp][WARN]${NC} $message"
            ;;
        "ERROR")
            echo -e "${RED}[$timestamp][ERROR]${NC} $message"
            ;;
        "DEBUG")
            echo -e "${BLUE}[$timestamp][DEBUG]${NC} $message"
            ;;
        "SUCCESS")
            echo -e "${PURPLE}[$timestamp][SUCCESS]${NC} $message"
            ;;
    esac
}

# 显示帮助信息
show_help() {
    cat << EOF
UR-NET房屋检查系统 - 日志管理和监控脚本

用法: $0 [选项]

选项:
    -c, --cleanup     清理旧的日志和结果文件
    -s, --status      显示系统状态和统计信息
    -m, --monitor     实时监控最新日志
    -l, --logs        显示最近的日志文件
    -r, --results     显示最近的结果文件
    -a, --analyze     分析日志和结果统计
    -t, --tail        实时跟踪最新日志文件
    -h, --help        显示此帮助信息

清理选项:
    --force-cleanup   强制清理所有日志和结果文件
    --cleanup-logs    仅清理日志文件
    --cleanup-results 仅清理结果文件

监控选项:
    --check-disk      检查磁盘空间使用情况
    --check-cron      检查定时任务状态
    --check-docker    检查Docker状态

示例:
    $0 -c             # 清理旧文件
    $0 -s             # 显示状态
    $0 -m             # 监控日志
    $0 -a             # 分析统计
    $0 --check-disk   # 检查磁盘

EOF
}

# 创建必要的目录
ensure_directories() {
    mkdir -p "$LOG_DIR" "$RESULTS_DIR"
}

# 清理旧文件
cleanup_old_files() {
    local cleanup_type="${1:-all}"
    
    log "INFO" "开始清理旧文件..."
    
    case $cleanup_type in
        "logs"|"all")
            if [[ -d "$LOG_DIR" ]]; then
                log "INFO" "清理 $MAX_LOG_DAYS 天前的日志文件..."
                local deleted_logs=$(find "$LOG_DIR" -name "*.log" -type f -mtime +$MAX_LOG_DAYS -delete -print | wc -l)
                log "INFO" "删除了 $deleted_logs 个旧日志文件"
            fi
            ;;
    esac
    
    case $cleanup_type in
        "results"|"all")
            if [[ -d "$RESULTS_DIR" ]]; then
                log "INFO" "清理 $MAX_RESULT_DAYS 天前的结果文件..."
                local deleted_results=$(find "$RESULTS_DIR" -name "*.json" -type f -mtime +$MAX_RESULT_DAYS -delete -print | wc -l)
                log "INFO" "删除了 $deleted_results 个旧结果文件"
            fi
            ;;
    esac
    
    log "SUCCESS" "文件清理完成"
}

# 强制清理所有文件
force_cleanup() {
    log "WARN" "即将删除所有日志和结果文件..."
    read -p "确认删除所有文件? (y/N): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm -rf "$LOG_DIR"/*.log 2>/dev/null || true
        rm -rf "$RESULTS_DIR"/*.json 2>/dev/null || true
        log "SUCCESS" "所有文件已删除"
    else
        log "INFO" "操作已取消"
    fi
}

# 显示系统状态
show_status() {
    log "INFO" "系统状态报告"
    echo "========================================"
    
    # 目录状态
    echo -e "${CYAN}目录信息:${NC}"
    echo "  日志目录: $LOG_DIR"
    echo "  结果目录: $RESULTS_DIR"
    echo ""
    
    # 文件统计
    if [[ -d "$LOG_DIR" ]]; then
        local log_count=$(ls -1 "$LOG_DIR"/*.log 2>/dev/null | wc -l)
        local log_size=$(du -sh "$LOG_DIR" 2>/dev/null | cut -f1)
        echo -e "${CYAN}日志文件:${NC}"
        echo "  文件数量: $log_count"
        echo "  总大小: $log_size"
        
        if [[ $log_count -gt 0 ]]; then
            local latest_log=$(ls -t "$LOG_DIR"/*.log 2>/dev/null | head -1)
            local latest_time=$(stat -c %y "$latest_log" 2>/dev/null | cut -d. -f1)
            echo "  最新日志: $(basename "$latest_log")"
            echo "  最新时间: $latest_time"
        fi
        echo ""
    fi
    
    if [[ -d "$RESULTS_DIR" ]]; then
        local result_count=$(ls -1 "$RESULTS_DIR"/*.json 2>/dev/null | wc -l)
        local result_size=$(du -sh "$RESULTS_DIR" 2>/dev/null | cut -f1)
        echo -e "${CYAN}结果文件:${NC}"
        echo "  文件数量: $result_count"
        echo "  总大小: $result_size"
        
        if [[ $result_count -gt 0 ]]; then
            local latest_result=$(ls -t "$RESULTS_DIR"/*.json 2>/dev/null | head -1)
            local latest_time=$(stat -c %y "$latest_result" 2>/dev/null | cut -d. -f1)
            echo "  最新结果: $(basename "$latest_result")"
            echo "  最新时间: $latest_time"
        fi
        echo ""
    fi
    
    # 磁盘使用情况
    echo -e "${CYAN}磁盘使用:${NC}"
    df -h "$SCRIPT_DIR" | tail -1 | awk '{print "  使用率: " $5 "  可用空间: " $4}'
    echo ""
    
    echo "========================================"
}

# 检查磁盘空间
check_disk_space() {
    log "INFO" "检查磁盘空间使用情况..."
    
    local usage=$(df "$SCRIPT_DIR" | tail -1 | awk '{print $5}' | sed 's/%//')
    local available=$(df -h "$SCRIPT_DIR" | tail -1 | awk '{print $4}')
    
    echo -e "${CYAN}磁盘空间状态:${NC}"
    echo "  使用率: ${usage}%"
    echo "  可用空间: $available"
    
    if [[ $usage -gt 90 ]]; then
        log "ERROR" "磁盘空间不足！使用率已达到 ${usage}%"
        log "WARN" "建议立即清理旧文件"
    elif [[ $usage -gt 80 ]]; then
        log "WARN" "磁盘空间紧张，使用率: ${usage}%"
    else
        log "INFO" "磁盘空间充足"
    fi
}

# 检查定时任务状态
check_cron_status() {
    log "INFO" "检查定时任务状态..."
    
    local script_path="$SCRIPT_DIR/run_scheduled.sh"
    local current_crontab=$(crontab -l 2>/dev/null || echo "")
    
    if echo "$current_crontab" | grep -q "$script_path"; then
        log "SUCCESS" "定时任务已配置并运行"
        
        # 检查最近的执行记录
        local latest_log=$(ls -t "$LOG_DIR"/scheduled_run_*.log 2>/dev/null | head -1)
        if [[ -n "$latest_log" ]]; then
            local last_run=$(stat -c %y "$latest_log" 2>/dev/null | cut -d. -f1)
            log "INFO" "最后执行时间: $last_run"
            
            # 检查是否有错误
            if grep -q "ERROR" "$latest_log" 2>/dev/null; then
                log "WARN" "最近的执行中发现错误，请检查日志"
            else
                log "SUCCESS" "最近的执行正常"
            fi
        else
            log "WARN" "未找到执行日志，可能尚未开始执行"
        fi
    else
        log "ERROR" "定时任务未配置"
        log "INFO" "请运行: ./setup_cron.sh -i"
    fi
}

# 检查Docker状态
check_docker_status() {
    log "INFO" "检查Docker状态..."
    
    if command -v docker &> /dev/null; then
        if docker info &> /dev/null; then
            log "SUCCESS" "Docker服务正常运行"
            
            # 检查镜像
            if docker images | grep -q "ur-net-checker"; then
                log "SUCCESS" "Docker镜像已构建"
            else
                log "WARN" "Docker镜像未构建，请运行: docker build -t ur-net-checker ."
            fi
        else
            log "ERROR" "Docker服务未运行"
        fi
    else
        log "ERROR" "Docker未安装"
    fi
}

# 显示最近的日志文件
show_recent_logs() {
    log "INFO" "最近的日志文件:"
    
    if [[ -d "$LOG_DIR" ]]; then
        local logs=($(ls -t "$LOG_DIR"/*.log 2>/dev/null | head -5))
        
        if [[ ${#logs[@]} -gt 0 ]]; then
            for log_file in "${logs[@]}"; do
                local size=$(stat -c %s "$log_file" 2>/dev/null)
                local time=$(stat -c %y "$log_file" 2>/dev/null | cut -d. -f1)
                echo "  $(basename "$log_file") - ${size} bytes - $time"
            done
        else
            log "INFO" "暂无日志文件"
        fi
    else
        log "WARN" "日志目录不存在"
    fi
}

# 显示最近的结果文件
show_recent_results() {
    log "INFO" "最近的结果文件:"
    
    if [[ -d "$RESULTS_DIR" ]]; then
        local results=($(ls -t "$RESULTS_DIR"/*.json 2>/dev/null | head -5))
        
        if [[ ${#results[@]} -gt 0 ]]; then
            for result_file in "${results[@]}"; do
                local size=$(stat -c %s "$result_file" 2>/dev/null)
                local time=$(stat -c %y "$result_file" 2>/dev/null | cut -d. -f1)
                echo "  $(basename "$result_file") - ${size} bytes - $time"
            done
        else
            log "INFO" "暂无结果文件"
        fi
    else
        log "WARN" "结果目录不存在"
    fi
}

# 分析日志和结果统计
analyze_statistics() {
    log "INFO" "分析系统统计信息..."
    echo "========================================"
    
    # 分析日志文件
    if [[ -d "$LOG_DIR" ]]; then
        echo -e "${CYAN}日志分析:${NC}"
        
        local total_runs=$(grep -r "开始执行定时任务" "$LOG_DIR"/*.log 2>/dev/null | wc -l)
        local successful_runs=$(grep -r "定时任务执行完成" "$LOG_DIR"/*.log 2>/dev/null | wc -l)
        local failed_runs=$(grep -r "ERROR" "$LOG_DIR"/*.log 2>/dev/null | wc -l)
        
        echo "  总执行次数: $total_runs"
        echo "  成功次数: $successful_runs"
        echo "  失败次数: $failed_runs"
        
        if [[ $total_runs -gt 0 ]]; then
            local success_rate=$((successful_runs * 100 / total_runs))
            echo "  成功率: ${success_rate}%"
        fi
        echo ""
    fi
    
    # 分析结果文件
    if [[ -d "$RESULTS_DIR" ]]; then
        echo -e "${CYAN}结果分析:${NC}"
        
        local result_files=($(ls "$RESULTS_DIR"/*.json 2>/dev/null))
        if [[ ${#result_files[@]} -gt 0 ]]; then
            local total_properties=0
            local total_vacant=0
            
            for file in "${result_files[@]}"; do
                if [[ -f "$file" ]] && command -v jq &> /dev/null; then
                    local properties=$(jq '. | length' "$file" 2>/dev/null || echo "0")
                    local vacant=$(jq '[.[] | select(.status == "vacant")] | length' "$file" 2>/dev/null || echo "0")
                    
                    total_properties=$((total_properties + properties))
                    total_vacant=$((total_vacant + vacant))
                fi
            done
            
            echo "  检查的房产总数: $total_properties"
            echo "  发现的空置房产: $total_vacant"
            
            if [[ $total_properties -gt 0 ]]; then
                local vacant_rate=$((total_vacant * 100 / total_properties))
                echo "  空置率: ${vacant_rate}%"
            fi
        else
            echo "  暂无结果数据"
        fi
        echo ""
    fi
    
    echo "========================================"
}

# 实时跟踪最新日志
tail_latest_log() {
    local latest_log=$(ls -t "$LOG_DIR"/*.log 2>/dev/null | head -1)
    
    if [[ -n "$latest_log" ]]; then
        log "INFO" "实时跟踪日志文件: $(basename "$latest_log")"
        log "INFO" "按 Ctrl+C 退出"
        echo ""
        tail -f "$latest_log"
    else
        log "WARN" "未找到日志文件"
    fi
}

# 实时监控
monitor_system() {
    log "INFO" "开始实时监控系统..."
    log "INFO" "按 Ctrl+C 退出监控"
    echo ""
    
    while true; do
        clear
        echo -e "${PURPLE}UR-NET房屋检查系统 - 实时监控${NC}"
        echo "========================================"
        echo "监控时间: $(date '+%Y-%m-%d %H:%M:%S')"
        echo ""
        
        # 显示系统状态
        show_status
        
        # 检查最新日志
        local latest_log=$(ls -t "$LOG_DIR"/*.log 2>/dev/null | head -1)
        if [[ -n "$latest_log" ]]; then
            echo -e "${CYAN}最新日志内容 (最后5行):${NC}"
            tail -5 "$latest_log" 2>/dev/null || echo "无法读取日志"
            echo ""
        fi
        
        echo "========================================"
        echo "下次刷新: 30秒后"
        
        sleep 30
    done
}

# 主函数
main() {
    ensure_directories
    
    case "${1:-}" in
        -c|--cleanup)
            cleanup_old_files
            ;;
        --cleanup-logs)
            cleanup_old_files "logs"
            ;;
        --cleanup-results)
            cleanup_old_files "results"
            ;;
        --force-cleanup)
            force_cleanup
            ;;
        -s|--status)
            show_status
            ;;
        -m|--monitor)
            monitor_system
            ;;
        -l|--logs)
            show_recent_logs
            ;;
        -r|--results)
            show_recent_results
            ;;
        -a|--analyze)
            analyze_statistics
            ;;
        -t|--tail)
            tail_latest_log
            ;;
        --check-disk)
            check_disk_space
            ;;
        --check-cron)
            check_cron_status
            ;;
        --check-docker)
            check_docker_status
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