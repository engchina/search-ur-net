#!/bin/bash

# UR-NET房屋检查系统 Docker 运行脚本
# 作者: UR-NET检查系统
# 版本: 1.0
# 描述: 使用 Docker 容器运行房屋检查，解决 GLIBC 兼容性问题

# 设置脚本选项
set -e  # 遇到错误时退出
set -u  # 使用未定义变量时退出

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 默认参数
DEFAULT_DELAY="2.0"
DEFAULT_FILE="urls.txt"
DEFAULT_EMAIL=""
BUILD_IMAGE=false
SEND_EMAIL=false

# 帮助信息
show_help() {
    cat << EOF
UR-NET房屋检查系统 Docker 运行脚本

用法: $0 [选项]

选项:
    -d, --delay SECONDS   指定检查延时秒数 (默认: $DEFAULT_DELAY)
    -f, --file FILE       指定URL文件路径 (默认: $DEFAULT_FILE)
    -e, --email EMAIL     指定收件人邮箱（启用邮件发送）
    -b, --build          重新构建 Docker 镜像
    -h, --help           显示此帮助信息

示例:
    $0                                    # 使用默认参数运行检查
    $0 -d 3.0 -f my_urls.txt             # 指定延时和文件
    $0 -e user@example.com               # 运行检查并发送邮件
    $0 -b                                # 重新构建镜像并运行
    $0 -b -d 2.0 -e user@example.com     # 重新构建并运行完整流程

功能:
    1. 使用 Docker 容器运行，解决 GLIBC 兼容性问题
    2. 自动挂载结果目录和配置文件
    3. 支持邮件发送功能
    4. 提供镜像重建选项

输出文件:
    - 检查结果: ./results/ur_net_results_TIMESTAMP.json
    - 执行日志: 容器内日志

EOF
}

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

# 检查 Docker 是否安装
check_docker() {
    if ! command -v docker &> /dev/null; then
        log "ERROR" "Docker 未安装或不在 PATH 中"
        log "INFO" "请安装 Docker: https://docs.docker.com/get-docker/"
        exit 1
    fi
    
    if ! docker info &> /dev/null; then
        log "ERROR" "Docker 服务未运行或当前用户无权限访问 Docker"
        log "INFO" "请启动 Docker 服务或将当前用户添加到 docker 组"
        exit 1
    fi
    
    log "INFO" "Docker 环境检查通过"
}

# 检查必要文件
check_files() {
    local url_file="$1"
    
    if [[ ! -f "$url_file" ]]; then
        log "ERROR" "URL文件不存在: $url_file"
        exit 1
    fi
    
    if [[ ! -f "Dockerfile" ]]; then
        log "ERROR" "Dockerfile 不存在"
        exit 1
    fi
    
    # 创建结果目录
    mkdir -p results
    
    log "INFO" "文件检查通过"
}

# 构建 Docker 镜像
build_image() {
    log "INFO" "开始构建 Docker 镜像..."
    
    if docker build -t ur-net-checker . ; then
        log "INFO" "Docker 镜像构建成功"
    else
        log "ERROR" "Docker 镜像构建失败"
        exit 1
    fi
}

# 检查镜像是否存在
check_image() {
    if docker images ur-net-checker | grep -q ur-net-checker; then
        log "INFO" "Docker 镜像已存在"
        return 0
    else
        log "WARN" "Docker 镜像不存在，将自动构建"
        return 1
    fi
}

# 运行房屋检查
run_checker() {
    local delay="$1"
    local url_file="$2"
    
    log "INFO" "开始运行房屋检查..."
    log "INFO" "延时设置: ${delay}秒"
    log "INFO" "URL文件: $url_file"
    
    # 构建 Docker 运行命令
    local docker_cmd="docker run --rm"
    docker_cmd+=" -v $(pwd)/results:/app/results"
    docker_cmd+=" -v $(pwd)/$url_file:/app/urls.txt:ro"
    
    # 如果存在 .env 文件，挂载它
    if [[ -f ".env" ]]; then
        docker_cmd+=" -v $(pwd)/.env:/app/.env:ro"
    fi
    
    docker_cmd+=" ur-net-checker"
    docker_cmd+=" python ur_net_batch_property_checker.py -f urls.txt -d $delay"
    
    log "DEBUG" "执行命令: $docker_cmd"
    
    if eval $docker_cmd; then
        log "INFO" "房屋检查完成"
        
        # 显示结果文件
        local result_files=$(ls -t results/ur_net_results_*.json 2>/dev/null | head -1)
        if [[ -n "$result_files" ]]; then
            log "INFO" "结果文件: $result_files"
        fi
    else
        log "ERROR" "房屋检查失败"
        exit 1
    fi
}

# 发送邮件
send_email() {
    local email="$1"
    
    log "INFO" "开始发送邮件到: $email"
    
    # 构建邮件发送命令
    local docker_cmd="docker run --rm"
    docker_cmd+=" -v $(pwd)/results:/app/results:ro"
    
    # 如果存在 .env 文件，挂载它
    if [[ -f ".env" ]]; then
        docker_cmd+=" -v $(pwd)/.env:/app/.env:ro"
    fi
    
    docker_cmd+=" -e DEFAULT_TO_ADDR=$email"
    docker_cmd+=" ur-net-checker"
    docker_cmd+=" python ur_net_email_sender.py"
    
    if eval $docker_cmd; then
        log "INFO" "邮件发送完成"
    else
        log "ERROR" "邮件发送失败"
        exit 1
    fi
}

# 解析命令行参数
DELAY="$DEFAULT_DELAY"
URL_FILE="$DEFAULT_FILE"

while [[ $# -gt 0 ]]; do
    case $1 in
        -d|--delay)
            DELAY="$2"
            shift 2
            ;;
        -f|--file)
            URL_FILE="$2"
            shift 2
            ;;
        -e|--email)
            DEFAULT_EMAIL="$2"
            SEND_EMAIL=true
            shift 2
            ;;
        -b|--build)
            BUILD_IMAGE=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            log "ERROR" "未知参数: $1"
            show_help
            exit 1
            ;;
    esac
done

# 主执行流程
main() {
    log "INFO" "UR-NET房屋检查系统 Docker 版本启动"
    
    # 检查环境
    check_docker
    check_files "$URL_FILE"
    
    # 检查或构建镜像
    if [[ "$BUILD_IMAGE" == true ]] || ! check_image; then
        build_image
    fi
    
    # 运行房屋检查
    run_checker "$DELAY" "$URL_FILE"
    
    # 发送邮件（如果指定）
    if [[ "$SEND_EMAIL" == true ]] && [[ -n "$DEFAULT_EMAIL" ]]; then
        send_email "$DEFAULT_EMAIL"
    fi
    
    log "INFO" "所有任务完成"
}

# 捕获中断信号
trap 'log "WARN" "脚本被用户中断"; exit 130' INT

# 执行主函数
main "$@"