# MPVChapter - 自动视频章节提取工具

基于 Python 和 FFmpeg 的智能视频章节提取工具，通过检测音频中的静音段自动生成章节标记。

## 工作原理

程序使用**自适应阈值**技术：
1. 初步检测：根据 `min_silence` 参数检测所有可能的静音段
2. 智能分析：找到视频中最长的静音段
3. 自动调整：根据最长静音段乘以比例系数计算合适的静音检测阈值
4. 精确筛选：使用调整后的阈值重新筛选有效的章节切换点

这样可以让程序自动适应不同视频的静音特征，无需手动调整参数。

生成的章节文件格式：

```
00:00.000 Chapter 1
00:13.226 Chapter 2
00:21.603 Chapter 3
...
```

## 功能特点

- 极简使用：一个命令即可运行
- 零依赖：只使用 Python 标准库
- 配置简单：JSON 配置文件，易于修改
- 批量处理：支持单个文件或整个目录的批量处理
- 智能静音检测：使用 FFmpeg 的 silencedetect 滤镜
- 自适应阈值：自动分析视频静音特征，智能调整检测参数

## 快速开始

### 1. 安装 FFmpeg
```bash
# Windows: 下载并添加到 PATH
# macOS: brew install ffmpeg
# Linux: sudo apt install ffmpeg
```

### 2. 运行程序
```bash
python mpvchapter.py
```

## 配置文件

编辑 `config.json` 调整参数。

### 输入设置 (input)
```
- path: 输入目录路径，默认为当前目录 "."
  - ".": 当前目录
  - "./videos": 当前目录下的 video 子目录
  - "../videos": 上级目录下的 videos 子目录
- pattern: 文件匹配模式，支持通配符
  - "*.mp4": 只处理 MP4 文件
  - "*.{mp4,mkv,avi,mov,wmv,flv,webm}": 处理多种常见视频格式
  - "video*": 处理所有以 "video" 开头的文件
- batch_mode: 批量处理模式，true=处理所有匹配文件，false=只处理第一个文件
```

### 输出设置 (output)
```
- suffix: 输出文件后缀，默认为 ".chapter"
- encoding: 文件编码格式，默认为 "utf-8"
```

### 检测参数 (detection)
```
- noise_threshold_db: 静音检测阈值 (dB)
  - -30 (默认): 适合大多数视频
  - -35: 更严格的检测，适合对白为主的视频
  - -25: 更宽松的检测，适合背景音乐较多的视频
- min_silence: 最小静音时长 (秒)
  - 1.0 (默认): 适合一般视频
  - 0.8: 检测更短的静音，章节更密集
  - 1.5: 只检测较长的静音，章节更稀疏
- safety_ratio: 安全时间比例
  - 0.10 (默认): 章节时间 = 静音结束时间 - 10% × 静音时长
  - 0.05: 章节时间更接近静音结束
  - 0.20: 章节时间更早于静音结束
- min_gap: 章节间最小间隔 (秒)
  - 5.0 (默认): 适合一般视频
  - 3.0: 章节更密集
  - 8.0: 章节更稀疏
- skip_head: 跳过开头时间 (秒)，避免在视频开头生成章节
- skip_tail: 跳过结尾时间 (秒)，避免在视频结尾生成章节
```

### 自适应设置 (adaptive)
```
- enabled: 启用自适应静音检测阈值功能
  - 程序会先根据 min_silence 检测视频中所有的静音段
  - 使用四分位数方法分析静音时长分布，自动识别并过滤异常值
  - 计算Q1、Q3和IQR，定义正常范围：[Q1-1.5×IQR, Q3+1.5×IQR]
  - 使用正常范围内的最大静音时长作为参考，乘以 adaptive_ratio 作为候选阈值
  - 最终阈值 = max(min_silence, 正常范围最大值 × adaptive_ratio)
  - 这种方法能更科学地处理异常值，适应不同视频的静音特征
- adaptive_ratio: 自适应比例系数 (0.0-1.0)
  - 新阈值 = max(min_silence, 正常范围最大值 × adaptive_ratio)
  - 例如：正常范围最大值4秒，比例0.7，min_silence=1秒，则新阈值为2.8秒
  - 推荐值：0.6-0.8（0.7为默认值）
  - 0.0 = 使用 min_silence，1.0 = 使用正常范围最大值
```

### 章节设置 (chapters)
```
- prefix: 章节标题前缀，默认为 "Chapter"
- start_index: 起始章节索引，从1开始编号
```

### 日志设置 (logging)
```
- level: 日志级别，可选 DEBUG, INFO, WARNING, ERROR
- format: 日志格式
- show_progress: 显示处理进度信息
```

