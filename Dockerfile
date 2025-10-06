# 使用官方 Playwright Python 镜像作为基础镜像
FROM mcr.microsoft.com/playwright/python:v1.40.0-jammy

# 设置工作目录
WORKDIR /app

# 复制 requirements.txt 并安装 Python 依赖
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# 复制应用代码
COPY . .

# 创建结果目录
RUN mkdir -p results

# 设置环境变量
ENV PYTHONUNBUFFERED=1

# 默认命令
CMD ["python", "ur_net_batch_property_checker.py", "--help"]