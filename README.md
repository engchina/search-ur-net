# UR-NET 房屋信息爬虫

这是一个用于爬取UR-NET（日本都市再生机构）房屋信息的Python爬虫工具。该工具专门设计用来处理JavaScript动态加载的内容，能够获取真实的空房数据。

## 功能特点

- ✅ **JavaScript渲染支持**: 使用Playwright处理动态加载的内容
- ✅ **API直接调用**: 发现并使用UR-NET的内部API接口
- ✅ **真实数据获取**: 能够获取到非零的空房数据
- ✅ **多种爬取方式**: 提供多个版本的爬虫以适应不同需求
- ✅ **详细调试信息**: 保存网络请求、API响应等调试数据

## 文件说明

### 主要爬虫文件

1. **`ur_net_scraper.py`** - 原始版本爬虫
   - 基础的HTML解析爬虫
   - 无法处理JavaScript动态内容
   - 获取的空房数据全为0

2. **`ur_net_scraper_enhanced.py`** - 增强版爬虫 ⭐
   - 使用Playwright处理JavaScript渲染
   - 增加了多种等待机制和触发方式
   - 能够获取到部分真实数据
   - 推荐使用此版本

3. **`ur_net_api_scraper.py`** - API发现版爬虫
   - 尝试发现和测试各种API端点
   - 用于API接口的探索和分析

4. **`ur_net_working_api_scraper.py`** - 工作API版爬虫
   - 基于发现的有效API端点
   - 直接调用UR-NET的内部API
   - 最高效的数据获取方式

### 输出文件

- **`ur_properties.csv`** - 基础版本输出的CSV文件
- **`ur_properties_enhanced.csv`** - 增强版本输出的CSV文件
- **`ur_properties_api.csv`** - API版本输出的CSV文件
- **`areas_list.json`** - 地区列表数据
- **`debug_*.json`** - 各种调试信息文件
- **`*.log`** - 运行日志文件

## 安装依赖

```bash
pip install -r requirements.txt
```

### 主要依赖

- `requests` - HTTP请求库
- `beautifulsoup4` - HTML解析库
- `playwright` - 浏览器自动化库
- `pandas` - 数据处理库
- `lxml` - XML/HTML解析器

### 安装Playwright浏览器

```bash
playwright install chromium
```

## 使用方法

### 方法1: 使用增强版爬虫（推荐）

```bash
python ur_net_scraper_enhanced.py
```

这个版本使用Playwright来处理JavaScript渲染，能够获取到真实的空房数据。

### 方法2: 使用API版爬虫

```bash
python ur_net_working_api_scraper.py
```

这个版本直接调用UR-NET的内部API，效率最高。

### 方法3: 使用基础版爬虫

```bash
python ur_net_scraper.py
```

基础版本，仅用于对比和学习目的。

## 输出数据格式

所有版本都会生成包含以下字段的CSV文件：

| 字段名 | 说明 | 示例 |
|--------|------|------|
| 所在区 | 物件所在的区域 | 千代田区 |
| 物件名 | 物件的名称 | 木場三丁目パークハイツ |
| 対象空室数 | 可用空房数量 | 5 |
| 家賃(共益費) | 租金（含共益费） | 85,000円～ |

## 技术实现

### JavaScript处理策略

1. **页面等待机制**
   - 等待DOM内容加载完成
   - 等待网络请求空闲
   - 等待特定元素出现

2. **数据触发方式**
   - 模拟用户滚动
   - 触发JavaScript事件
   - 调用页面内的API函数

3. **API发现方法**
   - 网络请求监控
   - JavaScript代码分析
   - API端点探测

### 发现的API端点

主要的工作API端点：
```
https://chintai.r6.ur-net.go.jp/chintai/api/bukken/search/list_init/
```

请求格式：
```
POST application/x-www-form-urlencoded
rent_low=&rent_high=&floorspace_low=&floorspace_high=&tdfk=13&vacancy=
```

## 调试功能

### 调试文件说明

- **`debug_page_enhanced.html`** - 保存的完整页面HTML
- **`debug_api_responses_enhanced.json`** - 捕获的API响应
- **`debug_screenshot.png`** - 页面截图
- **`network_log.json`** - 网络请求日志
- **`areas_list.json`** - 地区列表数据

### 启用调试模式

在代码中设置：
```python
DEBUG = True
SAVE_DEBUG_FILES = True
```

## 性能优化

### 建议的运行参数

1. **增强版爬虫**
   - 等待时间: 10-15秒
   - 重试次数: 3次
   - 并发数: 1（避免被封）

2. **API版爬虫**
   - 请求间隔: 1秒
   - 超时时间: 30秒
   - 重试次数: 3次

## 注意事项

### 使用限制

1. **请求频率**: 建议控制请求频率，避免对服务器造成压力
2. **数据使用**: 获取的数据仅供学习和研究使用
3. **法律合规**: 请遵守相关法律法规和网站使用条款

### 常见问题

**Q: 为什么空房数据全是0？**
A: 这是因为UR-NET网站使用JavaScript动态加载数据。请使用增强版爬虫（`ur_net_scraper_enhanced.py`）。

**Q: Playwright安装失败怎么办？**
A: 确保网络连接正常，然后运行 `playwright install chromium`。

**Q: API调用返回错误怎么办？**
A: 检查请求头和参数格式，确保使用正确的Content-Type。

## 更新日志

### v2.0 (2025-10-06)
- ✅ 添加了Playwright支持
- ✅ 实现了JavaScript渲染处理
- ✅ 发现并实现了API直接调用
- ✅ 能够获取真实的空房数据
- ✅ 添加了详细的调试功能

### v1.0 (初始版本)
- ✅ 基础的HTML解析功能
- ✅ CSV数据导出
- ❌ 无法处理JavaScript动态内容

## 贡献

欢迎提交Issue和Pull Request来改进这个项目。

## 许可证

本项目仅供学习和研究使用。请遵守相关法律法规和网站使用条款。

---

**免责声明**: 本工具仅用于技术学习和研究目的。使用者应当遵守相关法律法规和网站的使用条款。作者不对使用本工具产生的任何后果承担责任。