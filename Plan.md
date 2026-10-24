# Legado iOS 迁移蓝图、功能差距清单与演进规划 (Plan.md)

> **基准说明**
> - **Android 对标基线**：`/Users/peibinxu/Downloads/legado-master`（`app/` 813 个 Kotlin 文件，`app/` + `modules/` 合计 844；184 个 layout XML，完整功能版 3.x）。
> - **iOS 当前工程基线**：`./ios`（`Sources/LegadoCore` + `Sources/LegadoApp`）共 **71 个 Swift 文件 ≈ 26.3k 行**（LegadoCore 35 文件 9.0k 行 + LegadoApp 36 文件 17.3k 行；含 Tests 共 88 文件）。
> - **单测门禁**：17 个测试文件共 **256 例单元测试**（249 项确定性用例 + 7 项联网嗅探冒烟测试；`swift test --skip LiveSourceTests` 实测 249/249 通过）。
> - **工程原则**：业务代码为纯 Swift，仅保留两个轻量 SPM 依赖——SwiftSoup（HTML/XPath 解析）与 ZIPFoundation（EPUB 与备份包解包）；严守 macOS (`swift build` / `swift test`) 与 iOS (`xcodebuild`) 双平台门禁。
> **当前版本**：`v0.2.7.3`（`VERSION` 文件；版本随 tag 发布）
---

## 目录
- [一、 Android ↔ iOS 当前功能差距对比矩阵](#一-android--ios-当前功能差距对比矩阵)
- [二、 关键设计决策与 Android 架构偏离备忘](#二-关键设计决策与-android-架构偏离备忘)
- [三、 详细功能版面差距明细](#三-详细功能版面差距明细)
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

## 三、 详细功能版面差距明细

### 1. 应用外壳与主界面
- **已实现**：书架 / 分类 / 订阅 / 设置 4 Tab 架构；主屏快捷操作（`UIApplicationShortcutItems` → `LaunchRouter` 场景级分发）。
- **待补齐**：Tab 自由显隐配置、自定义启动默认主页、书架待更新数量角标（BadgeView）、首次启动隐私协议弹窗、本地备份包密码加密（AES）。

### 2. 书架与书籍详情
- **已实现**：三列网格与列表切换、4 种排序规则、系统与自定义分组管理（新建/删除，暂无重命名）、多选批量清理/移入/删除、书籍信息自定义编辑、整书与单章换源、置顶、拷贝 URL、目录自动居中与缓存标记。
- **待补齐**：高级封面文字展示、分组封面选图、组内独立排序、网格模式拖拽（列表模式手动排序已实现）、远程书籍（WebDAV 浏览与直接加架）、书单导入导出（`bookshelf.json` 独立流程）。

### 3. 全屏阅读器与排版
- **已实现**：统一 CoreText 排版真理源（`ChapterTypography`）、超长标题自适应多行折行、滑动与连续滚动无缝衔接、`TypographyPage` 图文统一模型、滚动模式插图真实渲染、九宫格自定义点击区、章节内容自定义修改、区间离线下载、双TTS引擎与悬浮控制条、WebDAV 进度双向同步。
- **待补齐**：
  - 自动翻页进阶：连续滚动下的逐像素平滑滚动（目前按章衔接）。
  - 文本长按选择层：CoreText 字符选择高亮、双把手拖拽、上下文动作菜单（复制/词典/书签/朗读/替换）。
  - 样式编辑器：自定义阅读背景图片（内置 14 张图与相册选取）、自定义命名样式。

### 4. 规则引擎与解析能力
- **已实现**：CSS 选择器、JSONPath（含 `$..` 递归下降）、轻量 XPath 求值器（`//`、`/`、`|` 并集、`[@attr]`、`[contains()]`、`[N]`、`[last()]`、`..` 父节点）、正则清洗链、`<js>` / `@js:` 动态脚本、`book.getVariable` / `putVariable` 持久化读写、URL 选项的 `method` / `charset` / `retry` / `headers` / `body`。
- **待补齐**：URL 选项剩余键（`js`、`webJs`、`type`、`webViewDelayTime`、`useWebView`）、`source.jsLib` / `rssSource.jsLib` 预加载库、`java` 桥接的加密扩展（现仅有 `md5Encode` / `base64Encode` / `base64Decode` / `timeFormat`，无 AES/RSA/HMAC）。

### 5. 局域网服务与平台生态
- **已实现**：纯原生 `NWListener` 实现的局域网 WiFi 传书门户（网页文件选择上传 TXT/EPUB，服务端按 `Content-Length` 收满整包、解出 multipart 文件字节后自动入库）、URL Scheme 一键导入。
- **待补齐**：完整 REST/WebSocket API、静态管理后台 SPA、桌面 Widgets（书架封面墙/阅读进度）、Share Extension（外部分享加架）。

### 6. 书源供应链清理（2026-10-24）
- **自带书源全部移除**：删除 `Resources/bookSources.json`（机翻机器人 + ESJ 两条）及 `loadBundledSources` / 预装恢复 UI / 启动预载全链路，应用不再预装任何书源。
- **书源相关硬编码全部移除**：
  - `normalizeLegacyUrl` 的 `book.xkvi.top → n.novelia.cc` 域名迁移改写（导入、恢复、载入三处）。
  - `findSource(for:)` 的 Novelia/xkvi/fishhawk/机翻 别名匹配与 ESJ 别名匹配（保留通用的 URL/名称/域名/子串匹配）。
  - `updateSource` 的 novelia 域名特判、WebDAV 恢复的 xkvi 源过滤。
  - `SourceWebLoginView` 的 ESJ 专属「one 站/cc 站」镜像切换按钮与 esjzone 域名 Cookie 兜底。
  - 测试中的硬编码书源凭证（登录账号密码）随之删除。
- **活体书源测试改用社区列表**：`LiveSourceTests` 改为从 `https://list.xkvi.top/legado/booksource.json`（n.novelia.cc 国内反代）在线拉取书源并全链路验证。

### 7. 规则引擎请求头与登录态修复（2026-10-24，xkvi 书源接入实测驱动）
对 xkvi 反代书源全链路联调时发现并修复四个引擎缺陷，全部对齐 Android 语义：
1. **`getLoginHeader()` 语义错误**（`JSEngine.setupEnvironment`）：原先回退到静态 `header` 字段，导致书源 `<js>` 里 `level=${token ? 0 : 1}` 等登录态分支误判为「已登录」，用失效 Token 构造 level=0 请求全面 502。现仅返回登录捕获头（对齐 Android `CacheManager.get("loginHeader_<key>")`）。
2. **`java.ajax` / `java.connect` 不携带书源请求头**：书源 exploreUrl 内 `java.ajax("/api/user/favored")` 裸发请求被反代拒之门外（502 → 「未知错误」占位）。现通过 `JavaShim.defaultHeaderProvider` 携带合并后的书源头（对齐 Android `AnalyzeUrl(url, source=)`）。
3. **`BookExploreService` 请求头未求值**：`<js>` header 原样传入 `parseLegadoUrl` 被静默丢弃 → 分类请求无 Cookie 全部 502（即「分类功能残留 + HTTP 502」的主因）。
4. **请求头合并语义错误**：`loginHeader ?? header` 是**替换**，而 Android `getHeaderMap(hasLoginHeader: true)` 是 header 求值后**叠加** loginHeader。xkvi 反代边界以 header 里的 `Cookie` 作网关放行、认证走 `Authorization: Bearer`，替换后登录态请求反而丢失 Cookie 全部 502。现统一收敛到 `JSEngine.resolvedSourceHeader(source, engine:, loginHeaderOverride:)`（搜索/详情/目录/正文/分类/RSS 全链路 + JS 引擎内部 ajax/connect）。

修复后的行为矩阵（xkvi 书源实测）：
- 未登录：`level=1` 游客搜索 20 本/页、分类浏览正常，分类栏显示「账号未登录」占位（书源自带共享 Cookie 过反代网关）。
- 登录后（表单脚本登录 → `Authorization: Bearer <JWT>` 叠加共享 Cookie）：`level=0` 搜索 20 本/页、分类出现 阅读历史/默认收藏夹/R18 并可正常浏览。
- 新增 `testXkviJifanLoginFlow`：登录 → 搜索 → 分类 → 浏览四步全链路（凭证走 `LEGADO_XKVI_USER`/`LEGADO_XKVI_PASS` 环境变量，不入库）。

### 8. 代码清理（2026-10-24，v0.2.6 发布前）
- **硬编码终检**：Sources 全目录域名扫描仅剩三类合法 URL——WebDAV 服务商预设（坚果云/TeraCloud）、RSS 预装订阅（少数派/V2EX 公共 Feed）、字典规则预设（百度汉语/汉典），均为产品功能而非站点耦合逻辑；书源站名（ESJ/Novelia/xkvi）仅存于解释 Android 行为的注释中。
- **死代码移除**：SPM 模板残留 `LegadoCore.swift`（含 pbxproj 注册）；`RssService.fetchArticles` 兼容包装（调用方已全部迁移 `fetchArticlePage`）；`ArticlePage.isLastPage` 未使用计算属性；`BookStore.tocRefreshInterval` 未使用别名；`AudioBookService.punctuationOnlyPattern` 未使用正则常量；`BookExploreService` 中被 `extractJSScript` 覆盖后死亡的 `@js:` 分支。
- **重复逻辑收敛**：`<js>…</js>` / `@js:` 脚本抽取五处重复实现收敛为 `JSEngine.extractJSScript(from:)`（搜索 URL 渲染、分类解析、请求头求值内部）；`SourceManagerView` 两份一致的 web 登录判定合并为单一静态方法。
- `BookGroup` 的 `idAudio`/`idNetNone`/`idLocalNone`/`idError` 常量保留——它们是 Android `BookGroup` 伴生对象 ID 空间的对照文档（分组 ID 语义保真）。

### 11. 书架/详情/搜索页深度布局对齐（2026-10-24，第四轮）
- **详情页（activity_book_info 同构）**：头部从「左封面右信息卡」重排为 Android 垂直结构——居中 110×160 大封面（圆角 5 + 阴影）→ 居中书名（18sp）→ 居中 kind 标签行 → 竖排图标信息行（作者 / 来源+「换源」accent 小按钮 / 最新章节 / 分组+「设置分组」（confirmationDialog 选组） / 目录 N 章+「查看目录」直达目录列表）；底部操作栏改为 Android `fl_action` 等宽双格——左「放入书架/删除书籍」纯文本 + 右「阅读」accent 实心，平铺无圆角卡；工具栏菜单按 Android `book_info.xml` 顺序重排（编辑/刷新/置顶/换源/变量…）。
- **书架页（main_bookshelf 同构）**：标题「我的书架」→「书架」；菜单顺序对齐——更新目录 → 添加本地 → 分组管理 → 书架布局（视图切换+排序方式子菜单）→ 选择；列表行作者 13sp、最新章节行带 book 图标 12sp（对齐 item_bookshelf_list 层级）。
- **搜索页（activity_book_search 同构）**：标题「聚合搜索」→「搜索」；结果行补齐 Android item_search 的最新章节行与多源角标（源名 · N源，对齐 bv_originCount）。
- **Tab 页标题**：书架/发现/订阅/我的 全部与 `main_bnv.xml` 一致。
- **对齐后修正（用户反馈）**：详情页书名改为完整换行居中显示（去掉单行中部截断）；详情页展示期间隐藏底部 TabBar（iOS 16+ 用 `.toolbar(.hidden, for: .tabBar)`，iOS 15 回退查找窗口内 UITabBar 隐藏），避免底部双按钮操作栏与四个导航 Tab 叠放；搜索历史从 `LazyVGrid` 固定网格改为流式换行胶囊布局（iOS 15 兼容的 alignmentGuide FlowLayout），长按删除保留；详情页容器 `ignoresSafeArea(bottom)` 铺到物理底部、按钮栏净距按设备特征推导（有 Home 指示条设备留 8pt 视觉净距、无指示条设备贴底）——动态读窗口 inset 的方案在 TabBar 隐藏后不可靠（可能含占位且不触发重算），故以设备特征推导替代魔法数字。
- **TabBar 返回透明 bug（用户报告）**：`.toolbar(.hidden, for: .tabBar)` pop 回根页后 SwiftUI 有时不还原背景材质。修复：App 启动时全局为 UITabBar 的 standard/scrollEdge 两种状态显式配置 `configureWithDefaultBackground()` 材质（一处声明，根因修复，非逐页补丁）。
- **详情页 tags 只显示三个（用户报告）**：FlowLayout 的 alignmentGuide 实现中 ZStack 高度按未偏移子帧塌缩，多行内容被裁成一行（且无滚动——用户以为可拖动实则整体被裁）。重写为两阶段确定性排版：子项自报尺寸 → 按容器宽贪心折行 → 显式 position 定位、容器高度取行高之和；搜索历史同组件一并修复。tag 来源增加去重防 ForEach id 冲突。
- **tags 仍只显示三个（用户复测，几何方案在此上下文依旧塌缩）**：放弃一切运行时几何测量，改为**估宽确定性分行**——CJK 15pt/字、ASCII 8pt/字、胶囊附加 30pt，按 330pt 行宽贪心分行后以普通 HStack/VStack 渲染。估宽偏大只会提前换行，永不裁切。搜索历史保留 FlowLayout（其上下文表现正常）。
- **详情页双目录入口（用户反馈）**：移除头部下方的大号「目录」预览卡及其 61 行实现，对齐 Android 仅保留信息行「目录：共 N 章 + 查看目录」入口（直达目录列表）。
- **tags 显示不全的真根因（computer-use 模拟器实测确认）**：渲染层三轮修改均无效——问题在**数据层**。Android `BookInfo.kt` 用 `getStringList(infoRule.kind)?.joinToString(",")` 取全部分类，iOS 误用 `getString()` 只取首个匹配；JSONPath 数组规则（如 `$.keywords`）下 iOS 永远只得一个 tag。已将详情与搜索两处 kind 解析对齐为 `getStringList().joined(",")`，并在模拟器实测通过。tags 行按用户要求回到单行横向滚动（Android LabelsBar 即 HorizontalScrollView 同构）。
- **书架下拉刷新不更新已添加书籍的元数据（用户报告）**：解析修复（getStringList）已在 v0.2.7.3 生效并经活体测试验证——`fetchBookDetail` 返回完整 kind（实测 11 个 tag，断言 `contains(",")` 通过），`saveOrUpdateBook` 本就合并 kind；若设备上刷新后仍为 3 个 tag，请确认安装的是 v0.2.7.3 及以后的 IPA（旧包解析层仍是 getString）。本轮补齐刷新合并清单的两处真实缺口（对齐 Android `upBookInfo`）：① `saveOrUpdateBook` 增加书名/封面合并（书架身份是 bookUrl，改名安全）；② `refreshAllBooks` 将解析出的新章节列表 `saveChapters` 落盘——此前只更新元数据不存目录，阅读器仍读旧目录。
- **v0.2.7.3 发布前全量核对**：① 硬编码扫描——Sources 无任何书源站域名逻辑引用，剩余 URL 均为产品预设（WebDAV 服务商/RSS 预装/字典规则）；② 重复收敛——`<js>`/`@js:` 规则拆分统一为 `JSEngine.splitJSRule`（RuleAnalyzer 两处同构块 + getString 分支 + extractJSScript 复用），`loginHeader ?? header` 替换式取头已全部收敛至 `resolvedSourceHeader`；③ getStringList 语义对齐核对——kind 用列表、name/author/intro 等单值字段保持 getString，与 Android BookInfo.kt/BookList.kt 一致。
- **TabBar 还原延迟（用户报告，返回书架等半秒才出现）**：`.toolbar(.hidden, for: .tabBar)` 的还原绑定在 pop 转场**结束**之后（详情页完全离开层级才收回隐藏偏好），0.35s 转场 + 淡入即感知为半秒延迟。改为 UIKit 层显式显隐（新 `TabBarVisibility` 服务）：详情页 onAppear 隐藏；还原由**每个能推入详情页的来源页**（书架/搜索/发现/分类流）在自己的 onAppear 触发——pop 转场**开始**瞬间 TabBar 即随转场滑回，与原生一致。

### 10. UI 布局对齐与翻页模式修复（2026-10-24，第三轮）
- **翻页模式不记忆（用户报告）**：双重缺陷——`makeStyleConfig()` 保存快照时未写入当前 `pageAnim`，`apply(style:)` 恢复时也未读回，导致每次进入阅读器都回落到滚动模式。修复后 `pageAnim` 随样式快照（对齐 Android `readConfig.json` 的 `pageAnim` 字段）完整往返。
- **「我的」页布局对齐 Android**：iOS 设置中心按 `pref_main.xml` 重排——顶层无分组六行（图标 + 标题 + caption 摘要 + 整行点击），顺序与文案完全一致（书源管理 / TXT 目录规则 / 替换净化 / 字典规则 / 主题模式 NameListPreference → Menu / Web 服务 Switch，运行时摘要显示局域网地址）；「设置」分组（备份与恢复 / 其它设置）；「其它」分组（书签 / 阅读记录 / 关于）。iOS 特有的 WiFi 传书详情页保留为 Web 服务下一行；无对应功能的入口（文件管理 / 退出 / 主题设置子页）省略而非占位。
- **其它设置子页（新）**：收纳 Android `OTHER_CONFIG` 下的 iOS 已有项——正文处理（新书默认净化 / 简繁转换 / 图片样式）、朗读（HttpTTS 引擎）、缓存（清理阅读缓存）。
- **关于子页（新）**：应用名称 / 当前版本 / 内核引擎 / 开源许可。
- **底部 Tab 对齐**：`main_bnv.xml` 四项——书架 / 发现（图标换 safari 指南针，原「分类」）/ 订阅 / 我的（person 图标，原「设置」）；分类页标题同步改「发现」。

### 9. 已实现功能对齐审查（2026-10-24，第二轮）
- **听书翻页续读 bug（用户报告）**：暂停/结束后翻页再点播放，会从旧段落续读而非新页开头。根因：底栏听书、朗读面板、浮动条三个入口都直连 `togglePlayPause()`/`play()`，paused 分支一律 `resume()` 到过期的 `currentIndex`。修复：三入口统一收敛到 `ReaderView.aloudPlayOrResume()`——**可见段落 == 朗读段落且未换章**才 `resume()`（保留 HttpTTS 音频中段进度），否则以 `currentAloudStartPos()` 重新锚定到当前可见段开头（对齐 Android `getNowParagraph` 语义）；`AudioBookService` 新增 `loadedChapterText` 与 `paragraphIndex(containingCharPos:)` 支撑判定，`stop()` 同时清空已载文本。
- **全书搜索跳转偏移基准错位**：命中偏移此前基于**原始缓存文本**计算，而阅读器排版的是净化后文本（去重标题/修剪/缩进均移位），跳转会落偏。修复：搜索改走 `fetchChapterContent(context:)` 同一条净化管线（阅读器经 `processContext` 注入逐章上下文），搜索文本与排版文本同基准；`source: nil` 时仅离线（缓存/本地文件），语义不变。
- **分组视图拖拽排序错乱**：书架/书源/RSS 列表在分组或搜索过滤视图里拖拽时，可见项被重排为 0…n-1，与视图外条目的序号碰撞并打乱「全部」视图。修复：统一改为**置换子集自身既有的序号槽位**（书架 `Book.order`、书源 `customOrder`、RSS `customOrder`），视图外条目保持原位；全量视图时退化为普通 0…n-1 重排。

---

## 四、 后续迭代演进路线图 (Future Roadmap)

当前工程已圆满达成 **P0（核心阅读闭环）** 与 **P1（高频生态与工具链）**，排版底层与连续长卷滚动架构已经终态收敛。后续研发全力推进 **P2（功能对齐）** 与 **P3（平台特性融合）**：

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
- **目标**：将当前基础可用的订阅模块补齐至生产级。
- **实施点**：
  1. ✅ `RssSourceEditSheet` 全字段化：24 字段全量编辑（sourceName/sourceUrl/sourceIcon/sourceGroup/sourceComment/enabled/variableComment/loginUrl/loginUi/header/sortUrl/singleUrl/articleStyle/ruleArticles/ruleNextPage/ruleTitle/rulePubDate/ruleDescription/ruleImage/ruleLink/ruleContent/style/enableJs/loadWithBaseUrl/variable/customOrder）。
  2. ✅ 新建 `RssSourceDebugSheet` 订阅源流式调试台（阶段 1 解析分类 → 阶段 2 文章列表 → 阶段 3 首篇正文，等宽日志实时滚动，标注 ruleNextPage 是否生效）。
  3. ✅ 文章列表支持 3 种版式切换：左文右图（0）、无图模式（1）、双列网格（2）；选择持久化到源的 `articleStyle` 字段。
  4. ✅ 支持基于 `ruleNextPage` 的触底翻页自动拼装（`RssService.fetchArticlePage` 返回 `ArticlePage{articles, nextPageUrl}`，含自环/回源保护与按 link 去重）。
  5. ✅ 文章已读状态置灰标记与阅读历史记录落盘追踪（`RssStore` read-state + 500 条历史，超限裁剪；`RssServiceTests` 10 例覆盖翻页与已读逻辑）。
- **遗留**：交互式登录 WebView 入口（`loginUrl` 已可编辑但无内置登录页）、订阅源并发校验。

#### Part 2：列表拖拽与手动排序 ✅（已完成）
- **目标**：补齐所有管理类列表的长按拖拽交互。
- **实施点**：
  1. ✅ 书架视图：`Book.order` 建模并落盘 `bookshelf.json`（对齐 Android `Book.order`，新书取 `minOrder-1` 置顶）；排序菜单新增「手动排序（可拖拽）」，该模式下列表常驻编辑态出现拖拽把手，`.onMove` 后全量 `order` 重写为 0…n-1（分组过滤视图经 bookUrl 回映射）。网格模式拖拽仍缺（SwiftUI `LazyVGrid` 无 `.onMove`）。
  2. ✅ 书源列表：新增「拖拽排序（优先级）」模式，编辑态拖拽重排后 `customOrder` 重写并按其重排全量数组（换源候选跟随新优先级）。
  3. ✅ TXT 目录规则（重写 `serialNumber`）、字典规则（重写 `sortNumber`）、HttpTTS 引擎与 RSS 订阅源（重写 `customOrder`）四页补齐 `EditButton` + `.onMove` 拖拽排序。

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
- **目标**：对齐 Android `SearchContentActivity`，提供秒级书内全文检索。
- **实施点**：
  1. ✅ 新增 `BookContentSearchService`（LegadoCore）：`AsyncStream` 流式产出 进度/命中/完成 三类事件；`withTaskGroup` 以 6 并发分块抓取，块内按章节序回吐保证结果有序；**缓存优先**（已缓存章节离线可搜），未缓存章节可选拉取（`includeUncached`）；单章命中封顶 3 条防刷屏；命中携带字符偏移与 ±20 字上下文；任务取消安全。
  2. ✅ 新增 `SearchContentSheet`：关键字/正则切换（非法正则前置校验）、含未缓存章节开关、流式进度（x/y 章）、命中列表上下文高亮，点击经 `loadInitialChapter(targetCharPos:)` 精准跳转（翻页模式换算页码、滚动模式定位偏移）。
  3. ✅ 入口：阅读器「搜索」弹窗顶部新增「全书搜索」直达卡片（避免底栏按钮过挤）。
  4. ✅ `BookContentSearchServiceTests` 7 例：关键字/正则匹配、偏移正确性、单章封顶、缓存边界、空查询与非法正则降级。

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
