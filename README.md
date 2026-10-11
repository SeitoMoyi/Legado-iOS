# Legado iOS (开源阅读 iOS 版)

[![iOS](https://img.shields.io/badge/Platform-iOS%2015.0%2B-blue.svg)](https://developer.apple.com/ios/)
[![Swift](https://img.shields.io/badge/Swift-5.0%2B-orange.svg)](https://swift.org)
[![Xcode](https://img.shields.io/badge/Xcode-14.0%2B-blue.svg)](https://developer.apple.com/xcode/)
[![Release](https://img.shields.io/badge/Release-v0.1.0--preview-green.svg)](https://github.com/SeitoMoyi/Legado-iOS/releases)
[![License](https://img.shields.io/badge/License-GPLv3-lightgrey.svg)](LICENSE)

> **Legado iOS** 是使用 **SwiftUI** 与 **Swift** 现代化技术栈构建的开源网络小说阅读器，高度兼容 Android 端 **Legado (开源阅读 3.0)** 书源生态、解析规则与 WebDAV 多端同步机制。

---

## 🌟 核心特性

- 📚 **全面兼容 Legado 3.0 书源规则**
  - 支持 CSS 选择器、JSONPath、XPath、正则表达式、JavaScript 动态脚本与模版语法的多重混合解析。
  - 支持从**本地 `.json` 文件**、网络链接或剪贴板一键导入与批量更新书源。
  - 支持内置 Web 浏览器交互式登录（适配复杂防爬或需要 Cookie 验证的书源，支持双域会话镜像）。
  - 📖 详细规范请参阅：[**书源制作与兼容性规范指南 (BOOKSOURCE_GUIDE.md)**](BOOKSOURCE_GUIDE.md)。

- 📑 **全新“分类”发现流**
  - **Level 1（快速换源）**：顶部胶囊栏单指轻点即切书源。
  - **Level 2（预设分类）**：横向标签滚动栏搭配矩阵分类抽屉，快速筛选来源、类型、分级与排序。
  - **Level 3（书籍信息流）**：标准书籍卡片流、自动下拉刷新、触底无限分页加载。

- 📖 **沉浸式全屏阅读器**
  - 支持覆盖翻页、左右平滑翻页与纵向连续滚动三种排版模式。
  - 内置羊皮纸、柔光暗调、纯黑夜间、护眼草绿等专属阅读主题，随心调节字号、行距与内边距。
  - 支持点击屏幕中央呼出控制栏、快速查看全书目录与章节滑块精细跳转。
  - 支持离线正文缓存与单书一键清除缓存。

- 🔄 **WebDAV 多端无缝互通**
  - 完美识别并兼容 Android 端 Legado 的 WebDAV 备份格式。
  - 直接支持导入 Android 导出的 `backup*.zip` 以及 `bookProgress/` 进度快照目录，保留已读进度与阅读章节。
  - 支持配置 WebDAV 服务器自动双向备份与云端还原，或在本地文件管理器中单机导入备份包。

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
│   │   ├── Models/               # 数据模型（Book, BookSource, RuleModels）
│   │   ├── Service/              # 核心服务（NetworkClient, BookSearchService, WebDAVService, EpubParser...）
│   │   └── Utils/                # 工具库（CryptoUtils, JSONPath）
│   └── LegadoApp/                # SwiftUI 交互层与应用入口
│       ├── Services/             # 状态容器（BookStore, SearchViewModel, AudioBookService）
│       ├── Theme/                # 阅读主题与排版配置（ReaderConfig）
│       └── Views/                # 界面视图
│           ├── BookshelfView.swift       # 书架页（倒序排列、未读红点、下拉刷新、全屏阅读）
│           ├── CategoryExploreView.swift # 分类页（三级快速切换、预设分类流）
│           ├── BookDetailView.swift      # 书籍详情页（目录、简介、换源、缓存清理）
│           ├── Reader/                   # 全屏阅读器视图
│           ├── SourceManagerView.swift   # 书源管理（本地文件导入、长按管理）
│           └── SettingsView.swift        # 设置页（WebDAV 同步、外观主题、恢复预装）
├── Tests/                        # 单元测试套件（覆盖率高，持续集成）
└── Legado.xcodeproj              # Xcode 工程文件
```

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

## 📦 GitHub Actions 持续集成与预发布

项目配置了自动化的 GitHub Actions 工作流：
- **推送 Tag**（例如 `v0.1.0`）会自动触发构建，打包未签名 IPA，并自动创建 GitHub Pre-Release 发布产物供侧载（Sideloading，如 AltStore / TrollStore / SideStore）测试。

---

## 📄 开源许可证

本项目基于 [GPLv3](LICENSE) 许可证开源。遵循与原版 Legado 相同的开源精神。
