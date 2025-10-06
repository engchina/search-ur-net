#!/bin/bash

# UR-NET房屋检查系统 - 一键部署脚本
# 作者: UR-NET检查系统
# 版本: 1.0
# 描述: 自动完成所有部署步骤

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
        "SUCCESS")
            echo -e "${PURPLE}[$timestamp][SUCCESS]${NC} $message"
            ;;
        "STEP")
            echo -e "${CYAN}[$timestamp][STEP]${NC} $message"
            ;;
    esac
}

# 显示横幅
show_banner() {
    echo -e "${PURPLE}"
    echo "========================================"
    echo "  UR-NET房屋检查系统 - 一键部署脚本"
    echo "========================================"
    echo -e "${NC}"
    echo "本脚本将自动完成以下步骤："
    echo "1. 检查系统环境"
    echo "2. 构建 Docker 镜像"
    echo "3. 配置定时任务（每10分钟执行一次）"
    echo "4. 验证部署结果"
    echo ""
}

# 显示帮助信息
show_help() {
    cat << EOF
UR-NET房屋检查系统 - 一键部署脚本

用法: $0 [选项]

选项:
    --install         执行完整安装
    --uninstall       卸载定时任务
    --status          查看系统状态
    --test            测试系统功能
    --rebuild         重新构建 Docker 镜像
    -h, --help        显示此帮助信息

示例:
    $0 --install      # 完整安装
    $0 --status       # 查看状态
    $0 --test         # 测试功能
    $0 --uninstall    # 卸载系统

EOF
}

# 检查系统环境
check_environment() {
    log "STEP" "步骤 1/4: 检查系统环境"
    
    # 检查操作系统
    if [[ -f /etc/redhat-release ]]; then
        local os_version=$(cat /etc/redhat-release)
        log "INFO" "操作系统: $os_version"
    else
        log "WARN" "未检测到 Red Hat 系统，继续执行..."
    fi
    
    # 检查 Docker
    if command -v docker &> /dev/null; then
        local docker_version=$(docker --version)
        log "INFO" "Docker 版本: $docker_version"
        
        if docker info &> /dev/null; then
            log "SUCCESS" "Docker 服务正常运行"
        else
            log "ERROR" "Docker 服务未运行，请启动 Docker 服务"
            log "INFO" "运行: sudo systemctl start docker"
            exit 1
        fi
    else
        log "ERROR" "Docker 未安装，请先安装 Docker"
        log "INFO" "安装命令: sudo yum install -y docker"
        exit 1
    fi
    
    # 检查 cron 服务
    if command -v crontab &> /dev/null; then
        log "SUCCESS" "Cron 服务可用"
    else
        log "ERROR" "Cron 服务不可用，请安装 cron"
        log "INFO" "安装命令: sudo yum install -y cronie"
        exit 1
    fi
    
    # 检查磁盘空间
    local disk_usage=$(df "$SCRIPT_DIR" | tail -1 | awk '{print $5}' | sed 's/%//')
    if [[ $disk_usage -gt 90 ]]; then
        log "ERROR" "磁盘空间不足，使用率: ${disk_usage}%"
        exit 1
    else
        log "SUCCESS" "磁盘空间充足，使用率: ${disk_usage}%"
    fi
    
    # 检查必要文件
    local required_files=(
        "Dockerfile"
        "requirements.txt"
        "ur_net_batch_property_checker.py"
        "run_scheduled.sh"
        "setup_cron.sh"
        "log_manager.sh"
    )
    
    for file in "${required_files[@]}"; do
        if [[ -f "$SCRIPT_DIR/$file" ]]; then
            log "INFO" "文件检查通过: $file"
        else
            log "ERROR" "缺少必要文件: $file"
            exit 1
        fi
    done
    
    log "SUCCESS" "系统环境检查完成"
    echo ""
}

# 构建 Docker 镜像
build_docker_image() {
    log "STEP" "步骤 2/4: 构建 Docker 镜像"
    
    # 检查是否已存在镜像
    if docker images | grep -q "ur-net-checker"; then
        log "INFO" "发现已存在的 Docker 镜像"
        read -p "是否重新构建镜像? (y/N): " -n 1 -r
        echo
        
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log "INFO" "跳过镜像构建"
            return 0
        fi
    fi
    
    log "INFO" "开始构建 Docker 镜像..."
    
    # 构建镜像
    if docker build -t ur-net-checker "$SCRIPT_DIR"; then
        log "SUCCESS" "Docker 镜像构建成功"
    else
        log "ERROR" "Docker 镜像构建失败"
        exit 1
    fi
    
    # 验证镜像
    if docker images | grep -q "ur-net-checker"; then
        local image_size=$(docker images ur-net-checker --format "table {{.Size}}" | tail -1)
        log "INFO" "镜像大小: $image_size"
        log "SUCCESS" "Docker 镜像验证通过"
    else
        log "ERROR" "Docker 镜像验证失败"
        exit 1
    fi
    
    echo ""
}

# 配置定时任务
setup_cron_job() {
    log "STEP" "步骤 3/4: 配置定时任务"
    
    # 确保脚本有执行权限
    chmod +x "$SCRIPT_DIR/run_scheduled.sh"
    chmod +x "$SCRIPT_DIR/setup_cron.sh"
    chmod +x "$SCRIPT_DIR/log_manager.sh"
    
    log "INFO" "脚本权限设置完成"
    
    # 安装定时任务
    if "$SCRIPT_DIR/setup_cron.sh" --install; then
        log "SUCCESS" "定时任务安装成功"
    else
        log "ERROR" "定时任务安装失败"
        exit 1
    fi
    
    # 验证定时任务
    if crontab -l | grep -q "run_scheduled.sh"; then
        log "SUCCESS" "定时任务验证通过"
        log "INFO" "任务将每10分钟执行一次"
    else
        log "ERROR" "定时任务验证失败"
        exit 1
    fi
    
    echo ""
}

# 验证部署结果
verify_deployment() {
    log "STEP" "步骤 4/4: 验证部署结果"
    
    # 创建必要目录
    mkdir -p "$SCRIPT_DIR/logs" "$SCRIPT_DIR/results"
    log "INFO" "目录创建完成"
    
    # 检查系统状态
    log "INFO" "系统状态检查:"
    "$SCRIPT_DIR/log_manager.sh" --status
    
    # 检查定时任务状态
    log "INFO" "定时任务状态检查:"
    "$SCRIPT_DIR/setup_cron.sh" --status
    
    # 检查 Docker 状态
    log "INFO" "Docker 状态检查:"
    "$SCRIPT_DIR/log_manager.sh" --check-docker
    
    log "SUCCESS" "部署验证完成"
    echo ""
}

# 执行完整安装
full_install() {
    show_banner
    
    log "INFO" "开始执行完整安装..."
    echo ""
    
    check_environment
    build_docker_image
    setup_cron_job
    verify_deployment
    
    log "SUCCESS" "🎉 UR-NET房屋检查系统部署完成！"
    echo ""
    echo -e "${CYAN}接下来的步骤:${NC}"
    echo "1. 系统将每10分钟自动执行一次房屋检查"
    echo "2. 日志文件保存在: $SCRIPT_DIR/logs/"
    echo "3. 结果文件保存在: $SCRIPT_DIR/results/"
    echo ""
    echo -e "${CYAN}常用命令:${NC}"
    echo "  查看状态: ./log_manager.sh --status"
    echo "  查看日志: ./log_manager.sh --logs"
    echo "  实时监控: ./log_manager.sh --monitor"
    echo "  清理文件: ./log_manager.sh --cleanup"
    echo ""
    echo -e "${CYAN}管理定时任务:${NC}"
    echo "  查看任务: ./setup_cron.sh --status"
    echo "  移除任务: ./setup_cron.sh --remove"
    echo ""
}

# 卸载系统
uninstall_system() {
    log "WARN" "即将卸载 UR-NET房屋检查系统..."
    read -p "确认卸载? (y/N): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log "INFO" "开始卸载系统..."
        
        # 移除定时任务
        if "$SCRIPT_DIR/setup_cron.sh" --remove; then
            log "SUCCESS" "定时任务已移除"
        fi
        
        # 询问是否删除 Docker 镜像
        read -p "是否删除 Docker 镜像? (y/N): " -n 1 -r
        echo
        
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            if docker rmi ur-net-checker 2>/dev/null; then
                log "SUCCESS" "Docker 镜像已删除"
            else
                log "WARN" "Docker 镜像删除失败或不存在"
            fi
        fi
        
        # 询问是否删除日志和结果文件
        read -p "是否删除所有日志和结果文件? (y/N): " -n 1 -r
        echo
        
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            rm -rf "$SCRIPT_DIR/logs" "$SCRIPT_DIR/results" 2>/dev/null || true
            log "SUCCESS" "日志和结果文件已删除"
        fi
        
        log "SUCCESS" "系统卸载完成"
    else
        log "INFO" "卸载操作已取消"
    fi
}

# 测试系统功能
test_system() {
    log "INFO" "开始测试系统功能..."
    
    # 测试 Docker 环境
    log "INFO" "测试 Docker 环境..."
    if docker run --rm ur-net-checker echo "Docker 测试成功"; then
        log "SUCCESS" "Docker 环境测试通过"
    else
        log "ERROR" "Docker 环境测试失败"
        return 1
    fi
    
    # 测试脚本执行
    log "INFO" "测试定时脚本..."
    if "$SCRIPT_DIR/run_scheduled.sh" --help &>/dev/null; then
        log "SUCCESS" "定时脚本测试通过"
    else
        log "ERROR" "定时脚本测试失败"
        return 1
    fi
    
    # 测试日志管理
    log "INFO" "测试日志管理..."
    if "$SCRIPT_DIR/log_manager.sh" --status &>/dev/null; then
        log "SUCCESS" "日志管理测试通过"
    else
        log "ERROR" "日志管理测试失败"
        return 1
    fi
    
    log "SUCCESS" "所有功能测试通过"
}

# 重新构建镜像
rebuild_image() {
    log "INFO" "重新构建 Docker 镜像..."
    
    # 删除旧镜像
    if docker images | grep -q "ur-net-checker"; then
        docker rmi ur-net-checker 2>/dev/null || true
        log "INFO" "旧镜像已删除"
    fi
    
    # 构建新镜像
    build_docker_image
}

# 显示系统状态
show_system_status() {
    log "INFO" "系统状态概览"
    echo "========================================"
    
    # Docker 状态
    echo -e "${CYAN}Docker 状态:${NC}"
    if command -v docker &> /dev/null && docker info &> /dev/null; then
        echo "  ✅ Docker 服务正常"
        if docker images | grep -q "ur-net-checker"; then
            echo "  ✅ Docker 镜像已构建"
        else
            echo "  ❌ Docker 镜像未构建"
        fi
    else
        echo "  ❌ Docker 服务异常"
    fi
    
    # 定时任务状态
    echo -e "${CYAN}定时任务状态:${NC}"
    if crontab -l 2>/dev/null | grep -q "run_scheduled.sh"; then
        echo "  ✅ 定时任务已配置"
    else
        echo "  ❌ 定时任务未配置"
    fi
    
    # 文件状态
    echo -e "${CYAN}文件状态:${NC}"
    if [[ -d "$SCRIPT_DIR/logs" ]]; then
        local log_count=$(ls -1 "$SCRIPT_DIR/logs"/*.log 2>/dev/null | wc -l)
        echo "  📁 日志文件: $log_count 个"
    else
        echo "  📁 日志文件: 0 个"
    fi
    
    if [[ -d "$SCRIPT_DIR/results" ]]; then
        local result_count=$(ls -1 "$SCRIPT_DIR/results"/*.json 2>/dev/null | wc -l)
        echo "  📁 结果文件: $result_count 个"
    else
        echo "  📁 结果文件: 0 个"
    fi
    
    echo "========================================"
}

# 主函数
main() {
    case "${1:-}" in
        --install)
            full_install
            ;;
        --uninstall)
            uninstall_system
            ;;
        --status)
            show_system_status
            ;;
        --test)
            test_system
            ;;
        --rebuild)
            rebuild_image
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