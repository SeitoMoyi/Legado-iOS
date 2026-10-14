# Legado iOS 版本更新日志与实施记录 (Version Update Log)

本文档记录 Legado iOS 各阶段版本的演进历史、实施细节、设计决策及与 Android 版本的有意偏离说明。功能差距总表参见 [FEATURE_GAP_ANALYSIS.md](FEATURE_GAP_ANALYSIS.md)。

---

## 目录
- [版本总览](#版本总览)
- [v0.2.3.1（iOS 15 顶栏兼容性修复）](#v0231ios-15-顶栏兼容性修复)
- [v0.2.3（书源 / 书架 / 规则工具链补齐，订阅与音频模块落地）](#v023书源--书架--规则工具链补齐订阅与音频模块落地)
- [v0.2.2（缓存与离线可用性）](#v022缓存与离线可用性)
- [v0.2.1（批次 P0：核心阅读与搜索闭环）](#v021批次-p0核心阅读与搜索闭环)
- [关键设计决策与 Android 偏离备忘](#关键设计决策与-android-偏离备忘)
- [后续版本规划（P2 / P3）](#后续版本规划p2--p3)

---

## 版本总览

| 版本 | 定位 | 主要更新内容 |
|---|---|---|
| **v0.2.3.1** | iOS 15 兼容性与顶栏交互修复 | 修复 iOS 15 下书架页右上角「更多 (⋯)」菜单按钮不显示的问题；修复订阅源列表与净化规则页在 iOS 15 下顶栏多按钮被系统丢弃的问题；统一收敛为 ToolbarItem + HStack 原语 |
| **v0.2.3** | 书源 / 书架 / 规则工具链补齐，订阅与音频模块落地，Android 数据互通 | XPath 规则引擎（`RuleTokenizer` + `RuleAnalyzer`）、WebDAV 10 类数据完整备份恢复、JS 变量持久化、6-Tab 全字段书源编辑器与四阶段调试台、书源管理搜索/三态胶囊/多选批量/并发校验、书架三列网格与 4 种排序与批量管理、书架分组体系、书籍信息编辑与整书换源、目录自动定位/正倒序/缓存标记、TXT 目录规则、阅读记录统计、字典规则与阅读查词、HttpTTS 与在线有声书播放器、条漫全屏预览、章节区间离线下载、全部书签汇总、本地备份包导出/导入、4-Tab 根架构（书架/分类/订阅/设置）与 RSS 订阅基础闭环、URL Scheme (`legado://` / `yuedu://`) 导入、主屏快捷操作、局域网 WiFi 传书 |
| **v0.2.2** | 缓存与离线可用性 | 目录缓存优先（TOC Cache）与 10 分钟静默刷新、离线失败态解死锁、续页总时长预算与截断保护、纯追加安全阀（`TocCache.isAppendOnly`）、朗读悬浮控制条 (`ReadAloudFloatingBar`)、听书状态自持、阅读面板归一 (`ReaderPanelChrome`)、设置页冗余项收敛、主动移除亮度调节与音量键翻页 |
| **v0.2.1** | P0 核心阅读闭环 | 阅读页三级菜单与更多设置面板、配置持久化 (`ReaderStore`)、书签体系、整书/单章换源 (`ChapterMatcher`)、替换净化管线 (`ContentProcessor`)、朗读面板与后台音频、搜索历史与搜索范围、字符集自动嗅探与目录/正文续页 |
| **v0.2.0** | 初始移植基线 | 基础书架、EPUB/TXT 阅读器、书源解析骨架、WebDAV 同步基础功能 |

---

## v0.2.3.1（iOS 15 顶栏兼容性修复）

### 问题背景与根因
在 iOS 15 设备与模拟器上，书架页（`BookshelfView`）顶栏右侧仅能看到「搜索」放大镜图标，原有的「更多 (⋯)」菜单按钮完全消失，导致无法进入批量管理多选、切换列表/三列网格视图、切换排序以及分组管理。

**根因分析**：
1. **SwiftUI 语义映射差异**：在 iOS 15 的 `NavigationView` 架构下，`ToolbarItemPlacement.primaryAction` 在底层被 UIKit 映射为单个 `navigationItem.rightBarButtonItem`。当把多个控件放在 `ToolbarItemGroup(placement: .primaryAction)` 中时，iOS 15 的 SwiftUI 导航桥接逻辑仅提取首个元素（搜索按钮）进行挂载，随后的 `Menu` 被系统静默丢弃。在 iOS 16+ 中，由于引入了 `NavigationStack` 与 `UIBarButtonItemGroup`，该语法才能被自动转换为组。
2. **多视图一致性规范**：项目中 `BookDetailView`、`EditSourceSheet`、`SettingsView` 等页面均已采用 `ToolbarItem(placement: .primaryAction) { HStack(spacing: 12) { ... } }` 模式将多个按钮包裹为单一自定义视图避免被截断；而 `BookshelfView`、`RssViews` 和 `ReplaceRuleListView` 此前未对齐该规范。

### 修复内容
| 文件 | 变更 | 说明 |
|---|---|---|
| `BookshelfView.swift` | `ToolbarItemGroup` → `ToolbarItem` + `HStack(spacing: 12)` | 恢复 iOS 15 下书架页「搜索」与「更多 (⋯)」双按钮常驻并存显示 |
| `RssViews.swift` | `ToolbarItemGroup` → `ToolbarItem` + `HStack(spacing: 12)` | 恢复 iOS 15 下订阅源列表页「收藏」与「新建/导入/导出 (⋯)」双按钮显示 |
| `ReplaceRuleListView.swift` | 合并双 `ToolbarItem(.primaryAction)` 为单个 `ToolbarItem` + `HStack(spacing: 12)` | 消除 iOS 15 下「编辑」按钮与「添加/导入/导出 (⋯)」菜单按钮的冲突 |

---

## v0.2.3（书源 / 书架 / 规则工具链补齐，订阅与音频模块落地）

实施拆解见 [plan.md](plan.md) Part 1-18,功能差距以 [FEATURE_GAP_ANALYSIS.md](FEATURE_GAP_ANALYSIS.md) 为准。

### 1. 书源体系（编辑 / 调试 / 管理 / 校验）

| 模块 | 改进内容 | 说明 |
|---|---|---|
| **6-Tab 书源编辑器与调试台** | `EditSourceSheet` 全字段化 + `SourceDebugSheet` 四阶段调试 | 覆盖基本/搜索/发现/详情/目录/正文全部规则字段与整源 JSON 粘贴导出；内置「搜索→详情→目录→正文」四阶段实时流式调试台 |
| **书源管理升级** | 搜索 + 三态分组胶囊 + 二级菜单「选择」多选批量 + 并发校验 | 支持名称/域名/`group:xx` 搜索；顶部「全部 / 已启用 / 已禁用」三态胶囊（不引入 Android 的分组子菜单）；右上角 `⋯` 二级菜单「选择」进入多选（全选/反选/批量启禁/删除/导出 JSON）；5 并发搜索校验写入 `失效` 判定与实测耗时 |
| **书源分类噪声只在显示层过滤** | `BookSource.displayGroup` | Android 的 `CheckSourceService` 会把校验判定词（`搜索目录失效` 等 11 个）以及第三方合集用的 `good` 标记写进 `bookSourceGroup`。这些 token 只在**渲染时**隐藏，书源的 `bookSourceGroup` / `bookSourceComment` / `respondTime` **原样保留**，WebDAV 导出回 Android 时数据完全一致 |
| **校验判定与测量耗时持久化** | `BookStore.loadBundledSources` | 该同步每次启动都会用内置包重建书源；`失效` 判定与 `respondTime` 只存在于设备侧，此前会被覆盖，导致红色「失效」标记永远留不住。现改为在内置包分类原文之上重新应用设备自己的判定 |
| **响应耗时仅在有效测量值时展示** | `BookSource.isMeasuredRespondTime` | Android 的 `respondTime` 是整轮校验耗时；校验失败时写入 `CheckSource.timeout + 实际耗时`（≥ 180000，如内置 ESJ 的 `185203` = `180000 + 5203`），属失败标记而非耗时。UI 只在 `0 < ms < 180000` 时渲染 `ms`，避免把失败罚时当成速度显示 |

### 2. 书架与书籍详情

| 模块 | 改进内容 | 说明 |
|---|---|---|
| **书架网格/排序/多选** | `BookshelfView` 升级视图切换、4 种排序与批量管理 | 支持列表与三列封面网格切换；支持按最近阅读/最近更新/书名/作者排序；右上角 `⋯` 二级菜单「选择」支持全选、反选、批量清理缓存、批量移除 |
| **书架分组体系** | `BookGroupStore` + `BookGroupManageSheet` | 顶栏横向分组胶囊切换：默认「全部 / 书源书籍 / 本地书籍」（书源书籍＝非本地导入，本地书籍＝TXT/EPUB/file 导入），支持自定义分组增删改与多选批量移入；旧版默认组「养肥中 / 已完结」在 v2 key 迁移中退役 |
| **书籍详情编辑与换源** | `BookDetailView` 接入 `BookInfoEditSheet`、`ChangeSourceSheet`、置顶与 URL 拷贝 | 支持自定义修改书名、作者、封面 URL、简介；支持整书换源、置顶书籍、拷贝书籍与目录 URL |
| **目录列表增强** | `BookDetailView` 章节列表 | 打开目录自动滚动居中当前阅读章节（`scrollTo(anchor: .center)`）；支持正序/倒序一键切换；已离线缓存章节显示「已缓存」标识 |

### 3. 规则引擎与数据互通

| 模块 | 改进内容 | 说明 |
|---|---|---|
| **XPath 规则引擎** | `RuleTokenizer` + `RuleAnalyzer` 完整支持 XPath | 支持 `//`、`/`、`|` 并集、`[@attr='val']`、`[contains(@class, ...)]`、`[N]`、`[last()]`、`/text()`、`/@href` 与 `@XPath:` 前缀 |
| **WebDAV 10 类备份互通** | `WebDAVService` 打包与恢复范围 | 覆盖 `bookshelf`、`bookSource`、`bookmark`、`replaceRule`、`searchHistory`、`readConfig`、`txtTocRule`、`readRecord`、`rssSources`、`rssStar` 完整跨设备互通 |
| **JS 变量持久化** | 接通 `book.getVariable/putVariable/setVariable` 与 `source.getVariable/setVariable` | 解决复杂书源跨详情页、目录页、正文页传递动态 Token 失败的问题 |
| **TXT 目录规则与动态切章** | `TxtTocRuleListView` + `TxtTocRuleEditSheet` | 支持正则目录规则增删改查、预装默认规则；本地 TXT 导入与详情页菜单均支持选择规则一键重新切章 |
| **发现源过滤** | `CategoryExploreView` 接入 `enabledExplore` | 过滤禁用发现的书源，并在书源编辑页与长按菜单提供「启用/禁用发现」开关 |

### 4. 阅读器、朗读与音频

| 模块 | 改进内容 | 说明 |
|---|---|---|
| **阅读器细节接线** | `progressBarBehavior` 与 `imageStyle` 生效 | 更多设置可切换进度条「按页调节 / 按章节调节」；正文渲染支持「纯文字 (`TEXT`)」过滤插图与「完整 (`FULL`)」铺满模式 |
| **HttpTTS 引擎与流媒体朗读** | `HttpTTSListView` + `AudioBookService` 支持网络 TTS | 支持自定义 HttpTTS 接口；朗读面板支持在系统离线语音与网络 HttpTTS 引擎间一键切换 |
| **在线有声书独立播放器** | `AudioPlayView` 深度集成 | 针对 `bookSourceType == 1` 或包含音频标签的书籍，提供黑胶旋转动效、流媒体音频播放、快进退 15s、倍速、定时关闭与章节目录 |
| **阅读记录自动统计** | `ReadRecordListView` + `ReaderView` 自动计时 | 阅读器挂载自动累计阅读时长并落盘 `ReadRecordStore`；设置页按书展示阅读时长、上次阅读时间与总时长汇总 |
| **字典规则与阅读器查词** | `DictRuleListView` + 搜索 Sheet「查字典」Tab | 支持自定义网络字典规则（内置百度汉语/汉典），阅读器查找弹窗内置查词 Tab 实时联网解析释义 |
| **条漫 / 漫画长图预览** | `ChapterImageView` 支持全屏放大 | 图片支持点击唤起全屏图片浏览器，支持双向平滑手势漫游 |
| **章节区间离线下载** | `ChapterRangeDownloadSheet` 上线 | 阅读器溢出菜单支持选择起止章节滑块或后续 50/100/全部下载，后台并发抓取并防爬虫限流 |

### 5. 信息架构、备份入口与订阅

| 模块 | 改进内容 | 说明 |
|---|---|---|
| **4-Tab 根架构与 RSS 订阅** | 根界面扩展为 4 Tab，上线「订阅」基础闭环 | `RssSourceListView`（订阅源管理/搜索/收藏/置顶/删除）、`RssArticleListView`（分类胶囊 + 文章流 + 下拉刷新）、`RssArticleReaderView`（`ruleContent` 正文提取）、`RssStarListView`（文章收藏夹）、`RssSourceEditSheet`（7 字段基础编辑器）；规则层缺口见 `FEATURE_GAP_ANALYSIS.md` §8 |
| **全部书签汇总** | 设置页 `所有书签` | 按「书名 · 作者」分组展示全站书签，支持内容/备注搜索、编辑/删除、导出 JSON 与 Markdown 至剪贴板 |
| **本地备份包导出与恢复** | `WebDAVSyncView` | 无需配置 WebDAV 即可离线导出/导入完整备份包（与 Android 兼容） |
| **搜索页书架匹配区块** | `SearchBookView` | 关键词命中本地书架时在顶部优先展示「书架已有」快捷卡片 |
| **源变量与书籍变量编辑** | `BookDetailView` 菜单 | 提供「设置书籍变量」与「设置源变量」弹窗（显示 `variableComment` 提示，读写持久化变量） |

### 6. 平台集成与外观

| 模块 | 改进内容 | 说明 |
|---|---|---|
| **URL Scheme 一键导入** | `Info.plist` + `LegadoApp.onOpenURL` | 注册 `legado://` 与 `yuedu://`；`?src=` / `?url=` 指向的书源 JSON 会被下载并导入书源列表 |
| **主屏快捷操作** | `UIApplicationShortcutItems` | 长按图标提供「搜索书籍」「继续阅读」两个入口 |
| **局域网 WiFi 传书 / Web 服务** | `LocalWebServer` (`Network.framework`) + 设置页入口 | 纯 `NWListener` 实现的轻量 HTTP 服务（无需第三方依赖）：网页上传 TXT/EPUB 直接入库、书源 JSON 端点；含 `NSLocalNetworkUsageDescription` 与 Bonjour 声明 |
| **水墨屏主题** | `ReaderTheme.eink` | 新增第 6 套主题（纯白底 `#FFFFFF` / 纯黑字 `#000000`），最大对比度、无彩色 |
| **阅读字体选择器** | `ReadStylePanel` | 「界面」面板可切换 系统默认(苹方) / 楷体(`STKaiti`) / 宋体(`Songti SC`) / 圆体(`Yuanti SC`)，写入 `textFont` 落盘 |

---

## v0.2.2（缓存与离线可用性）

### 1. 缓存与离线可用性（批次 P0.5）

| 模块 | 改进内容 | 原因 / 背景 |
|---|---|---|
| **离线可用性** | 失败态退出与重试解死锁 (`loadFailureView`) | 目录加载失败时提供「返回书架」按钮；重试逻辑改为重新加载目录 (`loadTOCAndStart`)，解决原 `loadInitialChapter` 因列表为空直接 return 的死锁 |
| **目录缓存优先** | 网络书目录入库与节流刷新 (`TocCache`) | 启动改为本地缓存优先 (`chapters_<md5>.json`)，避免每次进书必联网；后台 10 分钟静默刷新；目录章数变化时采用 `ChapterMatcher` 自动重定位当前阅读进度 |
| **网络预算与截断保护** | 请求超时与续页总时长封顶 | 单次请求超时设为 30s；目录续页封顶 200 页 / 120s，正文续页封顶 50 页 / 30s（`BookContentService.tocTimeBudget` / `contentTimeBudget`）；被截断的未完成内容严禁落盘缓存 |
| **缓存追加安全阀** | 纯追加校验 (`TocCache.isAppendOnly`) | 目录更新仅在纯追加时保留原章节正文缓存，目录结构错位时主动清空旧章节缓存，防止内容串章 |
| **朗读悬浮条** | `ReadAloudFloatingBar` 独立常驻 | 播放/暂停/结束三键常驻屏幕底部，与菜单显隐解耦；从当前页首字起读；自动过滤插图标记 `[image:...]` |
| **听书状态自持** | 播放状态自持有与暂停兜底 | 播放状态由 `AudioBookService.state` 自持，避免 `didPause` 回调丢失导致按钮状态卡死；暂停后 150ms 硬停兜底 |
| **阅读面板归一** | `ReaderPanelChrome` 统一规格 | 「界面」、「更多设置」、「朗读」面板共用圆角卡片、间距规范与半屏高度限制，消除各面板背景色与字体漂移 |
| **功能裁剪** | 主动移除亮度调节与音量键翻页 | 拦截音量键的私有机制实测导致系统全局音量被持续压低至 0；应用内亮度条与 iOS 系统控制中心能力冲突且视觉异常 |
| **设置页整理** | 移除冗余重复设置，收敛入口 | 删除设置页冗余的阅读器重复配置，统一收敛至阅读器内部面板；顺畅排列为书源、存储、外观、云备份、正文处理与关于 |

---

## v0.2.1（批次 P0：核心阅读与搜索闭环）

### 1. P0 8 大核心项落地记录

1. **P0-1 阅读页菜单骨架与面板拆分**
   - 拆解原有庞大单体 `ZStack` 为 `readingCanvas`、`controlsLayer`、`panelLayer`。
   - 引入 `ReaderPanel` 互斥枚举，解决多面板状态竞争。
   - 落地 3×3 九宫格自定义点击区域（`TapZoneOverlay`，强制中央区为菜单以防误锁死）。
2. **P0-2 配置持久化 (`ReaderStore` / `ReadStyleConfig`)**
   - 解决字号、行距、边距、主题冷启动丢失的问题，使用 Android 对齐字段落盘。
   - 采用 `TolerantJSON` 容错解码，兼顾老版本配置平滑升级。
3. **P0-3 书签体系 (`BookmarkSheet` / `BookmarkStore`)**
   - 采用「书名 + 作者」联合键持久化，整书换源后书签保持不丢。
   - 精确记录并还原段落内文字偏移位置 (`targetCharPos`)；支持导出 JSON 与 Markdown。
4. **P0-4 整书换源与单章换源 (`ChangeSourceService` / `ChapterMatcher`)**
   - 多源并发竞速搜索，支持基于 Jaccard 相似度与中文数字章节号解析的智能目录匹配。
   - 阅读器内置 `tryAutoChangeSource`，在正文获取失败时自动静默换源重试。
5. **P0-5 正文替换净化与简繁转换 (`ContentProcessor`)**
   - 实现包含标题去重、简繁转换 (`ChineseConverter`)、逐行正则过滤、缩进排版在内的 7 步净化管线。
   - 增加正则超时检测与自动禁用机制；支持「起效的替换」实时查看与单书开关。
6. **P0-6 朗读控制面板与后台播放 (`ReadAloudPanel` / `AudioBookService`)**
   - 改造为段落队列驱动；支持定时停止、语速微调、音调调节。
   - 集成 `MPRemoteCommandCenter` 与锁屏媒体信息；配置后台音频模式 (`UIBackgroundModes: audio`)。
7. **P0-7 搜索范围与搜索历史 (`SearchScopeSheet` / `SearchKeyword`)**
   - 搜索支持全部书源、分组筛选、单书源限定三态。
   - 引入三桶排序算法（完全匹配 / 包含匹配 / 其他），支持精准搜索过滤；实现搜索历史存储与快捷搜索。
8. **P0-8 字符集自动识别与目录/正文续页 (`CharsetDetector`)**
   - 支持 UTF-8 BOM 剥离、HTTP Header 编码嗅探、HTML Meta 标签探测与 GBK/Big5 智能打分兜底。
   - `BookContentService` 实现 `nextTocUrl`（上限 200 页）与 `nextContentUrl`（上限 50 页）多页自动抓取与去重拼接。

---

## 关键设计决策与 Android 偏离备忘

为适配 iOS 系统沙盒、生命周期及平台规范，部分机制进行了针对性调整，避免视为 Bug：

| 序号 | 项目 | 处理方案 | 偏离原因 |
|---|---|---|---|
| **1** | 仿真翻页 | 降级为平滑滑动效果 | iOS 实现拟真物理翻页卷曲需要专用图形 Shader 与复杂度较高的变换，收益偏低 |
| **2** | 简繁转换 | 采用系统 `CFStringTransform` | 避免打包笨重的 OpenCC 词典库，实测足以覆盖绝大多数繁简转换场景 |
| **3** | 重新分段 | 简化为「按空行重排 + 合并碎行」 | Android 端使用含随机因子的断行逻辑，iOS 保持确定性处理 |
| **4** | 正则替换超时 | 终止 Task、禁用该规则并保留未处理正文 | Android 因 Java 正则不可中断机制在超时后会强杀重启进程；iOS 优雅取消即可 |
| **5** | 缓存内容 | 磁盘持久化「未净化原文」，读取时动态净化 | 便于用户修改替换规则或切换开关后即时生效，无需强制清除离线章节缓存 |
| **6** | 续页双重限制 | 目录限 200 页 / 120s，正文限 50 页 / 30s | 防止个别书源配置死循环或极慢源导致挂死主流程；被截断的结果一律不写缓存 |
| **7** | 音量键翻页 | **完全移除** | 私有拦截手段实测会直接修改系统物理音量并持续压低至 0，副作用不可接受 |
| **8** | 亮度调节 | **完全移除** | 与 iOS 控制中心功能完全重复，且应用内浮层存在视图遮挡与绘制瑕疵 |
| **9** | 单章换源流程 | 自动调用 `ChapterMatcher` 映射章节 | 章节匹配器单测通过率高，直接映射避免频繁打断用户翻页体验 |
| **10** | 书源分类噪声 | 仅**显示层**过滤 Android 校验判定词与 `good` 标记 | 书源数据必须与 Android 双向互通，因此 `bookSourceGroup` / `bookSourceComment` / `respondTime` 一律原样保存,不改写书源;噪声只在渲染分组胶囊时隐藏 |
| **11** | 响应耗时 (`respondTime`) | 仅在 `0 < ms < 180000` 时展示 | 同一字段在 Android 是「整轮校验耗时」,校验失败时写入 `timeout + 耗时`(≥180000)属失败标记;iOS 单次搜索耗时与之不可比,故隐藏失败标记并保留原始数据 |
| **12** | 文字两端对齐开关在滚动模式下置灰 | 只有 CoreText 路径（翻页模式）能强制两端对齐 | SwiftUI `Text` 不支持 `textAlign: justify`；滚动模式用原生 `Text` 渲染 |
| **13** | 「更多设置」面板只保留**真的生效**的开关 | `readBarStyleFollowPage`、`noAnimScrollPage`、`previewImageByClick`、`disableReturnKey`、`screenOrientation` 等项在 iOS 无对应实现 | 宁可不显示也不给死开关；`progressBarBehavior` 已于 v0.2.3 接线并恢复 picker |
| **14** | 搜索空结果**不弹**「切换到全部书源 / 关闭精准搜索」引导 | 属交互打磨而非能力缺失 | 书架匹配区块（`SearchBookView.matchedBookshelfBooks`）已上线，空结果引导留待后续 |
| **15** | 三个底部面板（「界面」/「更多设置」/「朗读」）统一走 `ReaderPanelChrome` | 同一个卡片曾被抄了三遍，底色/行标签透明度/高度三处漂移 | 统一占屏幕下 1/2、统一可滚动、统一行原语，全部跟随阅读主题色 |
| **16** | 音量键翻页相关开关（`volumeKeyPage` 等 3 项）随功能整体移除 | 见 #7 | 与 #7 同因；三个开关不再出现在任何面板 |

---

## 后续版本规划（P2 / P3）

P1（生态兼容与书源维护）已在 v0.2.3 落地。剩余项详见 [FEATURE_GAP_ANALYSIS.md](FEATURE_GAP_ANALYSIS.md) §23：

- **P2（功能对齐）**：完整 RSS 订阅源全字段编辑器、订阅源调试页与规则订阅聚合、Android 的高级分组（分组封面 / 组内排序 / 位掩码多选 / 拖拽排序）、MOBI/AZW3/UMD/PDF 本地格式（Android 亦不支持 FB2）、书内全文搜索、内置通用浏览器、二维码扫描导入、文本选择与词典取词。
- **P3（iOS 平台特性融合）**：桌面 Widgets（书架/进度）、App Intents / Share Extension / Universal Links 深度联动、CarPlay、完整 LAN REST/WebSocket API（WiFi 传书已落地）。
