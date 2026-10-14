# Legado iOS (开源阅读 iOS 版)

[![iOS](https://img.shields.io/badge/Platform-iOS%2015.0%2B-blue.svg)](https://developer.apple.com/ios/)
[![Swift](https://img.shields.io/badge/Swift-5.0%2B-orange.svg)](https://swift.org)
[![Xcode](https://img.shields.io/badge/Xcode-14.0%2B-blue.svg)](https://developer.apple.com/xcode/)
[![Release](https://img.shields.io/badge/Release-v0.2.5-green.svg)](https://github.com/SeitoMoyi/Legado-iOS/releases)
[![License](https://img.shields.io/badge/License-GPLv3-lightgrey.svg)](LICENSE)

> **Legado iOS** 是使用 **SwiftUI** 与 **Swift** 现代化技术栈构建的开源网络小说阅读器，高度兼容 Android 端 **Legado (开源阅读 3.0)** 书源生态、解析规则与 WebDAV 多端同步机制。

---

## ✨ v0.2.5 新增

本版重构阅读排版引擎架构，彻底统一滑动翻页与连续滚动模式，消除模式切换时的位置漂移与长标题截断问题：

- 📐 **统一排版引擎 (`ChapterTypography`) 与零漂移切换**：
  - **一套排版、不同处截断**：将滑动模式（Slide）与滚动模式（Scroll）收敛至同一套 CoreText 排版引擎，共用相同的行折行切片与字符范围映射，彻底杜绝两套排版计算偏差导致的行数累积漂移。
  - **长标题智能多行折行**：章节标题统一引入基于可用宽度的动态排版与折行，完美支持两行或三行超长标题展示，彻底解决滚动模式下单行截断、后半段内容消失的问题。
  - **时序竞争与页码还原修复**：消除面板切换翻页动画时触发的不必要重排（`onRepaginate`），每次滑动翻页即时更新阅读字符偏移量，确保滑动切滚动时精确对齐当前页第一行文字，滚动切滑动时精准定位至对应页码。
  - **排版换行符完整保留**：重构布局重建机制，持久保留原始章节内容（`rawContent`），彻底根除首章刷新后丢失 `\n` 换行符、段落粘连且仅由缩进空格分隔的 Bug。

---

## ✨ v0.2.4 新增

本版重构纵向连续滚动阅读体验、补齐 P0 核心阅读遗留交互，并针对 iOS 15 顶栏多按钮渲染进行底层兼容性修复：

- 📜 **纵向连续滚动排版重构**：
  - **边距与展现空间统一**：段落与图片采用与滑动翻页完全一致的边距、内衬与段距设置，视觉比例和谐自然。
  - **常驻通知栏/状态栏**：始终常驻系统顶栏（时间、电量、网络），字体图标跟随暗黑/浅色阅读主题自适应。
  - **零点击无缝双向长卷阅读**：彻底移除顶部章节切换按钮，进入滚动模式时自动向前与向后预拼装章节（`[上一章, 本章, 下一章]`）；上滑直接无缝衔接上一章末尾正文，触顶自动触发异步向上追加，实现完全贯通的长卷滚动阅读手感。
- 🎯 **P0 核心阅读遗留项全部补齐**：
  - **顶栏换源与刷新**：阅读器顶栏常驻「换源」与「刷新」双图标，一键触发整书换源与本章重载。
  - **章节编辑内容**：接通动作码 `ClickActionCode.editContent` 与正文菜单，新增 `EditContentSheet` 支持本章标题与正文自定义修改、即时生效落盘、一键重置及全量复制。
  - **WebDAV 进度双向同步**：接通动作码 `ClickActionCode.syncProgress` 与离线菜单，自动比较本地与远端时间戳，实现拉取最新进度覆盖与当前阅读进度回传。
  - **滚动朗读高亮与自动跟踪**：连续滚动模式下朗读段落实时动画高亮（柔和主色背景），并自动平滑滚动居中当前发音段落。
- 🛠 **修复 iOS 15 顶栏「更多」菜单按钮不显示**：在 iOS 15 上，由于 `NavigationView` 将 `ToolbarItemGroup(placement: .primaryAction)` 的语义限制为单个 Primary Action，导致书架页（`BookshelfView`）与订阅源列表（`RssViews`）右上角仅渲染首个按钮（搜索/收藏），二级菜单按钮（`⋯`）被系统丢弃。现统一收敛为单个 `ToolbarItem` 内嵌 `HStack` 规范结构，恢复书架多选批量管理、网格/列表切换、排序方式等全部二级菜单功能。
- 🛠 **修复替换规则页 iOS 15 顶栏按钮冲突**：在 `ReplaceRuleListView` 中合并并列的 `.primaryAction` 声明，确保「编辑」与「添加/导入/导出」菜单按钮在 iOS 15 上正常并存显示。

---

## ✨ v0.2.3 新增

这一版把 Android 侧的**工具链**补齐：书源/书架/规则/订阅/音频五个模块全部打通，并让书源与书架的展示与 Android 数据保持**双向一致**（改 App，不改书源）。实施拆解见 [plan.md](plan.md) Part 1-18，逐项以 [FEATURE_GAP_ANALYSIS.md](FEATURE_GAP_ANALYSIS.md) 为准。

- 🧩 **书源体系**：`EditSourceSheet` 升级为 **6-Tab 全字段编辑器**（基本/搜索/发现/详情/目录/正文 + 整源 JSON 粘贴导出），新增**四阶段实时调试台**（搜索→详情→目录→正文流式日志）；管理页支持名称/域名/`group:xx` 搜索、`全部/已启用/已禁用` 三态胶囊、多选批量启禁删导、5 并发**校验书源**。
- 🗂 **书源分类噪声只在显示层过滤**：Android 的 `CheckSourceService` 会把校验判定词（`搜索目录失效` 等）和第三方合集的 `good` 标记写进 `bookSourceGroup`，此前会被当成分类显示。现在这些 token 只在**渲染分组胶囊时**隐藏，`bookSourceGroup` / `bookSourceComment` / `respondTime` **原样保存**，WebDAV 导回 Android 时数据一字不差。另修正两点：每轮校验的 `失效` 判定与实测耗时不再被启动同步覆盖；`respondTime ≥ 180000`（Android 的失败罚时，如内置 ESJ 的 `185203 = 180000 + 5203`）不再被当作速度显示。
- 📚 **书架管理**：三列封面网格 / 列表切换、4 种排序（最近阅读/最近更新/书名/作者）、`⋯`→「选择」批量清缓存与移除；**分组体系**默认收敛为「全部 / 书源书籍 / 本地书籍」（旧默认组「养肥中 / 已完结」退役），支持自定义分组增删改与批量移入。
- 📖 **书籍详情与目录**：书籍信息编辑（书名/作者/封面/简介）、整书换源、置顶、拷贝书籍与目录 URL；目录自动定位当前章、正倒序切换、已缓存标识。
- ⚙️ **规则与互通**：`RuleAnalyzer` 支持 **XPath**（`//`、`[contains(@class,…)]`、`[last()]`、`/@href` 等）；WebDAV 备份扩到 **10 类**数据（新增 `txtTocRule`、`readRecord`、`rssSources`、`rssStar` 等）；`JSEngine` 接通 `book.getVariable / setVariable`；TXT 目录规则管理 + 一键重新切章。
- 🔊 **朗读与音频**：HttpTTS 自定义引擎、在线有声书独立播放页（黑胶动效/倍速/定时/快进 15s）、条漫全屏预览、章节区间离线下载、阅读记录自动计时统计、字典规则与阅读器「查字典」。
- 📰 **4-Tab 与订阅**：底部导航扩展为 书架 / 分类 / 订阅 / 设置，正式上线 **RSS 订阅**（订阅源管理、分类文章流、正文提取阅读、文章收藏）。
- 🔗 **平台集成**：`legado://` 与 `yuedu://` URL Scheme 一键导入书源、主屏快捷操作（搜索书籍 / 继续阅读）、**局域网 WiFi 传书**（`Network.framework` 纯原生 HTTP 服务，网页上传 TXT/EPUB 直接入库）。
- 🎨 **外观**：新增**水墨屏**主题（纯白底纯黑字，6 套主题）与阅读**字体选择器**（系统/楷体/宋体/圆体）。

---

## ✨ v0.2.2 新增（上一版）

这一版按使用反馈做了三件事：**删掉两个有害功能**、**把打开书从"必联网"改成"缓存优先"**、**修掉离线卡死**。实施记录见 [UPDATE_LOG.md](UPDATE_LOG.md) 的「v0.2.2」小节与「关键设计决策与 Android 偏离备忘」表。

- 🗑 **删除音量键翻页**：iOS 拦音量键只能借隐藏的 `MPVolumeView`，而它的 slider 一旦写入就**真的改系统音量** —— 实测每按一次音量被往下压一截直到 0。功能与 `volumeKeyPage` 等三个开关整体移除，改用系统手势与控制中心。
- 🔊 **朗读悬浮控制条**：朗读期间常驻屏幕底部的 播放 / 暂停 / 结束 三键，**不随菜单与面板收起而消失**（可见性绑播放状态）。
- 🔊 **从当前页首个字开始朗读**，不再从章节开头重读；跨章衔接时新章节从其首页开始。插图占位标记 `[image:…]` 不再被念出来。
- 📚 **打开书籍改为缓存优先（对齐 Android）**：目录（TOC）此前**每次进阅读器都强制联网抓取**，是"打开要加载一会"的主因，也是离线打不开的原因。现在先读本地目录缓存、立即渲染，超过 10 分钟才在后台静默重爬；抓到新目录才回写缓存。抓到目录后章节正文原本就有磁盘缓存，两者合起来使**已缓存的书可以离线打开**。
- 🧵 **追更**：读到倒数 3 章内自动后台刷新目录（Android `upToc` 的等价物）；目录有变化时用章节名相似度重定位，不会把读者甩回第一章；只有「纯追加」才保留按 index 存储的正文缓存，结构变化则清除，避免错位串章。
- ⏱ **超时与截断保护**：请求超时从无限制的 60s 收紧到 30s；目录续页增加总时长预算（120s）与页数上限双闸。**被截断的目录或正文一律不写缓存**，避免"半本书"被当成完整缓存长期复用。
- 🚪 **离线不再困住阅读器**：加载失败页新增「返回书架」；「重试」原来调用了一个在目录为空时直接 return 的函数（死按钮），现在会真正重走抓目录流程；失败视图也能点出菜单；错误提示补上了可操作的下一步。
- 🛟 **章节失败不再盖住整页**：屏幕上已有可读内容时，某一章获取失败只在底部提示一次并保留当前页（Android 是当页文本渲染，不阻断阅读）。
- ⚙️ **设置页**：删除「阅读器显示设置」块（阅读设置的唯一入口收敛到阅读页的「界面」/「更多设置」面板，避免两处各写一份而漂移）；板块顺序改为 书源管理 → 书架与存储 → 外观模式 → 数据与云备份 → 正文处理 → 关于。
- 🧪 **测试分层**：5 个访问真实书源的用例移到 `LiveSourceTests`，主机不可达时**自动 skip 而非 fail**；CI 发布门槛改为 `swift test --skip LiveSourceTests`（224 个用例，其中确定性 219 例全通过，联网冒烟 5 例）。

---

## ✨ v0.2.1 新增（上一版）

本版把阅读页与搜索页补齐到 Android 的核心交互，详见 [FEATURE_GAP_ANALYSIS.md](FEATURE_GAP_ANALYSIS.md) 与实施记录 [plan.md](plan.md)。

- 🧭 **阅读页三级菜单**
  - 底部六键工具栏（目录 / 搜索 / 听书 / 净化 / 界面 / 更多）+ 顶栏溢出菜单。
  - **3×3 可自定义点击区域**，14 种动作，与 Android 同一张表；保存时强制保留一个「菜单」区，防止把自己锁死。
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
  - 支持从**本地 `.json` 文件**、网络链接导入，或**粘贴整源 JSON 到剪贴板**导入；支持多选批量启用/禁用/导出，以及并发「校验书源」。
  - 内置书源预设：机翻机器人书源全源发现流，ESJ Zone 书源统一命名规范。
  - 支持内置 Web 浏览器交互式登录（适配复杂防爬或需要 Cookie 验证的书源，支持双域会话镜像）。
  - 📖 详细规范请参阅：[**书源制作与兼容性规范指南 (BOOKSOURCE_GUIDE.md)**](BOOKSOURCE_GUIDE.md)。

- 📑 **全新“分类”发现流**
  - **Level 1（快速换源）**：顶部胶囊栏单指轻点即切书源。
  - **Level 2（预设分类）**：横向标签滚动栏搭配矩阵分类抽屉，快速筛选来源、类型、分级与排序。
  - **Level 3（书籍信息流）**：标准书籍卡片流、自动下拉刷新、触底无限分页加载。

- 📖 **沉浸式全屏阅读器**
  - **无缝滚动阅读**：纵向连续滚动模式支持向下拉动无缝加载上一章，并在章节断点间丝滑阅读，不再重置回章节首页。
  - **多排版模式**：覆盖 / 滑动 / 仿真 / 滚动 / 无动画五档翻页动画（仿真降级为滑动），互相切换完美保留阅读位置。
  - **分卷连贯性**：彻底解决多卷小说因卷标导致的目录章节断连问题，各章节顺畅连贯翻阅。
  - **原生全屏呈现**：所有入口（书籍详情页、目录跳转等）均以原生全屏视图进入阅读器，去除侵入性卡片交互。
  - 内置默认白、复古羊皮纸、护眼草绿、夜间暗黑、水墨屏五套预设主题 + 自定义配色，可调节字号、行距、字距、段距、缩进与正文边距，并全部持久化。
  - 支持离线正文缓存、单书一键清除缓存与全量清理。

- 🔍 **聚合搜索**
  - 多源并发、流式增量返回、触底自动翻页。
  - 搜索范围三态 + 精准搜索 + 跨源合并与来源数排序 + 搜索历史。

- 🔄 **WebDAV 多端无缝互通 (对齐 Android Legado)**
  - **标准 ZIP 备份**：完整支持 Android Legado 标准的 `backup${yyyy-MM-dd}-${deviceName}.zip` 打包格式，保留书籍元数据与精确阅读进度（`durChapterIndex`, `durChapterPos`, `durChapterTime`），并覆盖 **10 类**数据（书架 / 书源 / 书签 / 替换规则 / 搜索历史 / 阅读样式 / TXT目录规则 / 阅读记录 / 订阅源 / 文章收藏）。
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
│   │   ├── Models/               # 数据模型（Book, BookSource, ReadConfig, Bookmark, ReplaceRule, SearchScope, SearchKeyword, RuleModels, RssModels）
│   │   ├── Service/              # 核心服务（NetworkClient, BookContentService, ContentProcessor, ChangeSourceService, ReaderStore, ReplaceRuleStore, BookSearchService, BookExploreService, RssService, TocCache, LocalWebServer, LaunchIntent, WebDAVService, EpubParser...）
│   │   └── Utils/                # 工具库（CharsetDetector, ChapterMatcher, ChineseConverter, TolerantJSON, CryptoUtils, JSONPath）
│   └── LegadoApp/                # SwiftUI 交互层与应用入口
│       ├── LegadoApp.swift       # @main 入口 + AppDelegate/SceneDelegate（快捷操作）+ MainTabView（书架/分类/订阅/设置 4 tab）+ legado:// URL 处理
│       ├── Services/             # 状态容器（BookStore, SearchViewModel, AudioBookService, LaunchRouter）
│       ├── Theme/                # 阅读主题与排版配置（ReaderConfig）
│       └── Views/                # 界面视图
│           ├── BookshelfView.swift       # 书架页（分组胶囊、三列网格/列表、4 种排序、批量管理）
│           ├── CategoryExploreView.swift # 分类页（三级快速切换、预设分类流）
│           ├── BookDetailView.swift      # 书籍详情页（目录、简介、换源、信息编辑、变量、缓存清理）
│           ├── RssViews.swift            # 订阅模块（订阅源/文章流/正文阅读/收藏夹/源编辑）
│           ├── AudioPlayView.swift       # 在线有声书独立播放页
│           ├── SourceManagerView.swift   # 书源管理（搜索/三态胶囊/多选批量/并发校验/登录）
│           ├── SourceDetailView.swift    # 书源详情页（登录/变量/信息）
│           ├── SourceWebLoginView.swift  # 书源 WebView 登录
│           ├── EditSourceSheet.swift     # 6-Tab 全字段书源编辑器 + 四阶段调试台
│           ├── SearchBookView.swift      # 搜索页（多源并发、书架匹配、历史）
│           ├── WebDAVSyncView.swift      # WebDAV 同步 + 本地备份包导出/导入
│           ├── Reader/                   # 全屏阅读器
│           │   ├── ReaderView.swift      # 阅读画布 / 顶栏 / 底栏 / 手势 / 缓存下载
│           │   ├── Panels/               # 界面 / 更多设置 / 朗读 / 悬浮朗读条 + 共用卡片 + 点击区域
│           │   └── Sheets/               # 书签 / 换源 / 起效的替换
│           ├── Search/                   # 搜索范围选择面板
│           ├── Settings/                 # 替换规则管理
│           └── SettingsView.swift        # 设置页（书源/书架与存储/外观/云备份与局域网/正文处理/关于）+ TXT目录/字典/HttpTTS/所有书签/阅读记录
├── Tests/LegadoCoreTests/        # 单元测试套件（224 例，含 5 例联网冒烟）
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
   swift test --skip LiveSourceTests   # 只跑确定性单测，不依赖外网
   swift test                          # 再加上打真实书源的冒烟用例
   ```
   `LiveSourceTests` 会访问 `m.suixkan.com`、机翻机器人、`n.novelia.cc` 等真实站点，用来验证规则引擎对活站点的解析；目标站点不可达时它们**自动 skip 而不是 fail**，CI 发布门槛也不把它们算在内。
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
