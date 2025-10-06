#!/bin/bash

# UR-NET房屋检查和邮件发送自动化脚本
# 作者: UR-NET检查系统
# 版本: 1.0
# 描述: 自动执行房屋检查并发送结果邮件

# 设置脚本选项
set -e  # 遇到错误时退出
set -u  # 使用未定义变量时退出

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 加载.env文件中的配置
load_env_config() {
    if [[ -f ".env" ]]; then
        # 读取.env文件中的DEFAULT_TO_ADDR
        local env_email=$(grep "^DEFAULT_TO_ADDR=" .env | cut -d'=' -f2)
        if [[ -n "$env_email" ]]; then
            DEFAULT_EMAIL="$env_email"
        fi
    fi
}

# 默认参数
DEFAULT_EMAIL="your_email@example.com"  # 将被.env文件覆盖
DEFAULT_DELAY="2.0"
DEFAULT_FILE="urls.txt"
DEFAULT_RESULTS_DIR="results"

# 加载环境配置
load_env_config

# 初始化变量
EMAIL="$DEFAULT_EMAIL"
DELAY="$DEFAULT_DELAY"
CSV_FILE="$DEFAULT_FILE"
RESULTS_DIR="$DEFAULT_RESULTS_DIR"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
OUTPUT_FILE="${RESULTS_DIR}/ur_net_results_${TIMESTAMP}.json"
LOG_FILE="${RESULTS_DIR}/execution_log_${TIMESTAMP}.log"

# 帮助信息
show_help() {
    cat << EOF
UR-NET房屋检查和邮件发送自动化脚本

用法: $0 [选项]

选项:
    -e, --email EMAIL     指定收件人邮箱 (默认: $DEFAULT_EMAIL)
    -d, --delay SECONDS   指定检查延时秒数 (默认: $DEFAULT_DELAY)
    -f, --file FILE       指定CSV文件路径 (默认: $DEFAULT_FILE)
    -h, --help           显示此帮助信息

示例:
    $0                                          # 使用默认参数
    $0 -e user@example.com                      # 指定收件人
    $0 -d 3.0 -f my_urls.txt -e user@example.com  # 指定所有参数

功能:
    1. 检查Python环境和必要文件
    2. 运行UR-NET批量房屋检查
    3. 自动发送检查结果邮件
    4. 生成详细的执行日志

输出文件:
    - 检查结果: ${RESULTS_DIR}/ur_net_results_TIMESTAMP.json
    - 执行日志: ${RESULTS_DIR}/execution_log_TIMESTAMP.log

EOF
}

# 日志函数
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $level in
        "INFO")
            echo -e "${GREEN}[INFO]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        "WARN")
            echo -e "${YELLOW}[WARN]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        "ERROR")
            echo -e "${RED}[ERROR]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        "DEBUG")
            echo -e "${BLUE}[DEBUG]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        *)
            echo "[$timestamp] $message" | tee -a "$LOG_FILE"
            ;;
    esac
}

# 错误处理函数
error_exit() {
    log "ERROR" "$1"
    exit 1
}

# 检查Python环境
check_python_env() {
    log "INFO" "检查Python环境..."
    
    if ! command -v python3 &> /dev/null; then
        error_exit "Python3未安装或不在PATH中"
    fi
    
    local python_version=$(python3 --version 2>&1)
    log "INFO" "Python版本: $python_version"
    
    # 检查必要的Python包
    local required_packages=("requests" "beautifulsoup4" "selenium")
    for package in "${required_packages[@]}"; do
        if ! python3 -c "import $package" &> /dev/null; then
            log "WARN" "Python包 '$package' 未安装，可能影响程序运行"
        fi
    done
}

# 检查必要文件
check_required_files() {
    log "INFO" "检查必要文件..."
    
    local required_files=("ur_net_batch_property_checker.py" "ur_net_email_sender.py" "$CSV_FILE")
    
    for file in "${required_files[@]}"; do
        if [[ ! -f "$file" ]]; then
            error_exit "必要文件不存在: $file"
        fi
        log "DEBUG" "文件检查通过: $file"
    done
}

# 创建结果目录
create_results_dir() {
    if [[ ! -d "$RESULTS_DIR" ]]; then
        mkdir -p "$RESULTS_DIR"
        log "INFO" "创建结果目录: $RESULTS_DIR"
    fi
}

# 清理旧文件
cleanup_old_files() {
    log "INFO" "清理旧的临时文件..."
    
    # 保留最近7天的结果文件
    find "$RESULTS_DIR" -name "ur_net_results_*.json" -mtime +7 -delete 2>/dev/null || true
    find "$RESULTS_DIR" -name "execution_log_*.log" -mtime +7 -delete 2>/dev/null || true
    
    log "DEBUG" "清理完成"
}

# 运行房屋检查
run_property_check() {
    log "INFO" "开始运行UR-NET房屋检查..."
    log "INFO" "参数: CSV文件=$CSV_FILE, 延时=$DELAY秒, 输出文件=$OUTPUT_FILE"
    
    local start_time=$(date +%s)
    
    if python3 ur_net_batch_property_checker.py -c "$CSV_FILE" -d "$DELAY" -o json -p "$OUTPUT_FILE" --verbose; then
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        log "INFO" "房屋检查完成，耗时: ${duration}秒"
        
        # 检查输出文件是否生成
        if [[ ! -f "$OUTPUT_FILE" ]]; then
            error_exit "检查完成但输出文件未生成: $OUTPUT_FILE"
        fi
        
        # 显示检查结果摘要
        show_check_summary
    else
        error_exit "房屋检查失败"
    fi
}

# 显示检查结果摘要
show_check_summary() {
    log "INFO" "检查结果摘要:"
    
    if command -v jq &> /dev/null; then
        # 使用jq解析JSON
        local total_checked=$(jq -r '.summary.total_checked // 0' "$OUTPUT_FILE" 2>/dev/null || echo "0")
        local total_vacant=$(jq -r '.summary.total_vacant_rooms // 0' "$OUTPUT_FILE" 2>/dev/null || echo "0")
        local timestamp=$(jq -r '.timestamp // "未知"' "$OUTPUT_FILE" 2>/dev/null || echo "未知")
        
        log "INFO" "  检查时间: $timestamp"
        log "INFO" "  总检查数: $total_checked"
        log "INFO" "  空房总数: $total_vacant"
    else
        # 简单的文本解析
        log "INFO" "  结果文件: $OUTPUT_FILE"
        log "INFO" "  文件大小: $(du -h "$OUTPUT_FILE" | cut -f1)"
    fi
}

# 检查是否需要发送邮件
should_send_email() {
    log "INFO" "检查是否需要发送邮件..."
    
    # 创建临时Python脚本来检查邮件发送条件
    local temp_script="/tmp/check_email_condition_$$.py"
    cat > "$temp_script" << 'EOF'
import json
import sys
import os
import glob

def compare_results(current_file, previous_file):
    try:
        with open(current_file, 'r', encoding='utf-8') as f:
            current_data = json.load(f)
        with open(previous_file, 'r', encoding='utf-8') as f:
            previous_data = json.load(f)
        
        # 获取当前和之前的物件数据
        current_properties = current_data.get('results', [])
        previous_properties = previous_data.get('results', [])
        
        # 检查是否有新的空室物件
        current_vacant = {prop['url']: prop.get('total_vacant', 0) 
                         for prop in current_properties if prop.get('total_vacant', 0) > 0}
        previous_vacant = {prop['url']: prop.get('total_vacant', 0) 
                          for prop in previous_properties if prop.get('total_vacant', 0) > 0}
        
        # 检查新增的空室物件
        new_properties = set(current_vacant.keys()) - set(previous_vacant.keys())
        
        # 检查空室数量增加的物件
        increased_properties = []
        for prop_url in current_vacant:
            if prop_url in previous_vacant:
                if current_vacant[prop_url] > previous_vacant[prop_url]:
                    increased_properties.append(prop_url)
        
        has_new_properties = len(new_properties) > 0 or len(increased_properties) > 0
        
        return {
            'has_new_properties': has_new_properties,
            'new_properties': list(new_properties),
            'increased_properties': increased_properties
        }
    except Exception as e:
        print(f'ERROR: {e}', file=sys.stderr)
        return {'has_new_properties': False, 'error': str(e)}

# 主逻辑
if len(sys.argv) != 2:
    print('ERROR: Missing current file argument')
    sys.exit(1)

current_file = sys.argv[1]
if not os.path.exists(current_file):
    print('ERROR: Current result file not found')
    sys.exit(1)

# 查找前一个结果文件
all_files = glob.glob('results/ur_net_results_*.json')
if len(all_files) <= 1:
    print('SEND: First run detected')
    sys.exit(0)

# 排除当前文件，找到最新的前一个文件
previous_files = [f for f in all_files if f != current_file]
if not previous_files:
    print('SEND: No previous results found')
    sys.exit(0)

previous_file = max(previous_files, key=os.path.getmtime)
result = compare_results(current_file, previous_file)

if result.get('error'):
    print(f'ERROR: {result["error"]}')
    sys.exit(1)

if result['has_new_properties']:
    new_count = len(result['new_properties'])
    increased_count = len(result['increased_properties'])
    print(f'SEND: New vacant properties detected (new: {new_count}, increased: {increased_count})')
    sys.exit(0)
else:
    print('SKIP: No new vacant properties found')
    sys.exit(2)
EOF
    
    # 运行Python脚本并捕获输出到临时文件
    local output_file=$(mktemp)
    python3 "$temp_script" "$OUTPUT_FILE" > "$output_file" 2>&1
    local exit_code=$?
    
    # 读取输出
    local check_result=$(cat "$output_file")
    
    # 清理临时文件
    rm -f "$temp_script" "$output_file"
    
    log "INFO" "$check_result"
    
    if [[ $exit_code -eq 0 ]]; then
        return 0  # 需要发送邮件
    elif [[ $exit_code -eq 2 ]]; then
        return 1  # 不需要发送邮件
    else
        log "ERROR" "邮件发送检查失败"
        return 2  # 检查失败
    fi
}

# 发送邮件
send_email() {
    log "INFO" "开始发送检查结果邮件..."
    log "INFO" "收件人: $EMAIL"
    
    local subject="UR-NET房屋检查结果 - $(date '+%Y-%m-%d %H:%M')"
    
    if python3 ur_net_email_sender.py -j "$OUTPUT_FILE" -to "$EMAIL" -s "$subject"; then
        log "INFO" "邮件发送成功"
    else
        error_exit "邮件发送失败"
    fi
}

# 解析命令行参数
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -e|--email)
                EMAIL="$2"
                shift 2
                ;;
            -d|--delay)
                DELAY="$2"
                shift 2
                ;;
            -f|--file)
                CSV_FILE="$2"
                shift 2
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                error_exit "未知参数: $1。使用 -h 查看帮助信息。"
                ;;
        esac
    done
    
    # 验证参数
    if [[ ! "$DELAY" =~ ^[0-9]+\.?[0-9]*$ ]]; then
        error_exit "延时参数必须是数字: $DELAY"
    fi
    
    if [[ ! "$EMAIL" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        error_exit "邮箱格式不正确: $EMAIL"
    fi
}

# 主函数
main() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}  UR-NET房屋检查和邮件发送自动化脚本  ${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo
    
    # 解析命令行参数
    parse_arguments "$@"
    
    # 创建结果目录和日志文件
    create_results_dir
    
    # 更新输出文件路径（包含时间戳）
    OUTPUT_FILE="${RESULTS_DIR}/ur_net_results_${TIMESTAMP}.json"
    LOG_FILE="${RESULTS_DIR}/execution_log_${TIMESTAMP}.log"
    
    log "INFO" "脚本开始执行"
    log "INFO" "参数配置:"
    log "INFO" "  邮箱: $EMAIL"
    log "INFO" "  延时: $DELAY 秒"
    log "INFO" "  CSV文件: $CSV_FILE"
    log "INFO" "  输出文件: $OUTPUT_FILE"
    log "INFO" "  日志文件: $LOG_FILE"
    
    # 执行检查步骤
    check_python_env
    check_required_files
    cleanup_old_files
    
    # 执行主要功能
    run_property_check
    
    # 检查是否需要发送邮件
    local email_sent=false
    if should_send_email; then
        send_email
        email_sent=true
    else
        log "INFO" "根据检查结果，跳过邮件发送"
    fi
    
    log "INFO" "脚本执行完成"
    echo
    echo -e "${GREEN}✓ 所有任务完成！${NC}"
    echo -e "${GREEN}✓ 检查结果: $OUTPUT_FILE${NC}"
    echo -e "${GREEN}✓ 执行日志: $LOG_FILE${NC}"
    if [[ "$email_sent" == true ]]; then
        echo -e "${GREEN}✓ 邮件已发送至: $EMAIL${NC}"
    else
        echo -e "${YELLOW}📧 邮件发送已跳过（无新空室物件）${NC}"
    fi
}

# 信号处理
trap 'log "ERROR" "脚本被中断"; exit 1' INT TERM

# 执行主函数
main "$@"