# UR-NET 房屋空室检查系统

这是一个用于自动检查UR-NET（日本都市再生机构）房屋空室信息的Python自动化系统。该系统使用Playwright进行网页自动化，能够批量检查多个物件的空室状态，并在发现新的空室时自动发送邮件通知。

## 🌟 功能特点

- ✅ **批量检查**: 支持从CSV文件批量导入物件URL进行检查
- ✅ **智能检测**: 使用Playwright处理JavaScript动态加载的内容
- ✅ **变化监控**: 自动对比前次检查结果，仅在有新空室时发送通知
- ✅ **邮件通知**: 支持HTML格式的邮件通知，包含详细的检查结果
- ✅ **自动化运行**: 提供完整的Shell脚本支持定时任务
- ✅ **详细日志**: 完整的执行日志和错误处理机制
- ✅ **多种输出**: 支持JSON和CSV格式的结果输出

## 📁 项目结构

```
search-ur-net/
├── ur_net_batch_property_checker.py  # 主要的批量检查程序
├── ur_net_email_sender.py           # 邮件发送模块
├── run_ur_net_check_and_email.sh    # 自动化运行脚本
├── run.sh                           # 简化的运行脚本
├── urls.txt                         # 物件URL列表（CSV格式）
├── requirements.txt                 # Python依赖包
├── .env.example                     # 环境配置示例
├── .gitignore                       # Git忽略文件配置
└── results/                         # 检查结果输出目录
    ├── ur_net_results_*.json        # JSON格式检查结果
    └── execution_log_*.log          # 执行日志
```

## 🚀 快速开始

### 1. 环境准备

```bash
# 克隆项目
git clone <repository-url>
cd search-ur-net

# 安装Python依赖
pip install -r requirements.txt

# 安装Playwright浏览器
playwright install chromium
```

### 2. 配置设置

复制环境配置文件并填入实际配置：

```bash
cp .env.example .env
```

编辑 `.env` 文件，配置SMTP邮件服务器信息：

```bash
# SMTP 服务器配置
SMTP_SERVER=smtp.your-provider.com
SMTP_PORT=587

# SMTP 认证信息
SMTP_USER=your_username
SMTP_PASS=your_password

# 发件人地址
FROM_ADDR=no-reply@example.com

# 默认收件人地址
DEFAULT_TO_ADDR=your_email@example.com

# 密送地址（可选，多个地址用逗号分隔）
BCC_ADDR=bcc1@example.com,bcc2@example.com
```

### 3. 准备物件列表

编辑 `urls.txt` 文件，添加要检查的物件信息。文件格式为CSV：

```csv
No.,物件名,対象空室数,最寄駅,住所,電話番号,管理年数,URL
1,示例物件,0,JR山手线「新宿」站 徒步5分,东京都新宿区,03-1234-5678,10年,https://www.ur-net.go.jp/chintai/kanto/tokyo/example.html
```

### 4. 运行检查

#### 方法1: 使用自动化脚本（推荐）

```bash
# 使用默认参数运行
./run_ur_net_check_and_email.sh

# 指定参数运行
./run_ur_net_check_and_email.sh -e your_email@example.com -d 3.0 -f urls.txt
```

#### 方法2: 使用简化脚本

```bash
./run.sh
```

#### 方法3: 直接运行Python程序

```bash
# 仅运行检查程序
python3 ur_net_batch_property_checker.py -c urls.txt -d 2.0 -o json

# 发送邮件通知
python3 ur_net_email_sender.py -f results/ur_net_results_latest.json -t your_email@example.com
```

## 📋 命令行参数

### 批量检查程序 (ur_net_batch_property_checker.py)

```bash
python3 ur_net_batch_property_checker.py [选项]

选项:
  -c, --csv FILE        CSV文件路径 (默认: urls.txt)
  -d, --delay SECONDS   请求间延时秒数 (默认: 2.0)
  -o, --output FORMAT   输出格式 [json|csv] (默认: json)
  -p, --path PATH       输出文件路径
  --headless           无头模式运行 (默认: True)
  --max-retries N      最大重试次数 (默认: 5)
  --verbose            详细输出模式
```

### 邮件发送程序 (ur_net_email_sender.py)

```bash
python3 ur_net_email_sender.py [选项]

选项:
  -f, --file FILE       结果JSON文件路径
  -t, --to EMAIL        收件人邮箱地址
  -s, --subject TEXT    邮件主题
  --text-file FILE      纯文本结果文件路径
```

### 自动化脚本 (run_ur_net_check_and_email.sh)

```bash
./run_ur_net_check_and_email.sh [选项]

选项:
  -e, --email EMAIL     收件人邮箱地址
  -d, --delay SECONDS   检查延时秒数 (默认: 2.0)
  -f, --file FILE       CSV文件路径 (默认: urls.txt)
  -h, --help           显示帮助信息
```

## 📊 输出格式

### JSON格式结果

```json
{
  "timestamp": "2024-01-01 12:00:00",
  "summary": {
    "total_checked": 10,
    "total_vacant_rooms": 5,
    "properties_with_vacancies": 3
  },
  "results": [
    {
      "url": "https://www.ur-net.go.jp/chintai/kanto/tokyo/example.html",
      "property_name": "示例物件",
      "total_vacant": 2,
      "status": "success",
      "details": {
        "rooms": [
          {
            "type": "1DK",
            "rent": "80,000円",
            "floor": "3階"
          }
        ]
      }
    }
  ]
}
```

### 邮件通知格式

系统会发送HTML格式的邮件，包含：
- 检查时间和总结信息
- 有空室的物件详细信息
- 物件链接和联系方式
- 与上次检查的对比结果

## 🔧 高级配置

### 定时任务设置

使用crontab设置定时检查：

```bash
# 编辑crontab
crontab -e

# 添加定时任务（每天上午9点检查）
0 9 * * * cd /path/to/search-ur-net && ./run_ur_net_check_and_email.sh
```

### 自定义检查逻辑

可以修改 `ur_net_batch_property_checker.py` 中的检查逻辑：

- 调整页面等待时间
- 修改重试机制
- 自定义数据提取规则

### 邮件模板自定义

可以修改 `ur_net_email_sender.py` 中的HTML模板：

- 调整邮件样式
- 添加自定义字段
- 修改通知条件

## 🛠️ 依赖包说明

| 包名 | 版本 | 用途 |
|------|------|------|
| playwright | 1.40.0 | 网页自动化和JavaScript渲染 |
| beautifulsoup4 | 4.14.2 | HTML解析 |
| requests | 2.32.5 | HTTP请求 |
| pandas | 2.1.4 | 数据处理 |
| python-dotenv | 1.1.1 | 环境变量管理 |
| lxml | 6.0.2 | XML/HTML解析器 |

## 🚨 注意事项

### 使用限制

1. **请求频率**: 建议设置适当的延时（2-5秒），避免对服务器造成压力
2. **数据使用**: 获取的数据仅供个人学习和研究使用
3. **法律合规**: 请遵守相关法律法规和网站使用条款

### 常见问题

**Q: 检查结果显示所有空室数都是0？**
A: 这可能是因为网站结构发生变化或反爬虫机制。请检查网络连接并适当增加延时。

**Q: 邮件发送失败？**
A: 请检查SMTP配置是否正确，确认邮箱服务商的SMTP设置和认证信息。

**Q: Playwright安装失败？**
A: 确保网络连接正常，可以尝试使用代理或手动下载浏览器文件。

**Q: 程序运行中断？**
A: 检查日志文件了解具体错误原因，常见原因包括网络超时、页面结构变化等。

## 📈 性能优化建议

1. **延时设置**: 根据网络状况调整延时，通常2-5秒比较合适
2. **并发控制**: 避免同时运行多个检查实例
3. **资源清理**: 定期清理旧的结果文件和日志
4. **监控设置**: 建议配置系统监控确保定时任务正常运行

## 🔄 更新日志

### v3.0 (当前版本)
- ✅ 重构为批量检查系统
- ✅ 添加智能邮件通知功能
- ✅ 完善的Shell脚本自动化
- ✅ 详细的日志和错误处理
- ✅ 支持多种输出格式

### v2.0 (历史版本)
- ✅ 添加Playwright支持
- ✅ 实现JavaScript渲染处理
- ✅ 发现并实现API直接调用

### v1.0 (初始版本)
- ✅ 基础HTML解析功能
- ✅ CSV数据导出

## 📄 许可证

本项目仅供学习和研究使用。请遵守相关法律法规和网站使用条款。

## 🤝 贡献

欢迎提交Issue和Pull Request来改进这个项目。

---

**免责声明**: 本工具仅用于技术学习和研究目的。使用者应当遵守相关法律法规和网站的使用条款。作者不对使用本工具产生的任何后果承担责任。