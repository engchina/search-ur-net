# UR-NET 房屋空室检查系统 - Docker 解决方案

## 问题背景

在 Red Hat Enterprise Linux 7.9 等较旧的系统上，Playwright 需要较新的 GLIBC 和 GLIBCXX 版本，会出现以下错误：

```
GLIBC_2.27' not found
GLIBCXX_3.4.20' not found
CXXABI_1.3.9' not found
```

## Docker 解决方案

使用 Docker 容器运行应用，容器内包含所有必要的依赖，完全解决兼容性问题。

## 快速开始

### 1. 检查 Docker 环境

确保 Docker 已安装并运行：

```bash
docker --version
docker info
```

### 2. 使用 Docker 运行

#### 方法一：使用 docker-compose（推荐）

```bash
# 构建并运行
docker-compose up --build

# 后台运行
docker-compose up -d --build

# 查看日志
docker-compose logs -f
```

#### 方法二：使用自定义脚本

```bash
# 首次运行（自动构建镜像）
./run_docker.sh

# 指定参数运行
./run_docker.sh -d 3.0 -f urls.txt

# 运行并发送邮件
./run_docker.sh -e your_email@example.com

# 重新构建镜像
./run_docker.sh -b
```

#### 方法三：直接使用 Docker 命令

```bash
# 构建镜像
docker build -t ur-net-checker .

# 运行检查
docker run --rm \
  -v $(pwd)/results:/app/results \
  -v $(pwd)/urls.txt:/app/urls.txt:ro \
  -v $(pwd)/.env:/app/.env:ro \
  ur-net-checker \
  python ur_net_batch_property_checker.py -f urls.txt -d 2.0
```

## 文件说明

### 新增文件

- `Dockerfile` - Docker 镜像构建文件
- `docker-compose.yml` - Docker Compose 配置文件
- `run_docker.sh` - Docker 运行脚本
- `DOCKER_README.md` - 本说明文档

### 目录挂载

- `./results` → `/app/results` - 结果输出目录
- `./urls.txt` → `/app/urls.txt` - URL 输入文件
- `./.env` → `/app/.env` - 环境配置文件

## 使用示例

### 基本检查

```bash
# 使用默认设置
./run_docker.sh

# 自定义延时
./run_docker.sh -d 5.0

# 使用不同的 URL 文件
./run_docker.sh -f my_urls.txt
```

### 完整流程（检查 + 邮件）

```bash
# 运行检查并发送邮件
./run_docker.sh -e recipient@example.com

# 自定义所有参数
./run_docker.sh -d 3.0 -f custom_urls.txt -e admin@company.com
```

### 开发和调试

```bash
# 重新构建镜像
./run_docker.sh -b

# 进入容器调试
docker run -it --rm \
  -v $(pwd):/app \
  ur-net-checker \
  /bin/bash
```

## 优势

1. **兼容性解决** - 完全解决 GLIBC 版本问题
2. **环境隔离** - 不影响主机系统
3. **易于部署** - 一次构建，到处运行
4. **资源控制** - 可限制内存和 CPU 使用
5. **日志管理** - 统一的日志输出

## 故障排除

### Docker 权限问题

```bash
# 将用户添加到 docker 组
sudo usermod -aG docker $USER
# 重新登录或执行
newgrp docker
```

### 镜像构建失败

```bash
# 清理 Docker 缓存
docker system prune -f

# 重新构建
./run_docker.sh -b
```

### 结果文件权限问题

```bash
# 修改结果目录权限
chmod 755 results/
```

## 性能优化

### 资源限制

在 `docker-compose.yml` 中已配置：

```yaml
deploy:
  resources:
    limits:
      memory: 2G
    reservations:
      memory: 512M
```

### 网络优化

如需要特殊网络配置，可在 `docker-compose.yml` 中启用：

```yaml
network_mode: host
```

## 注意事项

1. 首次运行需要下载基础镜像和安装依赖，可能需要较长时间
2. 确保 `results` 目录有写入权限
3. 邮件功能需要正确配置 `.env` 文件
4. 容器内时间可能与主机不同，注意时间戳

## 技术细节

- **基础镜像**: `python:3.12-slim`
- **浏览器**: Chromium（通过 Playwright 安装）
- **显示**: Xvfb 虚拟显示器
- **Python 版本**: 3.12
- **依赖管理**: pip + requirements.txt