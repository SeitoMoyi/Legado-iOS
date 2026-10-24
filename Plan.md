# Legado iOS 迁移蓝图、功能差距清单与演进规划 (Plan.md)

> **基准说明**
> - **Android 对标基线**：`/Users/peibinxu/Downloads/legado-master`（`app/` 813 个 Kotlin 文件，`app/` + `modules/` 合计 844；184 个 layout XML，完整功能版 3.x）。
> - **iOS 当前工程基线**：`./ios`（`Sources/LegadoCore` + `Sources/LegadoApp`）共 **71 个 Swift 文件 ≈ 26.3k 行**（LegadoCore 35 文件 9.0k 行 + LegadoApp 36 文件 17.3k 行；含 Tests 共 88 文件）。
> - **单测门禁**：17 个测试文件共 **258 例单元测试**（251 项确定性用例 + 7 项联网嗅探冒烟测试；`swift test --skip LiveSourceTests` 实测 251/251 通过）。
> - **应用图标**：Android Legado 512px 母版（`ic_launcher-web.png`）经 `Assets.xcassets/AppIcon` 单尺寸 1024 编译注入。
> - **工程原则**：业务代码为纯 Swift，仅保留两个轻量 SPM 依赖——SwiftSoup（HTML/XPath 解析）与 ZIPFoundation（EPUB 与备份包解包）；严守 macOS (`swift build` / `swift test`) 与 iOS (`xcodebuild`) 双平台门禁。
> **当前版本**：`v0.2.7.6`（`VERSION` 文件；版本随 tag 发布）
---

## 目录
- [一、 Android ↔ iOS 当前功能差距对比矩阵](#一-android--ios-当前功能差距对比矩阵)
- [二、 关键设计决策与 Android 架构偏离备忘](#二-关键设计决策与-android-架构偏离备忘)
- [三、 版本变更摘要与已固化的对齐语义](#三-版本变更摘要与已固化的对齐语义)
- [四、 后续迭代演进路线图 (Future Roadmap)](#四-后续迭代演进路线图-future-roadmap)
  - [Phase 1: P2 核心生态与高频功能（近期重点）](#phase-1-p2-核心生态与高频功能近期重点)
  - [Phase 2: P2 进阶系统与数据完整性（中期推进）](#phase-2-p2-进阶系统与数据完整性中期推进)
  - [Phase 3: P3 iOS 平台深度融合（远期演进）](#phase-3-p3-ios-平台深度融合远期演进)

---

## 一、 Android ↔ iOS 当前功能差距对比矩阵

### 标记说明
| 标记 | 含义 |
|---|---|
| ✅ | 已实现，核心行为与 Android 基本对齐 |
| ⚠️ | 部分实现（有入口但功能存在缺口 / 只覆盖核心分支） |
| ❌ | 完全缺失 |
| 🍎 | 涉及 Android 专属机制，iOS 需结合平台特性重新定义 |

### 总体版面完成度矩阵

| # | 功能版面 | Android | iOS | 完成度 | 现状与核心缺口 |
|---|---|---|---|---|---|
| 1 | **应用外壳 / 底部导航** | 4 Tab 可配 | 4 Tab 固定 | **60%** | 书架/分类/订阅/设置 4 Tab 已上线；缺 Tab 显隐、默认主页、角标、启动隐私协议、本地备份密码 |
| 2 | **书架页** | 极重 | 中等 | **62%** | 列表与三列网格、5 种排序（含手动拖拽排序，`Book.order` 落盘）、分组胶囊（全部/书源/本地/自定义 CRUD）、批量清理/移入/删除已实现；缺封面文字、网格模式拖拽、远程书籍、书单导入导出 |
| 3 | **书籍详情页** | 完整 | 较完整 | **80%** | 书籍信息编辑、置顶、整书换源、拷贝 URL、目录正倒序/居中/缓存标识已实现；缺二维码分享、WebDAV 书籍上传 |
| 4 | **全屏沉浸阅读器** | 全站最重 | 高度完善 | **75%** | 统一 CoreText 排版引擎、长标题折行、5 档翻页（仿真降级为滑动）、双向无缝长卷滚动、三级菜单、书签、九宫格点击区、换源/刷新快捷键、章节内容编辑、区间下载、双模式文字两端对齐、6 套主题（5 套预设 + 自定义）、TTS 面板与常驻悬浮条已实现；缺自动翻页在滚动模式下的逐像素平滑滚动、长按选词与词典菜单；**书内全书并发搜索已实现**（`SearchContentSheet`：缓存优先 + 联网并发抓取、关键字/正则、命中高亮、精准跳转章节字符偏移） |
| 5 | **分类 / 发现页** | 书源折叠流 | 三级分类流 | **65%** | 切源胶囊、预设分类矩阵抽屉、标准书籍卡片流、动态 JS 脚本解析已实现；缺按分组筛选、单源操作菜单、ERROR 堆栈查看 |
| 6 | **搜索页** | 多源并发 | 多源并发 | **85%** | 多源增量并发、精准搜索三桶排序、范围三态选择、书架已有藏书匹配置顶、搜索历史增删、停止与继续已实现；缺空结果智能引导、退后台挂起 |
| 7 | **RSS 订阅中心** | 独立完整模块 | 深度完善 | **75%** | 独立 Tab、源管理、分类解析、文章流与正文提取、文章收藏夹、**全字段编辑器（24 字段，含 loginUrl/loginUi/variable/header/style 等）**、**三阶段流式调试台（分类→列表→正文）**、**文章 3 种版式切换（左文右图/无图/双列网格，持久化）**、**ruleNextPage 触底翻页自动拼装**、**已读置灰与阅读历史落盘**均已实现；缺交互式登录 WebView（loginUrl 仅可编辑）、订阅源并发校验、啃读模式 |
| 8 | **书源管理页** | 极重 | 中高 | **78%** | 搜索过滤（含 `group:`）、三态胶囊、批量启/禁/删/导、并发校验与失效标记、长按菜单、3 种导入、**拖拽排序模式（优先级 = `customOrder` 重排）**已实现；缺二维码扫码、逐条勾选导入 |
| 9 | **书源编辑页** | 6 Tab 全字段 | 6 Tab 全字段 | **85%** | 基本/搜索/发现/详情/目录/正文 6 Tab 全规则字段编辑、整源 JSON 拷贝粘贴、直达调试台已实现；缺语法高亮与辅助符号键盘条 |
| 10 | **书源调试页** | 完整 | 四阶段实时调试台 | **65%** | 搜索→详情→目录→正文四阶段流式实时调试日志已实现；缺阶段原始 HTML 查看器、WebSocket 实时调试 |
| 11 | **登录 / 内置浏览器** | 完整 | 登录✅ 浏览器❌ | **50%** | 交互式 WebKit 登录、Cookie 域过滤提取并写入 `loginHeader` + 镜像至 `HTTPCookieStorage` 已实现；缺通用内置浏览器、Cloudflare 过盾自动重试、文件下载 |
| 12 | **设置中心（「我的」）** | 约 140 项设置键 | Android 同构布局 | **50%** | **v0.2.8 起对齐 Android `pref_main.xml` 布局**：顶层六行（书源管理 / TXT 目录规则 / 替换净化 / 字典规则 / 主题模式 / Web 服务开关）+「设置」分组（备份与恢复 / 其它设置）+「其它」分组（书签 / 阅读记录 / 关于）；Tab 更名「我的」「发现」与 Android 四 Tab 一致；正文处理/朗读引擎/清缓存收敛进「其它设置」子页；缺帮助文档站、文件管理 |
| 13 | **规则管理中心** | 4 独立 CRUD 页 | 4 独立 CRUD 页 | **90%** | 替换净化、TXT 目录规则、字典规则、HttpTTS 均已实现 CRUD、预装预设、导入导出与 **`EditButton` 拖拽排序**（TXT 重写 `serialNumber`、字典重写 `sortNumber`）；缺二维码导入 |
| 14 | **文件与数据互通** | 完整 | 完善 | **80%** | WebDAV 10 类数据备份恢复、双向阅读进度同步、离线本地备份包、所有书签汇总与 Markdown 导出、阅读记录统计已实现；缺 Android 备份包剩余 11 个成员（`bookGroup`/`sourceSub`/`httpTTS`/`dictRule`/`servers`/`keyboardAssists`/`directLinkUploadRule`/`shareReadConfig`/`themeConfig`/`coverRule`/`config.xml`）、私有文件浏览器 |
| 15 | **局域网服务 / 平台集成** | 完整 REST API | 轻量原生服务 | **35%** | 原生 `Network.framework` WiFi 传书门户与上传入库、`legado://` Scheme 导入、主屏快捷操作已实现；缺全套 REST/WebSocket API、后台常驻服务 |
| 16 | **核心规则解析引擎** | 全语法 | CSS/JSONPath/XPath/JS | **70%** | CSS、JSONPath（含 `$..`）、轻量 XPath 求值器、正则链式清洗、`<js>` / `@js:`、变量读写（`book.getVariable` / `putVariable`）、URL 选项的 `method`/`charset`/`retry`/`headers`/`body` 已实现；缺 URL 选项其余键、`jsLib` 预加载、AES/RSA/HMAC 等加密桥接 |
| 17 | **本地书籍格式** | 6 种主流格式 | EPUB / TXT | **45%** | EPUB3/EPUB2 图文与分卷解析、TXT 编码嗅探与智能切章已实现；缺 MOBI、AZW3、UMD、PDF 解析 |

---

## 二、 关键设计决策与 Android 架构偏离备忘

在迁移过程中，为契合 iOS 原生平台交互规范、沙盒限制与内存生命周期，部分机制进行了主动调整：

| # | 机制项 | iOS 处理方案 | 偏离原因与依据 |
|---|---|---|---|
| **1** | **仿真翻页动画** | 降级为平滑滑动效果 | iOS 拟真纸张卷曲需复杂 OpenGL/Metal Shader 变换，功耗高且收益低，滑动能提供更干净的视觉体验。 |
| **2** | **简繁转换** | 基于系统 `CFStringTransform` | 避免打包笨重的 OpenCC 词库，零第三方依赖。实测常用词正确（`头发→頭髮`、`面条→麵條`、`干净→乾淨`、`后来→後來`、`干杯→乾杯`），但**不等价于 Android**：Android `fixT2sDict()` 的 64 词排除表里有 23 词仍会被转换（`模組→模组`、`變數→变数`、`規則→规则`、`離線→离线`、`載入→载入`、`計程車→计程车` 等）；且一字多义仍会误判（`姓钟`→`姓鐘`，应为 `姓鍾`）。 |
| **3** | **重新分段** | **不实现** `reSegment` | Android 的 `ContentHelp.reSegment` 用 `Math.random()` 决定断句位置（`if (Math.random() * gain < 0.8 + k / 2.5)`），同一章每次打开结果都不同，无法缓存也无法测试；iOS 保留原始换行，只做确定性修剪。 |
| **4** | **正则替换超时** | 终止 Task、禁用规则并丢弃其结果 | Android 捕获 `RegexTimeoutException` 后禁用该规则，并把「规则名 + 堆栈」写进正文；iOS 同样禁用规则（`onRuleAutoDisabled` → 落盘 `isEnabled = false`），但不污染正文。 |
| **5** | **离线章节缓存** | 磁盘持久化「未净化原文」，读取时动态净化 | 便于用户修改替换规则或切换开关后即时生效，无需强制清理整本离线缓存。 |
| **6** | **续页双重限制** | 目录限 200 页 / 120s，正文限 50 页 / 30s | 防止个别书源配置死循环或慢源挂死主流程；被截断的未完成内容一律不写入磁盘缓存。 |
| **7** | **音量键翻页** | **完全移除** | iOS 拦截音量键的私有手段（`MPVolumeView`）实测会导致系统硬件音量被持续压低至 0，副作用严重。 |
| **8** | **应用内亮度调节** | **完全移除** | 与 iOS 系统控制中心手势冲突，且应用内浮层在刘海屏设备上存在绘制瑕疵。 |
| **9** | **常驻系统状态栏** | 阅读器常驻系统顶栏（时间、电量、网络） | 对齐 Android 原生沉浸体验，字体颜色随浅色/暗黑主题自适应，移除冗余的「隐藏状态栏」死开关。 |
| **10** | **文字两端对齐** | 滑动与连续滚动双模式均生效 | v0.2.5 将连续滚动全面重构为原生 CoreText 画布（`ReaderScrollCanvasView`）并收敛至统一排版引擎，彻底解决原 SwiftUI `Text` 无法两端对齐的限制。 |
| **11** | **书源分类噪声处理** | 仅在**显示层**过滤判定词与 `good` 标记 | Android 的 `CheckSourceService` 会将校验判定写入分组。`bookSourceGroup` 本身原样保存，仅在渲染胶囊时隐藏，避免把判定词当成真实分类展示。 |
| **12** | **响应耗时 (`respondTime`)** | 仅在有效测量值 (`0 < ms < 180000`) 时展示 | Android 校验失败时写入 `180000 + 耗时`（属失败标记而非延迟）；iOS 隐藏失败标记以避免将罚时当成速度显示。 |
| **13** | **单章换源流程** | 自动调用 `ChapterMatcher` 映射章节 | 章节匹配器单测通过率极高，自动映射可避免频繁打断用户翻页。 |
| **14** | **阅读面板归一** | 统一采用 `ReaderPanelChrome` | 「界面」、「更多设置」、「朗读」面板共用圆角卡片、间距规范与半屏高度限制，消除各面板样式漂移。 |
| **15** | **JSON 往返字段保真** | **已修复**：三个模型保留 `extra: [String: JSONValue]` 原始字典 | `BookSource` / `RssSource` / `Book` 解码时把未建模的 Android 字段（`jsLib`、`concurrentRate`、`enabledCookieJar`、`ruleReview`、`Book.customTag` / `customIntro` / `charset` / `type` / `order` / `syncTime` 等）收进 `extra`，`encode(to:)` 时**扁平化回写**为顶层键（无 "extra" 包装，Android GSON 直接识别）。`JSONExtrasTests` 8 例锁定往返零丢失。`RssSource` 同时补齐 `loginUrl` / `loginUi` / `variable` 三个 Android 字段。 |

---

## 三、 版本变更摘要与已固化的对齐语义

### v0.2.7.x 系列变更一览
| 版本 | 内容 |
|---|---|
| v0.2.7.1 | 「我的」页按 `pref_main.xml` 重排（顶层六行 + 设置/其它分组）；翻页模式持久化修复；底部 Tab 对齐 `main_bnv.xml`（书架/发现/订阅/我的） |
| v0.2.7.2 | （跳过） |
| v0.2.7.3 | 自带书源与书源硬编码全部移除（`xkvi→novelia` 迁写、别名匹配、ESJ 专属 UI、测试凭证）；活体测试改用社区源列表；书架/详情/搜索页深度布局对齐（详情垂直头部 + `fl_action` 底栏 + 菜单顺序）；搜索历史流式胶囊 |
| v0.2.7.4 | 书架下拉刷新元数据完整更新：合并书名/封面，章节列表落盘（对齐 Android `upBookInfo`） |
| v0.2.7.5 | 分页自然度：段距记账对齐 Android（挂下一段首行、跨页重置），页底不再提前分割；`LegadoAppTests` 分页不变量回归锁 |
| v0.2.7.6 | 阅读器菜单对齐（底栏四入口 + 悬浮球四键 + 界面面板方块化 + 纯色主题块）；应用图标（Android Legado 512px 母版）；审计去重 |

### 已固化的对齐语义（后续开发必须遵守）
1. **请求头合并**：一切书源请求头经 `JSEngine.resolvedSourceHeader(source, engine:, loginHeaderOverride:)`——header 规则求值后**叠加** loginHeader（Android `getHeaderMap(hasLoginHeader:)` 语义），严禁 `loginHeader ?? header` 替换式写法。
2. **`getLoginHeader()`** 仅返回登录捕获头，不回退静态 `header`（登录态分支判定依赖此语义）。
3. **`java.ajax/connect`** 经 `JavaShim.defaultHeaderProvider` 携带书源头。
4. **`<js>`/`@js:` 拆分** 统一走 `JSEngine.splitJSRule` / `extractJSScript`；kind 类列表规则用 `getStringList`（对齐 Android `BookInfo.kt`），单值字段用 `getString`。
5. **JSON 往返**：未建模字段一律进 `extra`（`JSONExtraPreserving`），encode 扁平化回写。
6. **分页记账**：段距挂下一段首行、页首行不收段距、跨页重置（Android `prepareNextPageIfNeed(durY + textHeight)` 语义），不变量由 `TypographyPageFillTests` 锁定。
7. **过滤视图拖拽排序**：置换可见子集自身序号槽位，不动视图外条目。
8. **详情页 TabBar**：隐藏/还原走 `TabBarVisibility`（来源页 onAppear 还原，pop 开始瞬间生效）；TabBar 材质由 App 启动时全局 Appearance 声明。
9. **听书启动/续读**统一走 `aloudPlayOrResume()`（可见段落==朗读段落才 resume，否则重锚定）。
10. **全书搜索**偏移基于净化后文本（`fetchChapterContent(context:)` 同管线），跳转按字符偏移精准定位。

## 四、 后续迭代演进路线图 (Future Roadmap)

P0（核心阅读闭环）与 P1（高频生态与工具链）已达成，排版底层与连续长卷滚动架构终态收敛。**下一版本 v0.2.8（中版本）目标：完成 Phase 1 剩余三项（Part 3/4/6）**，随后推进 Phase 2/3：

```mermaid
graph TD
    subgraph Phase 1: P2 核心生态与高频功能
        T1[Part 1: RSS 订阅深度完善 ✅]
        T2[Part 2: 列表拖拽与手动排序 ✅]
        T3[Part 3: 二维码全链路集成]
        T4[Part 4: 文本选择与取词联动]
        T5[Part 5: 书内全书并发搜索 ✅]
        T6[Part 6: 通用内置 WebKit 浏览器]
    end

    subgraph Phase 2: P2 进阶系统与数据完整性
        T7[Part 7: 规则订阅聚合 sourceSub]
        T8[Part 8: WebDAV 21 类全数据对齐]
        T9[Part 9: 本地 MOBI/AZW3/PDF 解析]
        T10[Part 10: 高级主题与背景图系统]
        T11[Part 11: 漫画模式专用交互]
    end

    subgraph Phase 3: P3 iOS 平台深度融合
        T12[Part 12: iOS 桌面组件 Widgets]
        T13[Part 13: App Intents 与 Share 扩展]
        T14[Part 14: CarPlay 与 VoiceOver 无障碍]
        T15[Part 15: 完整局域网 REST API]
    end

    Phase 1 --> Phase 2
    Phase 2 --> Phase 3
```

---

### Phase 1: P2 核心生态与高频功能（近期重点）

#### Part 1：RSS 订阅深度完善 ✅（已完成）
全字段编辑器（24 字段含 loginUrl/loginUi/variable）、三阶段流式调试台、文章 3 版式（articleStyle 持久化）、`ruleNextPage` 触底翻页（自环保护 + link 去重）、已读置灰与阅读历史落盘（500 条上限）。**遗留**：交互式登录 WebView、订阅源并发校验。

#### Part 2：列表拖拽与手动排序 ✅（已完成）
`Book.order` 建模落盘（新书 `minOrder-1` 置顶）+ 书架「手动排序（可拖拽）」；书源拖拽排序（`customOrder` 重排优先级）；TXT/字典/HttpTTS/RSS 四列表 `EditButton`+`.onMove`。过滤视图拖拽置换子集槽位。**遗留**：网格模式拖拽（`LazyVGrid` 无 `.onMove`）。

#### Part 3：二维码全链路集成
- **目标**：打通多端扫码导入与生成分享闭环。
- **实施点**：
  1. 基于 `AVFoundation` 开发轻量扫码页 `QRCodeScannerView`，支持扫描书源、规则、订阅源、WebDAV 配置 JSON 或导入直链。
  2. 支持从系统相册选取二维码图片并使用 `CIDetector` 离线识别。
  3. 书籍详情页与书源管理页菜单新增「生成分享二维码」，支持将配置编码为高清二维码展示与保存相册。

#### Part 4：阅读器文本选择与取词联动
- **目标**：在 CoreText 统一排版画布上建立原生级选词交互。
- **实施点**：
  1. 在 `ChapterCanvasLayerView` 与滑动视图上挂载长按手势（600ms），识别字符索引并计算文本包围盒（Bounding Box）。
  2. 绘制半透明主色选区高亮图层与左右两个调节双把手。
  3. 弹出上下文交互菜单（`UIMenuController` 或 SwiftUI 浮层）：
     - **复制**：复制选中文字至剪贴板。
     - **查字典**：直接调起内置「查字典」Tab 查询选中词汇释义。
     - **添加书签**：将选中句直接作为摘录内容创建书签。
     - **朗读所选**：从选中段落立即启动 TTS 朗读。
     - **创建替换规则**：以选中词为默认目标打开快速替换弹窗。

#### Part 5：书内全书多章并发搜索 ✅（已完成）
`BookContentSearchService`（AsyncStream 进度/命中/完成事件、6 并发分块、缓存优先 + 可选联网、单章命中封顶）+ `SearchContentSheet`（关键字/正则、命中高亮、字符偏移精准跳转、净化管线同基准）。入口：搜索弹窗顶部直达卡。

#### Part 6：通用内置 WebKit 浏览器
- **目标**：补齐非登录场景的网页浏览与 Cloudflare 智能过盾。
- **实施点**：
  1. 封装通用浏览器组件 `GeneralWebBrowserView`：包含前进、后退、刷新、复制 URL、Safari 打开、Cookie 管理。
  2. 自动过盾处理：当网络请求遇到 403 / 503 防爬或人机验证页时，自动弹出轻量浏览器引导用户完成滑动/验证，验证通过后自动回写 Cookie 至全局存储并重试正文抓取。

---

### Phase 2: P2 进阶系统与数据完整性（中期推进）

#### Part 7：规则订阅聚合 (`sourceSub.json`)
- 支持导入与管理外部规则聚合订阅源，定期自动检查更新并合并书源、替换规则与订阅源。

#### Part 8：WebDAV 完整 21 类数据对齐
- 扩充备份与恢复范围，覆盖 `servers`、`bookGroup`、`directLinkUploadRule`、`coverRule` 等剩余成员；实现导入恢复时的「忽略列表」多选配置。

#### Part 9：本地书籍格式扩展
- 引入轻量纯 Swift 解析器，扩展对 **MOBI**、**AZW3** 与 **PDF** 本地电子书的流式排版与渲染支持。

#### Part 10：高级主题与背景图系统
- 独立主题管理中心：支持新建、命名、导出自定义主题；支持正文背景图片纹理（Android 端 `assets/bg` 预装 14 张纹理，可对齐移植 + 相册自选）。
- E-Ink 深化：现有「水墨屏」主题只提供纯白底 + 纯黑字，仍需去除界面阴影与半透明层、提升对比度。

#### Part 11：漫画模式专用交互
- 针对图片书源或条漫格式提供横向整页翻页、PagerSnap 贴靠、双指 Pinch 缩放、图片二值化与滤镜。

---

### Phase 3: P3 iOS 平台深度融合（远期演进）

#### Part 12：iOS 桌面组件 (Widgets)
- 使用 WidgetKit 构建主屏组件：书架封面墙轮播、当前阅读书籍进度与最近更新章节提示。

#### Part 13：系统深度集成
- **App Intents**：集成 iOS 16+ App Intents 框架，支持通过 Siri 语音或快捷指令指令搜索小说与继续阅读。
- **Share Extension**：系统分享面板扩展，在 Safari 或第三方应用中选中链接或文本时，可一键发送给 Legado 加入书架或触发搜索。
- **Universal Links**：配置关联域名，支持网页端直链唤起客户端。

#### Part 14：CarPlay 与无障碍体验
- **CarPlay**：针对听书与音频书场景接入 CarPlay 模板，驾驶模式下安全切换章节与播放控制。
- **无障碍**：阅读器画布与控制面板适配 VoiceOver 读屏辅助标签，保障视障读者无障碍使用。

#### Part 15：完整局域网 REST API
- 扩展 `LocalWebServer`，补齐对齐 Android `HttpServer.kt` 的 12 GET + 14 POST 接口，支持通过局域网在 PC 浏览器端完整管理书架、书源及在线阅读。
