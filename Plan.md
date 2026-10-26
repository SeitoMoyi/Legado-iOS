# Legado iOS 迁移蓝图、功能差距清单与演进规划

> **复核日期：2026-10-26；当前发布版本：`v0.3.2`（见 [VERSION](VERSION)）；下一开发阶段：`v0.3.3`。**
> - Android 对标本工作区的 `../app/` 与 `../modules/`，不是上游最新版本；Android 快照没有 Git 元数据。`app/` 813 个 Kotlin 文件，连同 `modules/` 共 844 个；`res/layout*` 共 184 个 XML。
> - iOS 是 `ios/` 内的独立 Git 仓库，`v0.3.0` 已推送并发布为 `dd070f2`；v0.3.1 引擎已在 `60c4384` 推送并通过 GitHub 发布；当前分支 `feature/v0.3.2-android-data` 补数据兼容，见下方开发记录。`Sources/` 共 85 个 Swift 文件、31,165 行（Core：41 文件 / 10,322 行；App：44 文件 / 20,843 行）；`Runtime/` 另有 1 个 Swift 适配器文件；含 Tests 共 117 个 Swift 文件。
> - 31 个测试文件声明 404 个测试方法，其中 7 个为 `LiveSourceTests`。本轮以隔离测试目录执行非联网套件，XCTest 报告 **397 项、3 skipped、0 失败**；其中 3 个外部 EPUB / Android ZIP 样本用例因未设置 `LEGADO_TEST_EPUB` / `LEGADO_TEST_BACKUP_ZIP` 而显式 `XCTSkip`，不能视为这些样本已验收。
> - `tools/xcode_add_sources.py --check` 通过。v0.3.1 已接入 App QuickJS 引擎，iOS Simulator 编译通过；独立 iOS 17.2 模拟器原生探针完成 50 次嵌套宿主调用后循环超时 / 恢复及跨线程取消。实际书源详情 / 目录 / 正文冒烟因 book.xkvi.top TLS 连接失败而显式跳过。历史 v0.3.0 / v0.2.8.2 archive 与主题 / 简介 / 标题模拟器验收结果保留在各版本记录；不冒充本轮真机验收。
> - Swift tools 5.7；包声明 iOS 15 / macOS 12 起。依赖 SwiftSoup（HTML DOM / CSS）、ZIPFoundation（EPUB、备份与导出归档）及固定源码 QuickJS（脚本运行时）；XPath 是本项目基于 SwiftSoup 的轻量求值器。

补丁版本到 v0.4.0 的具体顺序与验收见 [ImplementationRoadmap.md](docs/ImplementationRoadmap.md)。

本文件记录源码可确认的迁移状态与待办；[README.md](README.md) 面向使用与开发入门。**字段能导入、能编辑、能导出，不代表对应 Android 行为已经执行。** 下表不再使用没有验收分母的百分比；「主流程已实现」也不表示全部分支与 Android 等价。

## 目录

- [一、当前功能与差距](#current-gaps)
- [二、设计决策与平台偏离](#design-decisions)
- [三、后续迭代与验收条件](#roadmap)

<a id="current-gaps"></a>
## 一、当前功能与差距

### 标记说明

| 标记 | 含义 |
|---|---|
| ✅ | 所述具体能力已有实现；验证范围见基准说明 |
| ⚠️ | 主流程存在，但有兼容性、分支或验收缺口 |
| ❌ | 未找到实现 |
| 🍎 | iOS 平台选择，需与功能缺失分开记录 |

### 功能矩阵

| # | 功能版面 | 已有实现 | 当前缺口 / 边界 |
|---|---|---|---|
| 1 | 应用外壳 / 导航 | ⚠️ 书架、发现、订阅、我的四个固定 Tab；URL Scheme；主屏快捷操作 | 缺 Tab 显隐、默认主页、角标、启动隐私协议与备份密码处理；主屏快捷操作不是 App Intents。 |
| 2 | 书架 | ⚠️ 列表 / 三列网格、5 种排序、列表拖拽、分组新增 / 删除 / 显隐、批量操作、缓存与导出、添加网址、WebDAV 远程文件导入 | v0.3.2 已接入位掩码多组、旧 ID 恢复迁移、重命名与刷新开关；仍缺网格拖拽、独立导入书单 / 日志及原生每组排序行为，`bookSort` 目前仅保留。 |
| 3 | 书籍详情 | ⚠️ 信息编辑、置顶、整书换源、拷贝 URL、分享二维码、目录过滤 / 倒序 / 缓存标识 | 缺 WebDAV 书籍文件上传；编辑简介写 `Book.intro`，不是 Android `customIntro` 的覆盖语义。详情页未提供独立的双向进度同步入口。 |
| 4 | 阅读器 | ⚠️ 统一 CoreText 排版、分页 / 双向连续滚动、图文页、5 个翻页选项（仿真降级）、主题与排版、书签、换源、章节编辑、区间下载、选词、全书搜索 | 滚动模式自动翻页实际为定时切下一章，缺逐屏 / 平滑滚动；章节编辑标题仅保留在会话，重置仅清正文缓存；本地正文现已优先读取编辑缓存。长按与把手等仅有几何单测，仍需真机验收。音量键、亮度、状态栏属于平台选择，见 §二。 |
| 5 | 发现 | ⚠️ 切源胶囊、分类矩阵、JSON / 文本 / JS 分类解析、书籍流分页 | 缺按分组筛选、单源操作菜单、错误堆栈查看；`exploreScreen` 已建模但未接入筛选流程。 |
| 6 | 搜索 | ⚠️ 多源并发流式结果、书名作者聚合、精准排序、范围选择、书架匹配、历史、停止 / 继续 | 缺空结果引导与后台挂起策略；全书搜索按并发批次完成后按章节顺序输出，并非每个网络请求完成即显示。 |
| 7 | RSS | ⚠️ 源管理与编辑、分类、文章列表 / 3 种布局 / 分页、已读记录、正文纯文本、收藏、三阶段调试 | `loginUrl` / `loginUi` 仅可编辑，缺 RSS 登录；`style` / `enableJs` / `loadWithBaseUrl` / `singleUrl` 未接入文章渲染行为；分类仅文本 / URL，缺 JSON / JS 分类；规则解析未传入完整 RSS 源脚本环境。 |
| 8 | 书源管理 | ⚠️ 搜索（含 `group:`）、启用状态筛选、批量操作、5 并发搜索校验、文件 / URL / 剪贴板 / 二维码导入、分享二维码、排序 | 缺逐条选择导入；校验主要验证搜索，不等于 Android 目录 / 正文等完整校验链。扫码直链仅有添加网址 / 复制，未接入规则下载；单对象 / 数组书源导入已统一，未知顶层字段透传。 |
| 9 | 书源编辑 | ⚠️ 基本 / 搜索 / 发现 / 详情 / 目录 / 正文六分区；整源 JSON 拷贝粘贴 | 不是 Android 全字段编辑：例如 `concurrentRate`、`enabledCookieJar` 无独立编辑项；v0.3.0 已加入 jsLib 编辑与执行，`isPay` / `payAction` 等也不完整；缺语法高亮与辅助键盘。若干已展示字段尚未执行，见下表。 |
| 10 | 书源调试 | ⚠️ 搜索 → 详情 → 目录 → 首章正文四阶段日志 | 缺各阶段原始响应查看、WebSocket 实时调试。 |
| 11 | 登录 / 浏览器 | ⚠️ WebKit 网页登录、手动 Cookie、头合并；`SourceLoginSheet` 的简单文本 / 密码表单与脚本执行入口 | 表单已拆 `<js>` / `@js:` 包装并拒绝脚本错误 / 未返回新凭据的登录；仍忽略 RowUi 按钮，未执行 `loginCheckJs`。登录浏览器已有前进 / 后退 / 刷新，缺通用浏览器入口、验证页自动重试与下载管理。 |
| 12 | 我的 / 设置 | ⚠️ 对齐 `pref_main.xml` 的主要分区；备份、规则、主题、其它设置、书签与记录 | 布局接近不代表所有 Android 设置键都有行为；缺帮助文档站、私有文件管理等。 |
| 13 | 规则管理 | ⚠️ 替换、TXT 目录、字典、HttpTTS 四类 CRUD / 导入导出 / 排序；替换规则扫码导入 | v0.3.2 已加入 HttpTTS 与字典 ZIP / WebDAV 备份；正则已通过进度回调中止超时匹配；JS 规则由 QuickJS 中断，超时返回并禁用规则；原生操作的严格墙钟保证不作承诺。 |
| 14 | 备份 / 数据互通 | ⚠️ WebDAV 与本地 ZIP；13 个已支持文件名、独立远端进度、书签汇总与导出 | Android 有 21 个候选备份成员；仍缺 8 个，且现有成员也有形态与合并语义差异。详见备份表，不能称为完整跨端互通。 |
| 15 | 局域网 / 平台集成 | ⚠️ `Network.framework` 上传门户、TXT / EPUB 入库、`legado://` / `yuedu://`、主屏快捷操作 | 缺 Android REST / WebSocket 服务、Widgets、App Intents、Share Extension、CarPlay；iOS 后台持续服务需单独评估。 |
| 16 | 规则与网络引擎 | ⚠️ CSS、部分 JSONPath / XPath、正则清洗、JS / 模板、变量、URL `method` / `headers` / `body` / `charset` / `retry` | JSONPath 递归查找取首个匹配，未实现完整过滤 / 切片；XPath 为子集。v0.3.0 支持书源 jsLib 内联与 JSON URL 映射；仍缺并发率 / CookieJar 开关语义、WebView 请求及 AES / RSA / HMAC 桥接；charset 已用于字符串请求体编码与响应解码，JSON 请求体仍按 UTF-8 编码。 |
| 17 | 本地格式 | ⚠️ TXT 编码探测 / 规则切章；EPUB3 nav、EPUB2 NCX、spine 兜底、图片与锚点片段提取 | Android 支持 TXT / EPUB / UMD / PDF / MOBI / AZW3；iOS 缺后四种。编码检测是启发式，不能保证所有文件无乱码。 |
| 18 | 朗读 / 有声书 | ⚠️ 系统 TTS、HttpTTS、朗读面板 / 悬浮条、锁屏命令；音频书独立 AVPlayer 页面 | 滚动朗读已有段落高亮，缺自动跟随居中；后台、耳机与不同服务端音频格式需设备验收。v0.3.2 已消费 Android `Book.type` 的本地 / 音频 / 临时书籍位，兼读旧 kind 标签；漫画类型仍无专门界面。 |

### 影响书源兼容性的具体未接入项

| 字段 / 行为 | 源码可确认的边界 | 依据 |
|---|---|---|
| `ruleBookInfo.init` 与详情 → 目录 | 本次已修复 Android `init` 键映射（兼读旧 iOS `initRule`），执行详情根节点预处理、name / author / intro / kind / wordCount / coverUrl / lastChapter / tocUrl，并按规则请求独立目录。仍未消费 updateTime。站点专用 JSON 元数据猜测与章节 API 路径重写已删除。 | [RuleModels.swift](Sources/LegadoCore/Models/RuleModels.swift)、[BookContentService.swift](Sources/LegadoCore/Service/BookContentService.swift) |
| 目录钩子与标记 | `formatJs` 已在跨页合并、去重、反转和重新编号后执行，提供共享 `gInt`、1 起算 `index`、`chapter` 与 `title`；异常 / null / undefined 保留原标题。目录已求值 `isVolume` / `isVip` / `isPay` / `updateTime`（写入 `tag`），无链接分卷用稳定的合成 URL 保留并直接读取 tag，不请求网络。v0.3.0 已接入显式刷新时的 `preUpdateJs` 与 `refreshTocUrl` / `reGetBook`；初次详情请求默认不执行。章节脚本对象仅提供当前已建模字段，不等价完整 Android Chapter 桥。 | [BookContentService.swift](Sources/LegadoCore/Service/BookContentService.swift) 的 `parseChapters` |
| WebView / 解密 / 付费规则 | `coverDecodeJs`、`webJs`、`sourceRegex`、`imageDecode`、`payAction` 等未进入对应执行链；源级 `replaceRegex` 仅支持正则替换对，不能按 Android 完整规则 / JS 求值。 | [EditSourceSheet.swift](Sources/LegadoApp/Views/EditSourceSheet.swift)、[BookContentService.swift](Sources/LegadoCore/Service/BookContentService.swift) |
| JSON 往返 | `BookSource` / `RssSource` / `Book` 的未知顶层键仍须通过 extras 感知解码保留。五类书源嵌套规则（搜索 / 发现 / 详情 / 目录 / 正文）现在直接在 Codable 解码时保留未知键，支持对象及 JSON 字符串规则，编辑 / 持久化 / ZIP 往返已覆盖。已知键类型不兼容、其它嵌套对象不受此保证。`Book.order` 已是正式属性。 | [JSONValue.swift](Sources/LegadoCore/Utils/JSONValue.swift)、[JSONExtrasTests.swift](Tests/LegadoCoreTests/JSONExtrasTests.swift) |
| 表单登录 | 简单表单、脚本包装拆分和错误检测已有实现；RowUi 按钮与登录校验尚未对齐。 | [SourceManagerView.swift](Sources/LegadoApp/Views/SourceManagerView.swift)、[BookStore.swift](Sources/LegadoApp/Services/BookStore.swift) 的 `performLogin` |

### 备份成员与语义

对照 Android [Backup.kt](../app/src/main/java/io/legado/app/help/storage/Backup.kt)、[Restore.kt](../app/src/main/java/io/legado/app/help/storage/Restore.kt)、[ReadBookConfig.kt](../app/src/main/java/io/legado/app/help/config/ReadBookConfig.kt) 与 iOS [WebDAVService.swift](Sources/LegadoCore/Service/WebDAVService.swift)、[BookStore.swift](Sources/LegadoApp/Services/BookStore.swift)：

| 范围 | 当前实现与差异 |
|---|---|
| 已支持的 13 个文件名 | `bookshelf.json`、`bookSource.json`、`bookmark.json`、`replaceRule.json`、`searchHistory.json`、`readConfig.json`、`txtTocRule.json`、`readRecord.json`、`rssSources.json`、`rssStar.json`、`bookGroup.json`、`dictRule.json`、`httpTTS.json`。书架与书源始终写入；其它项按有无数据 / 已存样式决定，不保证每包固定十三项。系统朗读选项不冒充 Android HttpTTS 数据行，iOS 的 -6 虚拟分组不导出。 |
| 阅读样式形态 | Android `readConfig.json` 是样式数组；iOS 本次已改为导出单元素数组，仍兼读旧版单对象；恢复数组时仅取第一项，尚未保留 / 管理全部样式。`ReaderPrefs`、自定义主题等也未整体写入 ZIP。 |
| 缺少的 8 个成员 | `sourceSub.json`、`servers.json`、`keyboardAssists.json`、`directLinkUploadRule.json`、`shareReadConfig.json`、`themeConfig.json`、`coverRule.json`、`config.xml`。部分 Android 成员可能按配置不存在；21 是候选清单，不是每包固定数量。 |
| 分组 | 已按 Android 位掩码匹配；旧时间戳 ID 以恢复快照迁移，保留进度 / 分组元数据。恢复外部备份时按名称 / 可用位映射冲突，保留本地组；只改恢复书籍的成员位。旧 iOS 包缺分组定义时只能使用已有映射或占位组，无法恢复原本不存在的组名；每组排序尚未执行。 |
| 书籍与阅读记录 | Android `Book.readConfig` 在 iOS 只作为顶层 extra 保留，iOS 的 `useReplaceRule` 为另一个顶层键，运行语义未映射。阅读记录现已按 Android 主键 `deviceId + bookName` 合并 max，避免混合不同设备记录。 |
| 进度 | `createBackupZip` **不生成** `bookProgress/`；进度字段在 `bookshelf.json` 中，独立进度文件通过远端 PUT / GET 同步。恢复支持 ZIP 内、邻接目录或远端目录的进度文件。本次已统一为优先比较阅读时间，缺时间或时间相同再比较章节 / 位置；不再以目录检查时间 `lastCheckTime` 判定阅读进度。恢复保留更新的本地进度，手动拉取不再把远端时间改写为当前时间。 |
| 本地文件与缓存 | ZIP 不含 TXT / EPUB 原文件、解包资源、目录与正文缓存。恢复书架条目不等于恢复本地书籍可读内容；设备路径不可跨端直接使用。 |
| 未识别成员 | 恢复只提取已支持成员，其余不会存储并在下一次 iOS 备份中重新打包；不能保证 Android → iOS → Android 的完整备份往返。 |

<a id="design-decisions"></a>
## 二、设计决策与平台偏离

保留编号，供代码注释与历史任务引用。平台选择与待修问题分别说明，避免把实现限制写成已经解决。

| # | 机制项 | iOS 处理与边界 |
|---|---|---|
| **1** | 仿真翻页 | 当前降级为滑动；这是产品实现选择，不意味着 iOS 无法实现卷页动画。 |
| **2** | 简繁转换 | 系统 `CFStringTransform`，不带 OpenCC 词库；与 Android OpenCC / `fixT2sDict()` 不等价，词组及多义字输出也可能随系统变化。 |
| **3** | 重新分段 | 当前不实现 Android `reSegment`，保留原始换行并做确定性修剪。Android 算法使用随机断句；随机性不意味着绝对无法测试或缓存。 |
| **4** | 正则超时 | 本次改为一次性回调竞争超时 / 取消 / 完成，调用者不再等待同步子任务；正文 / 标题统一禁用回调，正则通过进度回调检查截止时间并停止。运行时超时上限 60s；v0.3.1 将 App 脚本切换为 QuickJS，循环和原生回溯正则可由中断回调停止，网络宿主等待可取消；仍非进程隔离或所有原生操作的严格墙钟保证。 |
| **5** | 离线正文 | 网络缓存保存源级清洗后、全局 `ContentProcessor` 净化前的文本；不是原始 HTTP / HTML。读取时再执行用户净化。手动编辑正文会覆盖该缓存。 |
| **6** | 分页限制 | 目录串行续页最多 200 次 / 120s 检查预算，正文总计最多 50 页 / 30s。多 URL 分支共用剩余页数 / 时间预算，最多 8 并发，去重并传播失败，正文跳过下一章及其后链接；不完整结果不进入完整正文缓存，旧目录 API 对不完整结果抛错。预算仍在请求之间检查，不是严格网络整体 deadline。 |
| **7** | 音量键 | 当前不提供音量键翻页，保持系统音量行为。属于 iOS 产品选择，不推断所有实现均会压低系统音量。 |
| **8** | 亮度 | 当前不提供应用内亮度调节，使用系统控制中心。属于产品选择。 |
| **9** | 系统状态栏 | 阅读器固定显示系统状态栏，颜色随主题；不等于 Android 所有沉浸设置已对齐。模型中的 `hideStatusBar` 仍存在，但阅读器固定 `.statusBar(hidden: false)`。 |
| **10** | 两端对齐 | 分页与连续滚动画布共享 CoreText 排版，支持两端对齐。 |
| **11** | 书源分组噪声 | 仅显示层过滤校验判定词与第三方 `good` 标记，存储保留原分组。 |
| **12** | 响应耗时 | 只展示 `0 < ms < 180000` 的测量值，隐藏 Android 失败罚时标记。 |
| **13** | 换源章节映射 | 使用 `ChapterMatcher` 自动匹配；有单元测试，但存在目录歧义时仍可能匹配不准。 |
| **14** | 阅读面板 | `ReaderPanelChrome` 统一样式与高度限制。 |
| **15** | JSON 字段透传 | `BookSource` / `RssSource` / `Book` 通过 extras 感知解码保留未知顶层键，encode 扁平回写。五类嵌套书源规则也已保留未知键；定向测试覆盖编辑、持久化与备份往返。不保证所有字段、其它嵌套对象和解码调用零丢失，也不代表透传字段已执行。 |
| **16** | 请求头合并 | `JSEngine.resolvedSourceHeader` 求值静态 header 后叠加 loginHeader。 |
| **17** | `getLoginHeader()` | 只返回捕获的登录头，不回退静态 header，供脚本判断登录态。 |
| **18** | `java.ajax/connect` | 通过 `JavaShim.defaultHeaderProvider` 带书源头；Java 桥仅实现部分 Android API。 |
| **19** | JS 规则拆分 | 规则引擎使用 `splitJSRule` / `extractJSScript`；表单登录也已接入拆分。列表字段用 `getStringList`，单值字段用 `getString`。 |
| **20** | JSON 编解码调用约束 | 补充 #15：新增导入 / 恢复 / 持久化路径须用 extras 感知解码；五类书源规则直接使用其 Codable 保真实现；新增其它嵌套对象须单独处理。 |
| **21** | 分页记账 | 段距挂下一段首行、页首不收、跨页重置；`TypographyPageFillTests` 覆盖相关不变量。 |
| **22** | 过滤后拖拽 | 先稳定规范化缺失 / 重复序号，再置换可见条目的槽位；隐藏条目的相对位置保持。 |
| **23** | 详情页 TabBar | 使用 `TabBarVisibility` 与全局 Appearance，来源页恢复显示。 |
| **24** | 听书启动 / 续读 | 统一 `aloudPlayOrResume()`；可见段与朗读段一致才 resume，否则重锚定。 |
| **25** | 全书搜索基准 | 阅读器传入 `ProcessContext`，让搜索使用同一净化管线与 UTF-16 字符偏移；`source: nil` 限离线。服务调用不传 context 时无此同排版文本保证。 |

<a id="roadmap"></a>
## 三、后续迭代与验收条件

以下为建议优先级与版本目标，不是发布日期承诺。`v0.2.8` 已有的功能保留为完成记录；兼容性与数据缺口先于新格式和平台扩展。

### v0.3.0 发布范围：书源运行时基础（2026-10-26）

- `v0.3.0` 的范围为 jsLib、preUpdateJs 基础链、阅读器回归修复与执行中断技术调查；不是整个 v0.3.x 路线图。`VERSION` / Xcode 版本为 `0.3.0`，build 3。
- `BookSource.jsLib` 已建模并可编辑：内联脚本或按声明顺序加载 HTTP(S) 库映射，缓存文本、隔离每个引擎的可变全局；库下载关闭 Cookie 处理且不附加源登录头。失败在主服务请求前报告。缓存与大小限制的边界见 [SourceRuntime.md](docs/SourceRuntime.md)。
- 阅读器更新目录、书架更新和详情页显式刷新已执行 `preUpdateJs`；支持 `java.refreshTocUrl()`、按书名 / 作者精确匹配的 `java.reGetBook()`、直接修改 book URL 和跨目录阶段的 book 变量。辅助方法在钩子以外会报错。
- URL 迁移替换原书架位置并保留最新阅读进度 / 分组 / 顺序；已删除书籍不复活，目的 URL 冲突先报错再退出，避免覆盖其它书籍的缓存。原生网络等待可取消；钩子在线程池执行，不阻塞 UI 执行器。
- **执行中断调查**：未使用 JavaScriptCore 私有超时 API。独立 QuickJS 原型完成 50/50 循环中断、后续表达式恢复和显式资源释放，核心 C 文件可交叉编译 iOS arm64。QuickJS 尚未链接进 App，不能宣称已实现 JS 硬中断；运行中的纯 JS 死循环仍未解决；硬中断接入列入 v0.3.1，完成前不宣称运行时隔离，详见 [原型说明](tools/runtime_probe/README.md)。
- 运行时新增 16 个回归用例，阅读器加载会话另新增 5 个；当前非联网套件 **363 项、3 skipped、0 失败**，iOS Simulator 编译与工程源文件登记检查通过。库 / 钩子样本以确定性网络桩验证，尚无真机或真实依赖库书源验收。

### 首次加载退出阅读器修复（2026-10-26，v0.3.0）

- 阅读器以会话持有首次目录 / 正文、滚动请求、目录刷新与相邻章预取任务；退出立即取消会话和网络请求。取消或已被新请求替换的结果不再写入阅读器状态、更新进度或启动后续预取。
- 磁盘预取改为调用方持有的异步任务，取消同时停止当前请求与剩余章节队列。加载占位页直接显示「返回书架」，无需等待正文或先展开菜单；关闭只走父级回调或环境 dismiss 中的一条路径。
- 新增 4 个确定性回归测试，覆盖首章未缓存时退出 / 再打开、滚动加载与预取取消、不响应取消的晚到结果及快速切章。当前非联网套件 **363 项、3 skipped、0 失败**，iOS Simulator 编译通过。本轮没有运行中的模拟器，未做实际点击退出验收。

### v0.3.0 范围复核与代码审查（2026-10-26）

经用户澄清，按补丁版本逐步推进：**v0.3.0 完成书源运行时第一阶段、执行中断调查与已报告阅读器问题修复**。前次把整个 v0.3.x 和下一阶段硬中断接入都纳入 v0.3.0 门禁的描述予以纠正。v0.3.1 接入可中断运行时；浏览器 / 登录、备份互通、规则订阅及 RSS / 书架补齐继续按下方优先级推进。v0.3.0 保留 JavaScriptCore 的已知死循环限制，不宣称脚本隔离已完成。

- 修复 book 变量删除 / 清空后 `java.get` 回退旧本地值的问题；有书籍上下文时以其变量表为准。
- 换源或目录重排时取消旧请求，防止旧源正文和预取回写新缓存；退出后忽略滚动画布进度回调，并在自动换源的异步边界重新检查取消。
- 删除退出与消失回调的重复进度保存；钩子取消状态与完成结果在同一锁内提交，避免取消后仍赢得成功回调。
- 新增 2 个回归用例；非联网套件 363 项、3 skipped、0 失败。审查范围为本分支变更及其直接调用链，不代表对整个迁移项目的无缺陷保证。未发现新增生产站点专用 URL 分支；有意保留兼容桥及已说明的运行时限制。

### v0.3.1 实施顺序（已完成接入）

1. 原生运行时适配器：固定 QuickJS 来源 / 许可，接入公开中断、内存 / 栈限制、取消信号、资源释放；先保持现有 App 引擎路径，独立测试适配器。
2. 分批迁移已有 Java / source / book 桥与规则调用，避免替换引擎时丢失原有书源能力；库加载与主机网络调用单独限制。
3. 覆盖循环、递归、分配、取消与后续正常求值，验证 iOS 编译 / 运行及代表书源。只有完成接入验收后才宣称 App 支持硬中断，并发布 v0.3.1。

### v0.3.1 第一步记录：独立可中断适配器（2026-10-26，历史检查点）

- 新增独立 SwiftPM 产品 `LegadoRuntime` 与 C 封装，固定 QuickJS 2026-06-04 官方源码 / SHA-256；保留 MIT 许可。15 个 vendor 源码 / 头文件与上游逐字节一致，未包含 OS / shell 模块及编译产物。见 [来源与边界](Runtime/UPSTREAM.md)。
- 原生适配器支持单调时钟执行预算、原子取消、堆 / 栈 / 输入 / 输出限制、JSON 求值边界及显式资源释放；同一运行时串行使用，可在不同工作线程之间迁移。
- 新增 7 个测试：50 次循环中断 / 恢复、执行前及跨线程取消、递归 / 分配失败、JSON 序列化和异常字符串转换超时、输入输出边界、上下文隔离及 50 次释放检查。完整非联网套件 **370 项、3 skipped、0 失败**。
- 六个 C 源文件和 Swift 适配器均已交叉编译 iOS 15 arm64 设备 / 模拟器；这不是 iOS 实机运行验收。App 尚未依赖该产品，VERSION 仍为已发布的 v0.3.0；v0.3.1 未完成、未发布。
- 下一步是上述第 2 步：迁移现有 Java / source / book 桥及规则调用，再做 iOS 运行与代表书源验收。当前适配器无宿主网络、模块加载和 Promise job pump；等待运行时锁的时间不计入脚本执行预算，复杂原生操作仍需单独验证。

### v0.3.1 发布记录：App 引擎与宿主桥接入（2026-10-26）

- SwiftPM Core 和 Xcode App 现在都编译 QuickJS；移除 JavaScriptCore API 依赖。保留既有 java、source、book 方法和读写变量、HTTP 响应方法、头部脚本嵌套调用及目录格式化上下文；不是完整 Android Java 对象体系。
- 每次求值带执行预算 / 取消检查；嵌套宿主求值共享外层期限并恢复中断处理器，限制嵌套深度。HTTP / jsLib 等待检查取消；正文净化超时不再留下死循环 VM。目录格式化超时终止当前格式化任务，不逐章重复卡住。
- 分类脚本改用非 UI actor 异步入口，切源取消旧任务；解析错误不再报告成「连接正常」。修复迁移中的 Boolean 字符串差异，已有 source / header / login / rule 回归保持通过。
- 非联网套件 **377 项、3 skipped、0 失败**；iOS Simulator 编译及原生探针通过。探针覆盖 50 次嵌套宿主调用后的超时 / 恢复、跨线程取消和释放；Swift 测试另覆盖递归、分配、原生正则回溯、序列化 / 异常转换中断及工作池恢复。
- 实际书源冒烟因远端 TLS 失败跳过；未把跳过视为通过。复杂原生运算、OS 调度与等待同一运行时锁仍不提供严格实时保证；Promise job pump / 模块系统及其余 Android 桥未实现，详见运行时说明。

### v0.3.2 发布记录：Android 分组与补充备份（2026-10-26）

- 自定义分组改为单一位 ID / 多组成员掩码；旧时间戳编号和书籍绑定以完整快照迁移，中断后恢复，超过 63 组时保留原数据和旧过滤，删除多余组后可继续迁移。删除组清除对应位，并保留旧 ID 墓碑防止旧备份错误绑定复用的新组。
- 书架 / 详情均可多选分组、重命名；尊重分组顺序与下拉刷新开关。恢复时重映射其它设备的冲突位，不改动原有书籍分组；保存原生同名组和未来字段。原生 type 位用于本地 / 音频 / 临时书籍 / 更新失败筛选。
- 增加 bookGroup / dictRule / httpTTS 三类成员，ZIP 和散文件 WebDAV 共用解码链；仅这三类的备份也能识别。普通 Codable 仍保留新增模型的未知字段。损坏的最新 ZIP 不再偷偷回退另一个散文件快照。
- HTTP 朗读按稳定 ID 选择，重名端点不再选错；系统朗读为独立虚拟选项，不进入 HTTP 数据库 / 导出，移除固定 id=1 的删除特例。空字典 / HTTP 规则列表不再自动复活默认项。
- 新增 20 个回归方法；完整非联网套件 **397 项、3 skipped、0 失败**。模拟器编译通过；未声称真实 Android 安装往返、真机手势 / 音频后台已验收。当前备份仍缺其它 8 个成员、全部样式 / 偏好和书籍文件，下一步 v0.3.3 处理保真与订阅。

### v0.2.8.2 发布范围

本版本收录目录规则与嵌套字段保真、正文净化 / 网络 / 备份审计修复，以及自定义主题首开、简介 JS 和标题二次换行回归修复。342 项非联网测试（3 skipped、0 失败）、iOS Simulator 编译与未签名 iOS Release archive 通过（应用版本 0.2.8.2 / build 2），实际机翻机器人书源与第 63 话已在 iPhone 11 / iOS 15.5 模拟器验收。`preUpdateJs`、`jsLib`、JS 硬中断与 v0.3.x 数据互通 / 浏览器任务继续保留为待办。

### 已实现记录（v0.2.8 系列）

- **Part 4 文本选词**：双画布长按、拖拽与把手、复制 / 字典 / 书签 / 朗读 / 替换规则菜单已接入；几何单测通过，真实设备操作待验收。
- **书架二级菜单**：缓存管理、全书 / 全架下载、TXT / EPUB 缓存导出、导出书单、添加网址、WebDAV 远程导入、分组显隐已有实现。导出仅含已缓存的未净化文本，未缓存章节跳过；EPUB 不嵌入图片。Android 的导入书单 / 日志入口仍缺，不能标为 `main_bookshelf.xml` 全量完成。
- **Part 3 二维码**：相机 / 相册识别、部分载荷导入、书源 / 书籍二维码生成已接入。扫码规则直链下载未接入；单对象书源与扫码 RSS 字段保真已在本次修复。书籍二维码为详情 URL，不能视为包含书籍文件的跨端迁移；相机权限与相册保存需设备验收。

### 简介脚本与标题二次换行修复（2026-10-26，v0.2.8.2）

- 修复 JS 规则包含 `{{...}}` 时只替换模板、却把整段 JS 作为字符串返回的问题。标量 / 列表 / 元素规则均先插值脚本体再执行；详情 `init` 返回 JSON / HTML 字符串时也可作为新的解析根节点。
- 分页标题改为直接绘制统一排版引擎已测量的行，与测量 / 滚动标题共用 CoreText Semibold 字体、字距与行高，避免 SwiftUI 使用不同字体对预切行再次换行。页首标题高度按同一排版模型记账；绘制范围按 UTF-16 长度覆盖全部字符。
- 新增 6 个回归测试，覆盖含模板的简介 JS、列表规则、字符串详情根、执行异常、完整详情链，以及第 63 话标题实际位图只有两行。
- 本轮全套非联网测试 **342 项、3 skipped、0 失败**，Simulator 构建通过；在用户 iPhone 11 / iOS 15.5 模拟器的实际书源与书籍上确认简介显示文字、标题两行。更新安装保留原数据，验收后停留原第 63 话。

### 阅读主题首开修复（2026-10-26，v0.2.8.2）

- 修复正文使用自定义色、标题 / 阅读面板却使用主题固定色的不一致；所有阅读文字与控件改为使用同一有效调色板。
- 颜色解析严格拒绝部分十六进制输入，兼容 `#RGB` / `#RRGGBB` / Android `#AARRGGBB`。无效颜色使用可读默认配色，透明或与背景完全重合的文字使用黑 / 白恢复显示；原始编辑值保留，不抹除导入配置。
- 恢复预设主题时同时匹配背景与文字色；显式自定义主题保持自定义。主题和阅读偏好合并落盘，避免偏好修改取消尚未写入的主题。
- 滚动画布直接观察阅读配置，在创建时先应用恢复的颜色 / 排版，再安装首章。
- 新增 8 个回归测试，覆盖干净安装、冷启动颜色恢复、透明 / 同色 / 无效输入、主题与偏好落盘及正文首帧位图渲染；全套非联网测试 336 项、3 skipped、0 失败。iOS Simulator 编译与上述两个首开交互样本通过；未验证用户真机上的原始书源 / 配置。

### 本轮目录规则兼容实现（2026-10-26，v0.2.8.2）

- 五类书源嵌套规则保留未知 JSON 键（包括 null / 数组 / 对象），已知字段编辑优先；兼读详情 `initRule`，导出只写 Android `init`。
- 网络目录执行分卷 / VIP / 已购买 / 更新时间规则；保持无链接卷名；`formatJs` 在完整目录规范化后执行，按 Android 顺序共享计数器。旧目录缓存兼容；仅元数据变化也会更新阅读器，保留仍有效的正文缓存。
- 修复 HTML 节点直接传入 JavaScriptCore 的 `copyWithZone` 崩溃，节点及节点列表转为 HTML 字符串；这不是完整 Android DOM 桥。
- 新增 17 个固定样本回归用例，覆盖跨页格式化顺序、脚本异常、章节上下文、旧缓存与嵌套规则备份往返；3 个外部样本测试改为显式 skipped。
- **边界**：`preUpdateJs`、`jsLib`、详情 updateTime 和 JS 硬中断尚未实现。`formatJs` 的取消只在章节间检查，不能停止已经开始的死循环脚本；不将本轮描述为执行隔离完成。

### 本次代码审计已修复（v0.2.8.2）

- 删除站点专用章节 URL 重写与 JSON 元数据猜测，改为使用书源详情规则；修复 `init` 键与独立目录请求。
- 统一分页并发代码、限制总页数、传播 HTTP / 分片失败、去重并停止跨章续页；取消传播至搜索及网络重试。
- 修复相对 URL、带逗号 URL 的选项解析、大小写不敏感的头覆盖、字符串 POST 编码、同步超时请求取消；复用 User-Agent 与 JS 响应包装，补齐 `java.post` 书源头与相对地址。
- 修复可选字段在宽容解码中丢失、扫码 RSS extras 丢失、单对象书源导入、同名不同 URL 书源互相覆盖、重复书签 ID 导致恢复崩溃、导入序号重复 / 缺失导致排序失效。
- 修复多条删除索引漂移；批量书架更新在主线程提交状态并跳过刷新期间已删除的书籍；章节缓存与净化结果字典加锁。
- 修复正则超时等待、标题规则重复执行、标题规则缺少禁用回调；仍需 JS 执行隔离。
- 修复阅读样式导出形态、RSS 单独备份包误判、指定备份不存在时错读其它快照、解包错误被吞、WebDAV 失败状态被报告成功；统一进度冲突与多设备阅读记录合并。
- 移除重复 return、重复注释与未使用的视图 / 状态 / URL 方法；SPM 排除由 Xcode 管理的图标资源以消除构建警告。新增回归测试见 `Tests/LegadoAppTests/BookStoreTests.swift` 及核心测试扩展。

### 仍需优先完善

| 优先项 | 建议验收条件 |
|---|---|
| 规则钩子与字段保真 | v0.3.0 已实现 jsLib 与 preUpdateJs 的基础链路；继续补完整脚本上下文 / 搜索变量合并、详情 updateTime，并扩大 Android 对照样本。 |
| JS 执行隔离 | v0.3.1 已接入现有宿主桥并完成循环 / 正则中断、取消与 iOS 原生探针；后续覆盖其余 Android 桥和原生计算边界，不宣称进程级隔离。 |
| 分组兼容 | v0.3.2 已迁移 / 合并位掩码与定义；后续补每组排序及大规模 / 真机交互验收。 |
| 数据互通验收 | 用真实 Android ZIP 与 EPUB 样本验证往返；补全部样式 / 偏好 / 剩余备份成员。 |

### 第二批（目标 v0.3.x）：生态与数据完整性

#### Part 6：浏览器与登录链

复用现有登录 WebKit 的前进 / 后退 / 刷新能力，增加通用浏览器入口、URL 操作与下载；补 RowUi 按钮、`loginCheckJs`、RSS 登录及 WebView 请求分支。验证页处理与 Cookie 回写后重试需通过明确样本验收，不能承诺所有站点都能通过验证。

#### Part 8：备份成员与语义对齐

补齐上表剩余 8 个缺少成员，并修复已有成员的形态与合并逻辑：样式数组 / 当前样式选择、`ReaderPrefs`、`Book.readConfig`、位掩码分组、未知成员保留及恢复忽略列表。用真实 Android 包完成 Android → iOS → Android 双向验收；iOS 自身 create / restore 测试只能作为基础。明确区分元数据备份与 TXT / EPUB 文件迁移。

#### Part 7：规则订阅 `sourceSub.json`

实现外部规则订阅管理、更新检查与合并策略。定期更新需结合 iOS 后台调度限制设计；分别验证书源 / 替换规则 / RSS 更新和用户本地修改冲突。

#### RSS 与书架补齐

补扫码规则直链；补 RSS JSON / JS 分类、源脚本上下文、`singleUrl` / 样式 / JS 渲染；补书架导入书单 / 日志；缓存导出明确缺章，并补 EPUB 图片资源打包。

### 第三批（目标 v0.4.x）：格式与体验

- **Part 9 本地格式**：MOBI / AZW3 / UMD / PDF 分别评估；PDF 以页面渲染为主，不预设都能走文本重排。实现方式与依赖选择待技术验证。
- **Part 10 主题与背景**：命名主题、导入导出、背景图片 / 纹理与 E-Ink 对比度；处理 Android 路径映射。
- **Part 11 漫画**：专用图片分页、缩放与贴靠；现有正文插图不等于漫画交互已完成。
- **阅读体验**：连续滚动自动翻页、朗读跟随滚动、章节编辑持久化 / 本地文件覆盖、无障碍与选词真机回归。

### 第四批（目标 v1.0）：平台扩展

- **Widgets / App Intents / Share Extension**：书架与进度展示、搜索 / 继续阅读、系统分享导入。
- **VoiceOver / CarPlay**：画布和控制无障碍、听书模板；分别制定设备验收清单。
- **局域网 API**：对齐本快照 [HttpServer.kt](../app/src/main/java/io/legado/app/web/HttpServer.kt) 的 12 GET / 14 POST 路由及相关 WebSocket 调试能力；后台可用性单独按 iOS 生命周期评估。
