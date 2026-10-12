# Legado iOS (开源阅读 iOS 版)

[![iOS](https://img.shields.io/badge/Platform-iOS%2015.0%2B-blue.svg)](https://developer.apple.com/ios/)
[![Swift](https://img.shields.io/badge/Swift-5.0%2B-orange.svg)](https://swift.org)
[![Xcode](https://img.shields.io/badge/Xcode-14.0%2B-blue.svg)](https://developer.apple.com/xcode/)
[![Release](https://img.shields.io/badge/Release-v0.2.1-green.svg)](https://github.com/SeitoMoyi/Legado-iOS/releases)
[![License](https://img.shields.io/badge/License-GPLv3-lightgrey.svg)](LICENSE)

> **Legado iOS** 是使用 **SwiftUI** 与 **Swift** 现代化技术栈构建的开源网络小说阅读器，高度兼容 Android 端 **Legado (开源阅读 3.0)** 书源生态、解析规则与 WebDAV 多端同步机制。

---

## ✨ v0.2.1 新增

本版把阅读页与搜索页补齐到 Android 的核心交互，详见 [FEATURE_GAP_ANALYSIS.md](FEATURE_GAP_ANALYSIS.md) 与实施记录 [plan.md](plan.md)。

- 🧭 **阅读页三级菜单**
  - 底部六键工具栏（目录 / 搜索 / 听书 / 净化 / 界面 / 更多）+ 顶栏溢出菜单。
  - **3×3 可自定义点击区域**，14 种动作，与 Android 同一张表；保存时强制保留一个「菜单」区，防止把自己锁死。
  - **音量键翻页**（含「朗读时音量键翻页」「按键长按翻页」）。
  - 翻页动画 4 档：覆盖 / 滑动 / 滚动 / 无动画（仿真暂降级为滑动）。
  - 屏幕常亮档位、隐藏状态栏、文字两端对齐、首行缩进 0–4 字符、正文与页眉页脚边距。
  - 「界面」与「更多设置」统一为同一张底部卡片（屏幕下半部，条目超出可滚动），全部跟随阅读主题配色。
- 💾 **阅读配置持久化修复**：字号 / 行距 / 主题此前**冷启动即丢失**，现已按 Android 同名键落盘（`readConfig`）。
- 🔖 **书签体系**：添加、编辑原文与备注、列表与搜索、跳转还原到**段内字符位置**、导出 JSON / Markdown。以「书名 + 作者」建索引，**换源后书签不丢**；键名兼容 Android `bookmark.json`。
- 🔄 **换源**：整书换源、本章换源、**自动换源**（正文缺失时后台补全）。章节位置按比例估算 + 相邻窗口 Jaccard 相似度 + 章节号三重映射。入口目前在**阅读页**，详情页入口列入下一步。
- 🧹 **替换净化**：规则增删改查、启停、排序、导入导出；正则 / 字面、作用于标题或正文、作用域与排除范围匹配语义对齐 Android 的 SQL `LIKE`；超时规则自动禁用；简繁转换（系统 `CFStringTransform`，零外部词典）；「起效的替换」列出本章命中规则。
- 🔊 **朗读控制面板**：上一段 / 下一段（朗读单位为**段落**，与 Android 一致）、按页朗读、语速 0–45 档与 `(pref+5)/10` 换算、跟随系统语速、音调、定时停止 0–180 分钟；支持后台播放与锁屏 / 耳机线控。
- 🔎 **搜索范围与历史**：全部书源 / 多分组（可多选）/ 单书源三态；**精准搜索**三桶排序（等值 → 包含 → 其余，各自按来源数降序）；跨源按「书名 + 作者」合并并统计 `origins`；搜索历史按使用时间排序、输入过滤、长按删除、一键清除，键名兼容 `searchHistory.json`；搜索可**停止 / 继续**。
- 🌐 **抓取层兼容性**：**字符集自动识别**（BOM → 声明 → HTTP 头 → `<meta>` 嗅探 → Foundation 统计 → 候选严格解码打分），GBK / Big5 / EUC-KR 站点不再乱码；`nextContentUrl` 正文续页与 `nextTocUrl` 目录续页；5xx 与网络抛错自动重试。
- 🗑 **移除 App 内亮度调节**：iOS 的系统控制中心更方便，应用内再做一条亮度条属重复功能。

### 🐛 本版修掉的历史 bug

| 位置 | 问题 |
|---|---|
| 设置页「清理阅读缓存」 | 只把提示语设成「缓存已成功清理」，**从不真正删除任何缓存文件** |
| 阅读页字号 / 行距 / 主题 | 没有写盘逻辑，每次冷启动回到默认值 |
| 「更多设置」/「朗读」面板 | `.frame(maxHeight:)` 加在了 `VStack { Spacer; panel }` 整体上并会居中，面板悬在屏幕中段而不是贴底 |
| 「净化」按钮 | 图标 `eraser.pen` **不是有效 SF Symbol**，iOS 15 上渲染为空白（全 App 符号名已跑一遍校验，另修 3 个无效名） |
| 听书暂停 | 状态完全等 `AVSpeechSynthesizer` 的 `didPause` 回调，而该回调不保证送达 → 按钮卡在「暂停」，再点只会重读同一段 |
| 「朗读」面板若干行标签 | 未指定颜色，继承系统 primary，深色模式 + 浅色阅读主题时白字印在米色底上 |

---

## 🌟 核心特性

- 📚 **全面兼容 Legado 3.0 书源生态**
  - 支持 CSS 选择器、JSONPath、XPath、正则表达式、JavaScript 动态脚本与模版语法的多重混合解析。
  - 支持从**本地 `.json` 文件**、网络链接或剪贴板一键导入与批量更新书源。
  - 内置书源预设：机翻机器人书源全源发现流，ESJ Zone 书源统一命名规范。
  - 支持内置 Web 浏览器交互式登录（适配复杂防爬或需要 Cookie 验证的书源，支持双域会话镜像）。
  - 📖 详细规范请参阅：[**书源制作与兼容性规范指南 (BOOKSOURCE_GUIDE.md)**](BOOKSOURCE_GUIDE.md)。

- 📑 **全新“分类”发现流**
  - **Level 1（快速换源）**：顶部胶囊栏单指轻点即切书源。
  - **Level 2（预设分类）**：横向标签滚动栏搭配矩阵分类抽屉，快速筛选来源、类型、分级与排序。
  - **Level 3（书籍信息流）**：标准书籍卡片流、自动下拉刷新、触底无限分页加载。

- 📖 **沉浸式全屏阅读器**
  - **无缝滚动阅读**：纵向连续滚动模式支持向下拉动无缝加载上一章，并在章节断点间丝滑阅读，不再重置回章节首页。
  - **多排版模式**：覆盖 / 滑动 / 滚动 / 无动画四档翻页动画，互相切换完美保留阅读位置。
  - **分卷连贯性**：彻底解决多卷小说因卷标导致的目录章节断连问题，各章节顺畅连贯翻阅。
  - **原生全屏呈现**：所有入口（书籍详情页、目录跳转等）均以原生全屏视图进入阅读器，去除侵入性卡片交互。
  - 内置默认白、复古羊皮纸、护眼草绿、夜间暗黑四套阅读主题，可调节字号、行距、字距、段距、缩进与正文边距，并全部持久化。
  - 支持离线正文缓存、单书一键清除缓存与全量清理。

- 🔍 **聚合搜索**
  - 多源并发、流式增量返回、触底自动翻页。
  - 搜索范围三态 + 精准搜索 + 跨源合并与来源数排序 + 搜索历史。

- 🔄 **WebDAV 多端无缝互通 (对齐 Android Legado)**
  - **标准 ZIP 备份**：完整支持 Android Legado 标准的 `backup${yyyy-MM-dd}-${deviceName}.zip` 打包格式，保留 100% 书籍元数据与精确阅读进度（`durChapterIndex`, `durChapterPos`, `durChapterTime`）。
  - **多设备支持**：可自定义配置“设备名称”（默认自动识别为 iPhone / Mac 等），轻松识别不同设备的备份档案。
  - **秒级极速备份**：彻底移除高耗时的串行网络循环，全量备份由原本的 30+ 秒降至 1 秒内完成。
  - **云端历史备份选择**：支持一键检索并列出 WebDAV 远程所有历史备份归档（展示备份日期、文件体积），可自由挑选 Android 或 iOS 备份包进行合并恢复。
  - 本地文件管理器亦可直接选取导入 Android 导出的 `backup*.zip`（配合 `bookProgress/` 进度目录）。
  - 书签、替换规则、搜索历史均采用 Android 同名 JSON 键，可被 Android 端直接读回。

- 🌓 **全景暗黑模式**
  - 原生支持跟随系统、浅色模式与深色模式，界面与组件即时切换。

---

## 🏗️ 架构设计

项目采用轻量模块化结构，将底层业务逻辑与上层 UI 视图彻底解耦：

```text
Legado-iOS/
├── Sources/
│   ├── LegadoCore/               # 独立核心框架（跨平台纯 Swift 逻辑）
│   │   ├── Engine/               # 规则引擎（JSEngine, RuleAnalyzer, RuleTokenizer）
│   │   ├── Models/               # 数据模型（Book, BookSource, ReadConfig, Bookmark, ReplaceRule, SearchScope, SearchKeyword, RuleModels）
│   │   ├── Service/              # 核心服务（NetworkClient, BookContentService, ContentProcessor, ChangeSourceService, ReaderStore, ReplaceRuleStore, BookSearchService, WebDAVService, EpubParser...）
│   │   └── Utils/                # 工具库（CharsetDetector, ChapterMatcher, ChineseConverter, TolerantJSON, CryptoUtils, JSONPath）
│   └── LegadoApp/                # SwiftUI 交互层与应用入口
│       ├── Services/             # 状态容器（BookStore, SearchViewModel, AudioBookService, VolumeKeyObserver）
│       ├── Theme/                # 阅读主题与排版配置（ReaderConfig）
│       └── Views/                # 界面视图
│           ├── BookshelfView.swift       # 书架页（倒序排列、未读红点、下拉刷新、原生全屏阅读）
│           ├── CategoryExploreView.swift # 分类页（三级快速切换、预设分类流）
│           ├── BookDetailView.swift      # 书籍详情页（目录、简介、缓存清理；换源入口目前在阅读页）
│           ├── Reader/                   # 全屏阅读器
│           │   ├── Panels/               # 界面 / 更多设置 / 朗读面板 + 共用卡片样式 + 点击区域
│           │   └── Sheets/               # 书签 / 换源 / 起效的替换 / 搜索浮层
│           ├── Search/                   # 搜索范围选择面板
│           ├── Settings/                 # 替换规则管理
│           ├── SourceManagerView.swift   # 书源管理（本地文件导入、长按管理）
│           └── SettingsView.swift        # 设置页（WebDAV 同步与历史备份选择、外观主题）
├── Tests/LegadoCoreTests/        # 单元测试套件（176 例）
├── tools/xcode_add_sources.py    # 把新增 Swift 文件登记进 Xcode 工程（无同步文件夹组）
└── Legado.xcodeproj              # Xcode 工程文件
```

> 新增文件后需运行 `python3 tools/xcode_add_sources.py $(python3 tools/xcode_add_sources.py --check)`，否则 `xcodebuild` 会静默忽略它（SwiftPM 靠目录通配，`swift build` 不受影响）。

---

## 🛠️ 编译与运行

### 系统要求
- macOS 12.0+
- Xcode 14.0+
- iOS 15.0+ 部署目标

### 本地编译
1. 克隆代码仓库：
   ```bash
   git clone git@github.com:SeitoMoyi/Legado-iOS.git
   cd Legado-iOS
   ```
2. 运行单元测试（使用 Swift Package Manager）：
   ```bash
   swift test
   ```
3. 打开并运行 Xcode 工程：
   ```bash
   open Legado.xcodeproj
   ```
   在 Xcode 中选择模拟器或真机目标设备，按 `Cmd + R` 即可运行。

---

## 📦 GitHub Actions 持续集成与发布

项目配置了自动化的 GitHub Actions 工作流：
- **推送主分支 `main`** 会自动触发构建与测试，编译打包未签名 `Legado-v*.ipa`，并**自动发布到 GitHub Releases** 供侧载安装。
- 版本号取自仓库根目录的 `VERSION` 文件，与 Xcode 工程的 `MARKETING_VERSION` 需一起更新。
- **支持的侧载方式 (Sideloading)**：
  - **TrollStore**（巨魔商店，推荐，免越狱免证书签名，永久有效）
  - **AltStore / SideStore**（个人免费证书签名）
  - **Sideloadly / 爱思助手**

---

## 📄 开源许可证

本项目基于 [GPLv3](LICENSE) 许可证开源。遵循与原版 Legado 相同的开源精神。
