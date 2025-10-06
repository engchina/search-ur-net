#!/bin/bash

# UR-NET房屋检查系统 - 定时执行脚本
# 作者: UR-NET检查系统
# 版本: 1.0
# 描述: 用于 cron 定时任务的 Docker 执行脚本

# 设置脚本选项
set -e  # 遇到错误时退出

# 获取脚本所在目录的绝对路径
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# 配置参数
PROJECT_NAME="ur-net-checker"
CONTAINER_NAME="${PROJECT_NAME}-scheduled"
LOG_DIR="$SCRIPT_DIR/logs"
RESULTS_DIR="$SCRIPT_DIR/results"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
LOG_FILE="$LOG_DIR/scheduled_run_$TIMESTAMP.log"

# 颜色定义（用于日志）
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 创建必要的目录
mkdir -p "$LOG_DIR"
mkdir -p "$RESULTS_DIR"

# 日志函数
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $level in
        "INFO")
            echo -e "[$timestamp] ${GREEN}[INFO]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        "WARN")
            echo -e "[$timestamp] ${YELLOW}[WARN]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        "ERROR")
            echo -e "[$timestamp] ${RED}[ERROR]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        "DEBUG")
            echo -e "[$timestamp] ${BLUE}[DEBUG]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        *)
            echo "[$timestamp] $message" | tee -a "$LOG_FILE"
            ;;
    esac
}

# 清理函数
cleanup() {
    log "INFO" "开始清理容器..."
    
    # 停止并删除可能存在的容器
    if docker ps -a --format "table {{.Names}}" | grep -q "^${CONTAINER_NAME}$"; then
        docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
        log "INFO" "已清理容器: $CONTAINER_NAME"
    fi
}

# 检查 Docker 环境
check_docker() {
    if ! command -v docker &> /dev/null; then
        log "ERROR" "Docker 未安装或不在 PATH 中"
        exit 1
    fi
    
    if ! docker info &> /dev/null; then
        log "ERROR" "Docker 服务未运行或当前用户无权限访问 Docker"
        exit 1
    fi
    
    log "INFO" "Docker 环境检查通过"
}

# 检查镜像是否存在
check_image() {
    if docker images "$PROJECT_NAME" | grep -q "$PROJECT_NAME"; then
        log "INFO" "Docker 镜像已存在: $PROJECT_NAME"
        return 0
    else
        log "ERROR" "Docker 镜像不存在: $PROJECT_NAME"
        log "INFO" "请先运行: docker build -t $PROJECT_NAME ."
        exit 1
    fi
}

# 检查必要文件
check_files() {
    local required_files=("urls.txt" "Dockerfile")
    
    for file in "${required_files[@]}"; do
        if [[ ! -f "$file" ]]; then
            log "ERROR" "必要文件不存在: $file"
            exit 1
        fi
    done
    
    log "INFO" "文件检查通过"
}

# 运行房屋检查
run_checker() {
    log "INFO" "开始运行房屋检查..."
    
    # 构建 Docker 运行命令
    local docker_cmd=(
        "docker" "run"
        "--name" "$CONTAINER_NAME"
        "--rm"
        "-v" "$RESULTS_DIR:/app/results"
        "-v" "$SCRIPT_DIR/urls.txt:/app/urls.txt:ro"
    )
    
    # 如果存在 .env 文件，挂载它
    if [[ -f ".env" ]]; then
        docker_cmd+=("-v" "$SCRIPT_DIR/.env:/app/.env:ro")
    fi
    
    # 添加镜像和命令
    docker_cmd+=("$PROJECT_NAME")
    docker_cmd+=("python" "ur_net_batch_property_checker.py" "-f" "urls.txt" "-d" "2.0")
    
    log "DEBUG" "执行命令: ${docker_cmd[*]}"
    
    # 执行 Docker 命令并捕获输出
    if "${docker_cmd[@]}" >> "$LOG_FILE" 2>&1; then
        log "INFO" "房屋检查完成"
        
        # 显示最新的结果文件
        local latest_result=$(ls -t "$RESULTS_DIR"/ur_net_results_*.json 2>/dev/null | head -1)
        if [[ -n "$latest_result" ]]; then
            log "INFO" "结果文件: $latest_result"
            
            # 检查结果文件大小
            local file_size=$(stat -f%z "$latest_result" 2>/dev/null || stat -c%s "$latest_result" 2>/dev/null || echo "0")
            log "INFO" "结果文件大小: ${file_size} bytes"
        else
            log "WARN" "未找到结果文件"
        fi
        
        return 0
    else
        log "ERROR" "房屋检查失败"
        return 1
    fi
}

# 检查是否需要发送邮件
should_send_email() {
    local latest_result="$1"
    
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
    
    # 在Docker容器中运行检查脚本
    local docker_cmd=(
        "docker" "run"
        "--name" "${CONTAINER_NAME}-check"
        "--rm"
        "-v" "$RESULTS_DIR:/app/results:ro"
        "-v" "$temp_script:/app/check_email.py:ro"
        "$PROJECT_NAME"
        "python" "/app/check_email.py" "$latest_result"
    )
    
    "${docker_cmd[@]}" > "$output_file" 2>&1
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

# 发送邮件（如果配置了且需要发送）
send_email_if_needed() {
    local latest_result="$1"
    
    # 检查是否配置了邮件
    local email_configured=false
    
    if [[ -f ".env" ]]; then
        if grep -q "^DEFAULT_TO_ADDR=" ".env" && grep -q "^SMTP_" ".env"; then
            email_configured=true
        fi
    fi
    
    if [[ "$email_configured" != true ]]; then
        log "INFO" "未配置邮件，跳过邮件发送"
        return 0
    fi
    
    # 检查是否需要发送邮件
    if should_send_email "$latest_result"; then
        log "INFO" "检测到新的空室物件，开始发送邮件..."
        
        # 获取邮件主题
        local subject="UR-NET房屋检查结果 - $(date '+%Y-%m-%d %H:%M')"
        
        local docker_cmd=(
            "docker" "run"
            "--name" "${CONTAINER_NAME}-email"
            "--rm"
            "-v" "$RESULTS_DIR:/app/results:ro"
            "-v" "$SCRIPT_DIR/.env:/app/.env:ro"
            "$PROJECT_NAME"
            "python" "ur_net_email_sender.py" "-j" "$latest_result" "-s" "$subject"
        )
        
        if "${docker_cmd[@]}" >> "$LOG_FILE" 2>&1; then
            log "INFO" "邮件发送完成"
            return 0
        else
            log "ERROR" "邮件发送失败"
            return 1
        fi
    else
        log "INFO" "根据检查结果，跳过邮件发送（无新空室物件）"
        return 0
    fi
}

# 清理旧日志文件（保留最近7天）
cleanup_old_logs() {
    log "INFO" "清理旧日志文件..."
    
    # 删除7天前的日志文件
    find "$LOG_DIR" -name "scheduled_run_*.log" -mtime +7 -delete 2>/dev/null || true
    
    # 删除7天前的结果文件（可选，根据需要调整）
    # find "$RESULTS_DIR" -name "ur_net_results_*.json" -mtime +7 -delete 2>/dev/null || true
    
    log "INFO" "日志清理完成"
}

# 主执行函数
main() {
    log "INFO" "=========================================="
    log "INFO" "UR-NET房屋检查系统 - 定时执行开始"
    log "INFO" "执行时间: $(date)"
    log "INFO" "工作目录: $SCRIPT_DIR"
    log "INFO" "=========================================="
    
    # 设置清理陷阱
    trap cleanup EXIT
    
    # 执行检查流程
    check_docker
    check_image
    check_files
    
    # 运行检查
    if run_checker; then
        # 获取最新的结果文件
        local latest_result=$(ls -t "$RESULTS_DIR"/ur_net_results_*.json 2>/dev/null | head -1)
        
        if [[ -n "$latest_result" ]]; then
            # 发送邮件（如果配置了且需要发送）
            send_email_if_needed "$(basename "$latest_result")"
        else
            log "WARN" "未找到结果文件，跳过邮件发送"
        fi
        
        # 清理旧文件
        cleanup_old_logs
        
        log "INFO" "定时任务执行成功"
        exit 0
    else
        log "ERROR" "定时任务执行失败"
        exit 1
    fi
}

# 捕获中断信号
trap 'log "WARN" "脚本被中断"; cleanup; exit 130' INT TERM

# 执行主函数
main "$@"