#!/bin/bash

# UR-NET房屋检查系统 - 时区辅助脚本
# 作者: UR-NET检查系统
# 版本: 1.0
# 描述: 帮助管理和理解时区转换

# 设置脚本选项
set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
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
        "SUCCESS")
            echo -e "${PURPLE}[SUCCESS]${NC} $message"
            ;;
    esac
}

# 显示帮助信息
show_help() {
    cat << EOF
UR-NET房屋检查系统 - 时区辅助脚本

用法: $0 [选项]

选项:
    -c, --current     显示当前时区信息
    -j, --japan       显示日本时间信息
    -s, --schedule    显示执行时间表
    -t, --test        测试时区转换
    -h, --help        显示此帮助信息

示例:
    $0 -c             # 显示当前时区
    $0 -j             # 显示日本时间
    $0 -s             # 显示执行计划
    $0 -t             # 测试时区转换

EOF
}

# 显示当前时区信息
show_current_timezone() {
    log "INFO" "当前系统时区信息"
    echo "========================================"
    
    # 系统时区
    echo -e "${CYAN}系统时区:${NC}"
    if command -v timedatectl &> /dev/null; then
        timedatectl | grep "Time zone"
    else
        echo "  时区文件: $(readlink -f /etc/localtime 2>/dev/null || echo "未知")"
    fi
    
    # 当前时间
    echo -e "${CYAN}当前时间:${NC}"
    echo "  本地时间: $(date)"
    echo "  UTC时间: $(date -u)"
    
    # 环境变量
    echo -e "${CYAN}时区环境变量:${NC}"
    echo "  TZ: ${TZ:-未设置}"
    
    echo "========================================"
}

# 显示日本时间信息
show_japan_time() {
    log "INFO" "日本时间信息"
    echo "========================================"
    
    # 日本当前时间
    echo -e "${CYAN}日本时间 (JST):${NC}"
    if command -v TZ &> /dev/null; then
        echo "  当前时间: $(TZ='Asia/Tokyo' date)"
    else
        # 手动计算（假设系统是UTC）
        local utc_hour=$(date -u +%H)
        local jst_hour=$((utc_hour + 9))
        if [[ $jst_hour -ge 24 ]]; then
            jst_hour=$((jst_hour - 24))
        fi
        echo "  当前时间: $(date -u +%Y-%m-%d) $(printf "%02d" $jst_hour):$(date -u +%M:%S) JST"
    fi
    
    # 太平洋时间
    echo -e "${CYAN}太平洋时间 (PST/PDT):${NC}"
    if command -v TZ &> /dev/null; then
        echo "  当前时间: $(TZ='America/Los_Angeles' date)"
    else
        echo "  请安装 tzdata 包以获取准确时间"
    fi
    
    # 时差说明
    echo -e "${CYAN}时差说明:${NC}"
    echo "  日本时间 = UTC + 9小时"
    echo "  太平洋标准时间 = UTC - 8小时 (冬季)"
    echo "  太平洋夏令时间 = UTC - 7小时 (夏季)"
    echo "  日本时间 = 太平洋时间 + 17小时 (冬季)"
    echo "  日本时间 = 太平洋时间 + 16小时 (夏季)"
    
    echo "========================================"
}

# 显示执行时间表
show_schedule() {
    log "INFO" "定时任务执行时间表"
    echo "========================================"
    
    echo -e "${CYAN}执行时间安排:${NC}"
    echo "  日本时间: 8:00 - 19:00 (每10分钟)"
    echo "  太平洋时间: 15:00 - 02:00+1 (每10分钟)"
    echo ""
    
    echo -e "${CYAN}Cron 表达式:${NC}"
    echo "  */10 15-23 * * *  # 太平洋时间 15:00-23:59"
    echo "  */10 0-2 * * *    # 太平洋时间 00:00-02:59"
    echo ""
    
    echo -e "${CYAN}详细时间对照表:${NC}"
    echo "  日本时间  |  太平洋时间"
    echo "  ---------|----------"
    echo "  08:00    |  15:00 (前一天)"
    echo "  09:00    |  16:00 (前一天)"
    echo "  10:00    |  17:00 (前一天)"
    echo "  11:00    |  18:00 (前一天)"
    echo "  12:00    |  19:00 (前一天)"
    echo "  13:00    |  20:00 (前一天)"
    echo "  14:00    |  21:00 (前一天)"
    echo "  15:00    |  22:00 (前一天)"
    echo "  16:00    |  23:00 (前一天)"
    echo "  17:00    |  00:00"
    echo "  18:00    |  01:00"
    echo "  19:00    |  02:00"
    echo ""
    
    echo -e "${CYAN}注意事项:${NC}"
    echo "  - 夏令时期间时差会减少1小时"
    echo "  - 建议定期检查时区设置"
    echo "  - 日志文件使用本地时间记录"
    
    echo "========================================"
}

# 测试时区转换
test_timezone_conversion() {
    log "INFO" "测试时区转换功能"
    echo "========================================"
    
    # 获取当前UTC时间
    local utc_time=$(date -u +"%Y-%m-%d %H:%M:%S")
    echo -e "${CYAN}基准时间 (UTC):${NC} $utc_time"
    echo ""
    
    # 计算各时区时间
    if command -v TZ &> /dev/null; then
        echo -e "${CYAN}各时区当前时间:${NC}"
        echo "  UTC:        $(TZ='UTC' date '+%Y-%m-%d %H:%M:%S')"
        echo "  日本 (JST): $(TZ='Asia/Tokyo' date '+%Y-%m-%d %H:%M:%S')"
        echo "  太平洋:     $(TZ='America/Los_Angeles' date '+%Y-%m-%d %H:%M:%S')"
        echo "  纽约:       $(TZ='America/New_York' date '+%Y-%m-%d %H:%M:%S')"
        echo "  伦敦:       $(TZ='Europe/London' date '+%Y-%m-%d %H:%M:%S')"
    else
        echo -e "${YELLOW}警告: 无法获取准确的时区时间${NC}"
        echo "请安装 tzdata 包: yum install -y tzdata"
    fi
    
    echo ""
    
    # 检查是否在执行时间范围内
    local current_hour=$(date +%H)
    local in_schedule=false
    
    if [[ $current_hour -ge 15 && $current_hour -le 23 ]] || [[ $current_hour -ge 0 && $current_hour -le 2 ]]; then
        in_schedule=true
    fi
    
    echo -e "${CYAN}当前执行状态:${NC}"
    if [[ $in_schedule == true ]]; then
        echo -e "  ${GREEN}✅ 当前时间在执行范围内${NC}"
        echo "  任务将在下一个10分钟整点执行"
    else
        echo -e "  ${YELLOW}⏰ 当前时间不在执行范围内${NC}"
        echo "  下次执行时间: 太平洋时间 15:00"
    fi
    
    echo "========================================"
}

# 主函数
main() {
    case "${1:-}" in
        -c|--current)
            show_current_timezone
            ;;
        -j|--japan)
            show_japan_time
            ;;
        -s|--schedule)
            show_schedule
            ;;
        -t|--test)
            test_timezone_conversion
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