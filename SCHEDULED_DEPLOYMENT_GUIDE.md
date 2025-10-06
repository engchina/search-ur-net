# UR-NET房屋检查系统 - 定时任务部署指南

## 📋 概述

本指南提供了在 Red Hat Enterprise Linux Server 7.9 上使用 Docker 部署 UR-NET 房屋检查系统定时任务的完整步骤。系统将每 10 分钟自动执行一次房屋空置状态检查。

## 🎯 解决的问题

- **GLIBC 兼容性问题**: 通过 Docker 容器化解决 Red Hat 7.9 上的 `GLIBC` 和 `GLIBCXX` 版本不兼容问题
- **自动化执行**: 每 10 分钟自动检查房屋状态
- **日志管理**: 自动日志轮转和清理
- **监控告警**: 系统状态监控和错误告警

## 📁 文件结构

```
search-ur-net/
├── Dockerfile                          # Docker 镜像构建文件
├── docker-compose.yml                  # Docker Compose 配置
├── run_scheduled.sh                    # 定时执行脚本
├── setup_cron.sh                      # Cron 配置脚本
├── log_manager.sh                     # 日志管理脚本
├── SCHEDULED_DEPLOYMENT_GUIDE.md      # 本部署指南
├── requirements.txt                   # Python 依赖
├── ur_net_batch_property_checker.py   # 主程序
├── run_ur_net_check_and_email.sh     # 原始执行脚本
├── .env                               # 环境配置文件
├── logs/                              # 日志目录
│   └── scheduled_run_*.log
└── results/                           # 结果目录
    └── ur_net_results_*.json
```

## 🚀 快速部署

### 1. 环境准备

确保系统已安装 Docker：

```bash
# 检查 Docker 版本
docker --version

# 检查 Docker 服务状态
docker info

# 如果 Docker 未安装，请先安装
# sudo yum install -y docker
# sudo systemctl start docker
# sudo systemctl enable docker
```

### 2. 构建 Docker 镜像

```bash
# 进入项目目录
cd /path/to/search-ur-net

# 构建 Docker 镜像
docker build -t ur-net-checker .
```

### 3. 配置环境文件

确保 `.env` 文件包含必要的配置：

```bash
# 检查环境文件
cat .env

# 如果不存在，创建基本配置
echo "# UR-NET 配置" > .env
echo "DELAY=2.0" >> .env
echo "EMAIL_ENABLED=false" >> .env
```

### 4. 时区配置

#### 4.1 时区说明
本系统配置为在日本时间8:00-19:00期间执行，对应太平洋时间15:00-02:00（次日）。

```bash
# 查看时区配置信息
./timezone_helper.sh --schedule

# 测试时区转换
./timezone_helper.sh --test

# 查看当前时区
./timezone_helper.sh --current
```

#### 4.2 时间对照表
| 日本时间 | 太平洋时间 |
|---------|----------|
| 08:00   | 15:00 (前一天) |
| 12:00   | 19:00 (前一天) |
| 16:00   | 23:00 (前一天) |
| 19:00   | 02:00 |

### 5.1 使用一键安装脚本

```bash
# 安装定时任务
./quick_setup.sh --install

# 查看状态
./quick_setup.sh --status
```

### 5.2 手动安装

```bash
# 给脚本添加执行权限
chmod +x setup_cron.sh run_scheduled.sh log_manager.sh

# 安装定时任务（日本时间8:00-19:00，每10分钟执行一次）
./setup_cron.sh --install
```

### 6. 验证安装

```bash
# 检查定时任务状态
./setup_cron.sh --status

# 查看 cron 任务列表
./setup_cron.sh --list

# 检查系统状态
./log_manager.sh --status
```

## 📋 详细操作步骤

### 步骤 1: 系统环境检查

```bash
# 1. 检查操作系统版本
cat /etc/redhat-release

# 2. 检查 Docker 环境
docker --version
docker info

# 3. 检查磁盘空间
df -h

# 4. 检查 cron 服务
systemctl status crond
```

### 步骤 2: 项目配置

```bash
# 1. 进入项目目录
cd /root/workspace/search-ur-net

# 2. 检查项目文件
ls -la

# 3. 验证配置文件
cat .env
cat urls.txt  # 如果存在

# 4. 检查 Python 依赖
cat requirements.txt
```

### 步骤 3: Docker 镜像构建

```bash
# 1. 构建镜像
docker build -t ur-net-checker .

# 2. 验证镜像
docker images | grep ur-net-checker

# 3. 测试容器运行
docker run --rm ur-net-checker echo "测试成功"
```

### 步骤 4: 定时任务配置

```bash
# 1. 安装定时任务
./setup_cron.sh --install

# 2. 验证安装
crontab -l

# 3. 检查任务状态
./setup_cron.sh --status
```

### 步骤 5: 系统监控设置

```bash
# 1. 检查系统状态
./log_manager.sh --status

# 2. 设置日志清理
./log_manager.sh --cleanup

# 3. 检查磁盘空间
./log_manager.sh --check-disk
```

## 🔧 脚本使用说明

### setup_cron.sh - Cron 任务管理

```bash
# 安装定时任务
./setup_cron.sh --install

# 移除定时任务
./setup_cron.sh --remove

# 查看任务状态
./setup_cron.sh --status

# 列出所有任务
./setup_cron.sh --list
```

### run_scheduled.sh - 定时执行脚本

```bash
# 手动执行（测试用）
./run_scheduled.sh

# 带参数执行
./run_scheduled.sh -d 3.0 -f custom_urls.txt

# 查看帮助
./run_scheduled.sh --help
```

### log_manager.sh - 日志管理

```bash
# 查看系统状态
./log_manager.sh --status

# 清理旧文件
./log_manager.sh --cleanup

# 实时监控
./log_manager.sh --monitor

# 分析统计
./log_manager.sh --analyze

# 实时跟踪日志
./log_manager.sh --tail

# 检查各项状态
./log_manager.sh --check-disk
./log_manager.sh --check-cron
./log_manager.sh --check-docker
```

## 📊 监控和维护

### 日常监控

```bash
# 每日检查系统状态
./log_manager.sh --status

# 查看最近的执行日志
./log_manager.sh --logs

# 查看最近的结果文件
./log_manager.sh --results

# 分析执行统计
./log_manager.sh --analyze
```

### 定期维护

```bash
# 每周清理旧文件
./log_manager.sh --cleanup

# 每月检查磁盘空间
./log_manager.sh --check-disk

# 检查定时任务状态
./log_manager.sh --check-cron

# 检查 Docker 状态
./log_manager.sh --check-docker
```

### 故障排查

```bash
# 查看最新日志
tail -f logs/scheduled_run_$(date +%Y%m%d).log

# 检查 Docker 容器状态
docker ps -a

# 检查 cron 日志
tail -f /var/log/cron

# 手动执行测试
./run_scheduled.sh
```

## 🔍 日志文件说明

### 日志文件位置

- **定时任务日志**: `logs/scheduled_run_YYYYMMDD.log`
- **系统日志**: `/var/log/cron`
- **Docker 日志**: `docker logs <container_id>`

### 日志内容说明

```bash
# 正常执行日志示例
[2024-01-15 10:00:01][INFO] 开始执行定时任务
[2024-01-15 10:00:02][INFO] 检查 Docker 环境...
[2024-01-15 10:00:03][INFO] Docker 环境正常
[2024-01-15 10:00:04][INFO] 开始运行房屋检查...
[2024-01-15 10:05:30][INFO] 房屋检查完成
[2024-01-15 10:05:31][INFO] 结果已保存到: results/ur_net_results_20240115_100001.json
[2024-01-15 10:05:32][INFO] 定时任务执行完成
```

## ⚙️ 配置参数

### 环境变量配置 (.env)

```bash
# 执行延迟（秒）
DELAY=2.0

# 邮件功能开关
EMAIL_ENABLED=false

# 邮件配置（如果启用）
SMTP_SERVER=smtp.example.com
SMTP_PORT=587
EMAIL_USER=your_email@example.com
EMAIL_PASS=your_password
EMAIL_TO=recipient@example.com

# 结果目录
RESULTS_DIR=./results

# 日志级别
LOG_LEVEL=INFO
```

### Cron 任务配置

```bash
# 每10分钟执行一次
*/10 * * * * /path/to/run_scheduled.sh >/dev/null 2>&1

# 其他时间间隔示例：
# 每5分钟:  */5 * * * *
# 每15分钟: */15 * * * *
# 每30分钟: */30 * * * *
# 每小时:   0 * * * *
```

## 🚨 故障排查指南

### 常见问题及解决方案

#### 1. Docker 镜像构建失败

```bash
# 问题: 网络连接问题
# 解决: 检查网络连接，使用国内镜像源

# 问题: 权限不足
# 解决: 使用 sudo 或添加用户到 docker 组
sudo usermod -aG docker $USER
```

#### 2. 定时任务不执行

```bash
# 检查 cron 服务
systemctl status crond

# 检查 cron 任务
crontab -l

# 检查脚本权限
ls -la run_scheduled.sh

# 查看 cron 日志
tail -f /var/log/cron
```

#### 3. 日志文件过大

```bash
# 手动清理日志
./log_manager.sh --cleanup

# 强制清理所有文件
./log_manager.sh --force-cleanup

# 检查磁盘空间
./log_manager.sh --check-disk
```

#### 4. Docker 容器运行失败

```bash
# 检查容器日志
docker logs <container_id>

# 检查镜像
docker images

# 重新构建镜像
docker build -t ur-net-checker . --no-cache

# 测试容器
docker run --rm -it ur-net-checker /bin/bash
```

## 📈 性能优化

### 系统优化建议

1. **资源监控**
   ```bash
   # 监控 CPU 和内存使用
   top
   htop
   
   # 监控磁盘 I/O
   iotop
   
   # 监控网络
   nethogs
   ```

2. **Docker 优化**
   ```bash
   # 清理未使用的镜像
   docker image prune
   
   # 清理未使用的容器
   docker container prune
   
   # 清理未使用的网络
   docker network prune
   ```

3. **日志优化**
   ```bash
   # 设置日志轮转
   # 在 /etc/logrotate.d/ 创建配置文件
   
   # 压缩旧日志
   gzip logs/*.log
   ```

## 🔒 安全考虑

### 安全最佳实践

1. **文件权限**
   ```bash
   # 设置适当的文件权限
   chmod 750 *.sh
   chmod 640 .env
   chmod 755 logs results
   ```

2. **环境变量保护**
   ```bash
   # 不要在日志中记录敏感信息
   # 使用环境变量存储密码
   # 定期更换密码
   ```

3. **网络安全**
   ```bash
   # 限制 Docker 容器网络访问
   # 使用防火墙规则
   # 监控网络连接
   ```

## 📞 技术支持

### 获取帮助

1. **查看帮助信息**
   ```bash
   ./setup_cron.sh --help
   ./run_scheduled.sh --help
   ./log_manager.sh --help
   ```

2. **检查系统状态**
   ```bash
   ./log_manager.sh --status
   ./log_manager.sh --analyze
   ```

3. **收集诊断信息**
   ```bash
   # 系统信息
   uname -a
   cat /etc/redhat-release
   
   # Docker 信息
   docker version
   docker info
   
   # 项目状态
   ./log_manager.sh --status
   ```

## 📝 更新日志

- **v1.0** (2024-01-15): 初始版本，支持基本的定时任务功能
- 定时执行：每10分钟自动检查
- 日志管理：自动轮转和清理
- 监控告警：系统状态监控
- Docker 支持：解决 GLIBC 兼容性问题

---

**注意**: 本指南基于 Red Hat Enterprise Linux Server 7.9 环境编写，其他 Linux 发行版可能需要适当调整命令和配置。