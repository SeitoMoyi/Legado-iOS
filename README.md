# Legado iOS (开源阅读 iOS 版)

[![Platform](https://img.shields.io/badge/Platform-iOS%2015.0%2B-blue.svg)](https://developer.apple.com/ios/)
[![Swift](https://img.shields.io/badge/Swift_tools-5.7%2B-orange.svg)](https://swift.org)
[![Xcode](https://img.shields.io/badge/Xcode-14.0%2B-blue.svg)](https://developer.apple.com/xcode/)
[![License](https://img.shields.io/badge/License-GPLv3-lightgrey.svg)](LICENSE)

> **Legado iOS** 是使用 **SwiftUI** 与 **Swift** 构建的开源阅读器，正在迁移 Android **Legado（开源阅读 3.x）** 的书源、阅读与同步能力。第三方 SPM 依赖为 SwiftSoup（HTML DOM / CSS）与 ZIPFoundation（EPUB、备份与导出归档）；XPath 是本项目在 SwiftSoup 上实现的轻量子集。当前支持常用书源主流程，尚未实现全部 Android 规则与备份语义。

> **当前状态（2026-10-26）**：发布版本 `v0.3.2`，以 [VERSION](VERSION) 为准；App 已接入可中断 QuickJS 与既有宿主桥；已接入 Android 多组成员、迁移和 13 类备份；下一步补其余成员保真、样式 / 偏好与订阅。完整差距、源码依据与待办见 [Plan.md](Plan.md)。下文「可编辑 / 可透传」不等于对应规则已执行；本次 macOS SPM 测试与 iOS Simulator 编译通过，未做真机交互验收。

---

## 🌟 核心功能特性

### 1. Legado 3.0 常用书源与管理
- **多语法规则引擎**：支持 CSS 选择器、部分 JSONPath（如 `$.data[*]`，递归查找取首个匹配）、轻量 XPath（`//`, `/`, `|`, `[@attr]`, `[contains()]`, `[last()]`）、正则清洗、JavaScript（`<js>` / `@js:`）与模板变量（`{{key}}`, `{{page}}`）。v0.3.0 支持书源 `jsLib` 内联 / 按序 URL 库与刷新前钩子；仍缺完整 JSONPath / XPath、部分 Java 桥与 WebView 请求能力，详见 `Plan.md`。
- **6-Tab 书源编辑器**：提供 基本 / 搜索 / 发现 / 详情 / 目录 / 正文 6 大分区常用字段编辑，支持整源 JSON 拷贝与粘贴。尚非 Android 全字段覆盖，部分已展示字段也未接入执行链。
- **四阶段实时调试台 (`SourceDebugSheet`)**：输入测试关键字即可实时流式执行「1. 搜索列表 → 2. 书籍详情 → 3. 目录解析 → 4. 首章正文」全链路调试，精确显示各阶段网络耗时与解析字段。
- **书源管理与并发校验**：
  - 实时名称、域名、注释过滤，支持 `group:分组名` 语法。
  - 「全部 / 已启用 / 已禁用」三态分组胶囊栏。
  - 右上角多选模式：支持批量启用、禁用、全选、反选、导出 JSON 及批量删除。
  - 拖拽排序模式：长按把手重排书源，`customOrder` 重写为 0…n-1，换源候选按新优先级排列（对齐 Android 书源优先级语义）。
  - 5 并发搜索有效性校验（未覆盖 Android 全部校验阶段）：自动标记「失效」源并记录单次搜索耗时，显示层智能过滤第三方噪声与失败罚时；`bookSourceGroup` 等已知字段原样保留。
  - **扫码导入**：AVFoundation 相机扫码或相册选图 `CIDetector` 离线识别，按字段形态识别书源 / 替换规则 / 订阅源 / 字典规则 / WebDAV 配置；HTTP(S) 链接提供按网址添加书籍与复制，尚未接入扫码下载规则直链；书源管理长按菜单可**生成分享二维码**（单条书源的 JSON 数组，超容量自动提示）。
  - 未知顶层字段透传：`BookSource` / `RssSource` / `Book` 经 extras 感知解码后，将未建模的顶层字段（如 `concurrentRate`、`enabledCookieJar`、`Book.customTag` / `charset` / `type` / `syncTime`）保存在 `extra`，编码时扁平回写；`Book.order` 与书源 `jsLib` 已是正式属性。搜索 / 发现 / 详情 / 目录 / 正文五类嵌套规则也保留未知键，覆盖编辑、持久化和 ZIP 往返；其它嵌套对象、类型不兼容与顶层直接 `JSONDecoder` 调用仍不受此保证，也不代表透传字段已生效（见 `Plan.md` §二 #15）。
- **书源导入与登录**：
  - 不预装书源，书架从零开始；章节 URL 与详情元数据由书源规则决定，已删除站点专用路径重写与 JSON 猜测分支。
  - 支持从本地 `.json` 文件导入、网络 URL 下载导入、剪贴板粘贴导入。
  - 注册 `legado://` 与 `yuedu://` URL Scheme，网页端一键点击直接调起应用下载导入书源。
  - 支持内置 WebKit 网页登录与手动 Cookie，提取后写入书源 `loginHeader` 并镜像至 `HTTPCookieStorage`；另有简单文本 / 密码表单和脚本入口。脚本入口支持 `<js>` / `@js:` 包装与错误检测；RowUi 按钮与 `loginCheckJs` 尚未接入。

---

### 2. 沉浸式全屏阅读器
- **统一排版引擎 (`ChapterTypography`)**：
  - 滑动翻页与纵向连续长卷滚动共享同一套 CoreText 排版模型，减少模式切换时的排版位置差异。
  - 超长章节标题按可用宽度多行折行；分页与滚动标题使用同一 CoreText 字体和已测量行，避免分页标题被二次折行。
  - 保留 `rawContent` 中的换行，排版参数变更时基于该文本重算。
- **多排版模式与图文统一**：
  - 支持 覆盖 / 滑动 / 仿真（平滑降级）/ 连续滚动 / 无动画 5 档模式。
  - `TypographyPage`（`.lines` / `.image`）图文统一分页模型，翻页模式下插图独立成页。
  - 连续滚动模式原生支持双向长卷阅读：触底无缝拼装下一章，向下拉动无缝衔接上一章，并在断点间顺畅阅读；正文插图结合内存缓存（`ChapterImageLoader`）与排版坐标真实渲染。
- **精细化排版与主题**：
  - 内置 5 套预设主题：默认白、复古羊皮纸、护眼草绿、夜间暗黑、水墨屏（E-Ink 纯黑白无彩色），外加自定义配色（Hex 自由微调背景色与文字色）。恢复主题时同时匹配背景与文字色；无效色、透明或完全同色的文字有可读兜底，正文 / 标题 / 阅读面板共享有效配色。
  - 全局字体选择：系统默认（苹方）、楷体（`STKaiti`）、宋体（`Songti SC`）、圆体（`Yuanti SC`）。
  - 字号、行距、字距（CoreText `kern`）、段距、首行缩进（0–4 字符）、左右边距、上下边距全参数实时微调并落盘持久化。
  - 文字两端对齐（翻页与连续滚动双模式均生效）。
- **交互与快捷工具**：
  - **书内全书并发搜索 (`SearchContentSheet`)**：搜索弹窗顶部直达；关键字与正则双模式，缓存章节离线可搜、未缓存章节 6 并发联网抓取（可选），每批并发完成后按章节顺序输出命中（单章封顶 3 条），上下文高亮并展示章节进度；点击精准跳转到目标章节的字符偏移（翻页/滚动双模式适配）。
  - **长按选词与取词联动**：翻页与连续滚动双画布 600ms 长按选词（CJK 单字、西文整词），按住拖拽扩选、边界把手调节；浮动菜单支持 复制 / 查字典（预填查询词）/ 添加书签（摘录所选）/ 朗读所选 / 创建替换规则，随阅读主题深浅自适应。
  - **常驻系统状态栏**：始终常驻顶部时间、电量与网络状态，字体颜色随阅读主题深浅自适应。
  - **顶栏一键快捷按钮**：常驻「换源」与「刷新本章」图标，配合右侧菜单秒级切换。
  - **3×3 九宫格自定义点击区域**：支持 14 种动作配置（菜单、下一页、上一页、书签、听书、全文搜索、进度同步等）；仅在九个区域都没有菜单动作时，将中央恢复为菜单。
  - **章节内容自定义编辑 (`EditContentSheet`)**：支持编辑本章标题与正文、重置缓存及复制；正文写入磁盘缓存，标题仅更新当前阅读会话。重置会清正文缓存后重新加载，不恢复原始标题；本地 EPUB / TXT 也优先读取编辑缓存，清除后重新读取原文件。
  - **章节离线下载**：支持滑动选择起止章节区间，或一键下载后续 50/100/全部章节，任务中顺序抓取（每章 60ms 间隔），不保证 App 退后台后持续下载或免于站点限流。
  - **自动翻页**：支持 2–30 秒调速与悬浮控制条；分页模式定时翻页，连续滚动模式当前为定时切下一章，尚无平滑自动滚动。

---

### 3. 换源与离线可用性
- **整书换源与单章换源 (`ChangeSourceService`)**：
  - 多源并发搜索，展示候选书源、章节数与可选的最新目录预检。
  - 基于 Jaccard 相似度与中文数字章节号解析（`ChapterMatcher`）自动匹配当前章节；目录命名歧义时仍可能需要人工确认。
  - 阅读器内置 `tryAutoChangeSource`（默认关闭，需在「更多设置」开启）：目录为空或目录解析失败时，后台静默换到首个能取到目录的书源，无需中断阅读。
- **缓存优先与离线保障**：
  - 打开书籍优先加载本地目录缓存（`TocCache`），离线状态下只要已缓存过目录即可秒开书籍；10 分钟节流后台静默刷新目录。
  - 追更保护：纯追加更新保留原正文缓存，目录结构错位时主动重置防串章；串行 / 多 URL 续页受页数和检查预算限制，分片失败或截断不写完整正文缓存，不完整目录通过旧 API 返回时会抛错。
  - 目录加载失败时提供清晰重试与「返回书架」解死锁通道。

---

### 4. 朗读、听书与有声书播放器
- **双 TTS 引擎架构**：
  - 支持 iOS 原生离线语音合成（`AVSpeechSynthesizer`，默认 zh-CN）。
  - 支持自定义网络 **HttpTTS 引擎**，可在朗读面板中一键无缝切换原生/网络发音人。
- **朗读控制面板与常驻悬浮条**：
  - 朗读以段落为单位，支持上一段 / 下一段、语速调节（0–45 档换算）、音调微调、0–180 分钟定时停止。
  - 常驻底部的朗读悬浮条（播放/暂停/结束），可见性与播放状态自持，收起菜单后依然常驻。
  - 从当前可视页面首字起读，自动跳过插图标记 `[image:...]`。
  - 连续滚动模式下当前朗读段落以柔和底色高亮（尚无随进度自动居中滚动）。
  - 支持后台常驻音频播放（`UIBackgroundModes: audio`）、锁屏控制中心（`MPRemoteCommandCenter` / `nowPlayingInfo`）及耳机线控。
- **在线有声书独立播放器 (`AudioPlayView`)**：
  - 书架与书籍详情页针对 `bookSourceType == 1` 或包含音频标签的书籍自动路由进入有声书播放器。
  - 具备黑胶唱片式圆形封面、`AVPlayer` 流媒体播放、快进/快退 15 秒、0.75x~2.0x 倍速调节、定时关闭与完整章节目录抽屉。

---

### 5. 发现流与聚合搜索
- **三级分类发现流 (`CategoryExploreView`)**：
  - Level 1（快速换源）：顶栏横向胶囊单指轻点即换源。
  - Level 2（分类标签与矩阵抽屉）：支持换行格式（`标题::URL`）、标准 JSON 数组及 `<js>` 动态脚本生成的分类树。
  - Level 3（书籍信息流）：标准化书籍卡片流，支持下拉刷新与触底分页加载。
- **高性能聚合搜索 (`SearchBookView`)**：
  - 多源并发增量流式搜索（`AsyncStream` + `TaskGroup`），各源结果实时上涌。
  - 按「书名 + 作者」自动去重合并，聚合统计 `origins` 来源数徽标。
  - 搜索范围三态切换：全部书源 / 多分组勾选 / 单书源限定。
  - 精准搜索三桶排序：完全匹配 > 包含匹配 > 其余候选。
  - **书架已有匹配卡片**：搜索命中本地已有藏书时，输入框下方优先置顶快捷阅读入口。
  - 搜索历史管理：记录使用时间与频次，支持输入过滤、长按单条删除与一键清空。
  - 搜索控制：支持中途手动停止与断点继续。

---

### 6. 书架与书籍管理
- **灵活视图与排序**：
  - 支持标准列表视图与三列封面网格视图自由切换，状态持久化。
  - 5 种排序规则：最近阅读、最近更新、书名排序、作者排序、**手动排序（可拖拽）**——手动模式下列表出现拖拽把手，重排结果以 `Book.order` 持久化（对齐 Android），新书自动置顶。
- **分组体系 (`BookGroupStore`)**：
  - 默认虚拟分组：「全部」、「书源书籍」（网络源）、「本地书籍」（TXT/EPUB）。
  - 支持多组成员、分组重命名 / 删除、顺序与刷新开关。旧时间戳 ID 自动迁移并可从中断恢复；备份分组冲突会重映射，保持本地成员关系。
- **多选批量管理**：
  - 右上角 `⋯` 菜单进入选择模式，底部浮出批量操作栏：全选、反选、批量清理章节缓存、批量移入分组、批量移除书籍。
- **书架二级菜单（部分对齐 Android `main_bookshelf.xml`）**：
  - **缓存管理 (`CacheManageView`)**：按缓存体积列出书架书籍（已缓存/总章节数 + 占用，含尚无缓存的条目），支持**一键缓存全本**（⬇ 单键下载该书全部章节，行内实时进度、随时停止、已缓存自动跳过）、**一键缓存全部书籍**（逐本顺序队列）、单本清除与**整书导出**——TXT（UTF-8 / UTF-16 / GB18030 编码可选）与 EPUB（`mimetype` 首位 + container/OPF/nav/NCX 完整结构），以及「导出所有书籍」批量分享。导出仅包含已缓存的未净化正文，未缓存章节会跳过；EPUB 目前不嵌入图片资源。
  - **导出书单**：`bookshelf.json`（与 WebDAV 备份同编码形态）经系统分享面板导出。
  - **添加网址 (`AddUrlSheet`)**：粘贴章节/详情页 URL，按 `bookUrlPattern` → 前缀 → 同 host 三级匹配书源，自动抓取详情与目录后加架。
  - **远程书籍 (`RemoteBooksView`)**：WebDAV 目录浏览，点击 `.txt` / `.epub` 经鉴权会话下载并走本地导入链入库。
  - **书架管理 (`ShelfGroupDisplaySheet`)**：按分组开关书架顶部胶囊栏显示（`BookGroup.show`）。
- **书籍详情与信息编辑 (`BookDetailView`)**：
  - 支持编辑并持久化书名、作者、封面 URL、内容简介；简介写入 `Book.intro`，未实现 Android `customIntro` 的独立覆盖语义。
  - 目录列表支持输入过滤、正序/倒序一键翻转、已离线缓存章节绿色标识。
  - 快捷操作：整书置顶、整书换源、拷贝书籍 URL、拷贝目录 URL、清理单书缓存、**生成分享二维码**。
  - 变量弹窗：支持查看与编辑书源自定义变量及书籍绑定变量。

---

### 7. 正文处理与规则系统
- **正文替换净化管线 (`ContentProcessor`)**：
  - 处理包含：去除与标题重复段落 → 应用图片样式 → 系统级简繁转换（`ChineseConverter`）→ 逐行首尾修剪并按 order 升序执行替换规则 → 标题匹配规则 → 不间断空格清洗 → 规范首行缩进。
  - 单书净化总开关与全局新书默认净化配置。
  - 「起效的替换」实时查看器（`EffectiveReplacesSheet`），可从阅读菜单一键直达本章命中的规则并直接修改。
  - 正文与标题规则统一超时 / 取消与禁用回调，正则在进度回调中检查截止时间；超时结果被丢弃，调用者不再等待同步工作。已开始的 JS 仍缺强制中断，可能继续占用后台线程。
- **独立规则管理中心（设置 Tab）**（四类规则列表均支持 `EditButton` 拖拽排序，顺序字段随之持久化）：
  - **替换净化规则**：支持按分组管理、正则/字面匹配、作用于标题或正文、JSON 导入导出。
  - **TXT 目录规则**：内置标准章回节卷、Chapter、纯数字、大写分卷等默认预设；本地 TXT 导入自动匹配切章，详情页可随时选择规则重新切章。
  - **网络字典规则**：内置百度汉语、汉典等在线规则；阅读器搜索弹窗内置「查字典」Tab，快速解析关键字释义。
  - **HttpTTS 引擎管理**：自定义网络语音合成接口，支持 Header 配置、启用开关与默认引擎一键恢复。

---

### 8. WebDAV 与本地备份（部分 Android 兼容）
- **ZIP 备份与恢复**：沿用 Android 的 `backup<yyyy-MM-dd>-<设备>.zip` 命名，可通过 WebDAV 或本地文件导出 / 恢复。
- **已支持的文件名**：`bookshelf.json`、`bookSource.json`、`bookmark.json`、`replaceRule.json`、`searchHistory.json`、`readConfig.json`、`txtTocRule.json`、`readRecord.json`、`rssSources.json`、`rssStar.json`、`bookGroup.json`、`dictRule.json`、`httpTTS.json`。除书架 / 书源外，其它成员按数据是否存在决定是否写入。
- **兼容性边界**：Android 有 21 个候选备份成员，iOS 已支持分组、HttpTTS、字典等 13 个成员，仍缺规则订阅、主题、配置等 8 个成员。阅读样式已导出为数组，但只含当前样式、恢复也只取首项；分组位掩码已接入，单书阅读配置尚未对齐。阅读记录已按设备 + 书名合并。详见 [Plan.md 的备份表](Plan.md#current-gaps)。
- **独立阅读进度**：阅读器可按时间比较远端进度并拉取 / 上传，保存阅读位置时也会上传独立 `bookProgress/<书名>_<作者>.json`。ZIP 导出不生成该目录；恢复能读取 ZIP 内、邻接或远端进度目录；恢复与手动同步共用阅读时间优先、缺时间或同时间时比较章节 / 位置的策略。目录检查时间不参与进度比较。详情页暂无独立双向同步入口。
- **文件范围**：备份不含本地 TXT / EPUB 文件、解包资源、目录 / 正文缓存；未知 Android 成员不会在下次 iOS 备份中保留。恢复书架元数据不等于恢复书籍文件。
- **书签汇总 (`AllBookmarksView`)**：按书名 / 作者分组，支持检索、编辑 / 删除及 JSON / Markdown 复制导出。
- **WebDAV 配置扫码**：支持配置 JSON 或纯服务器地址。

---

### 9. RSS 订阅模块
- **独立订阅 Tab**：
  - 订阅源列表管理（名称、分组胶囊、URL 预览、置顶、删除、拖拽排序）。
  - 分类胶囊栏解析（支持 `标题::URL` 格式分类）与文章信息流展示（缩略图、标题、时间、描述）。
  - 文章正文阅读：基于 `ruleContent` 规则网络提取正文，离线 description 兜底，支持一键在 Safari 中打开原文。
  - 文章收藏夹（`RssStar`），数据自动纳入 WebDAV 备份。
- **订阅源编辑器 (`RssSourceEditSheet`)**：
  - 提供以下主要字段编辑：基本信息（名称/网址/图标/分组/注释/启用）、`loginUrl` + `loginUi` 登录配置、请求头 `header`、分类与版式（`sortUrl`/`singleUrl`/`articleStyle`）、列表规则七件套（`ruleArticles`/`ruleNextPage`/`ruleTitle`/`rulePubDate`/`ruleDescription`/`ruleImage`/`ruleLink`）、正文与样式（`ruleContent`/`style`/`enableJs`/`loadWithBaseUrl`）、变量与排序。`loginUrl` / `loginUi` 仅可编辑，RSS 登录未接入；`singleUrl` / `style` / `enableJs` / `loadWithBaseUrl` 尚未驱动相应渲染行为，文章正文以纯文本显示。
- **订阅源流式调试台 (`RssSourceDebugSheet`)**：
  - 三阶段实时调试：解析分类 (sortUrl) → 拉取文章列表 (ruleArticles 系列) → 抓取首篇正文 (ruleContent)，逐行流式输出各阶段耗时、解析结果预览与 `ruleNextPage` 是否生效。
- **文章流交互**：
  - 3 种版式一键切换并持久化：左文右图（0）、无图模式（1）、双列网格（2），对齐 Android `articleStyle`。
  - 基于 `ruleNextPage` 的触底翻页自动拼装，跨页文章按链接去重，带回环保护。
  - 已读文章标题置灰 + 已读角标，阅读历史落盘追踪（最多 500 条，随会话持久化）。

---

### 10. 本地文件与局域网传书
- **本地格式解析**：
  - **EPUB**：支持 EPUB3 nav 与 EPUB2 NCX 双目录标准，处理 spine 兜底，支持内嵌原画插图、锚点跳转与分卷连贯性识别。
  - **TXT**：结合启用的 TXT 目录规则智能正则分章；支持 UTF-8 BOM 剥离、HTTP/HTML 编码探测及 GB18030 / Big5 候选解码打分；启发式识别不能保证所有文件都正确。
- **局域网 WiFi 传书 (`LocalWebServer`)**：
  - 基于 iOS `Network.framework` 纯原生 `NWListener` 实现轻量 HTTP 服务，无需任何第三方 HTTP 库依赖。
  - 设置页一键开启服务，提示局域网地址（如 `http://192.168.1.100:1122`）。
  - 电脑或手机浏览器打开网页门户，通过文件选择上传 TXT、EPUB 文件；服务端按 `Content-Length` 收满整包、解出 multipart 中的文件字节并放入书架。
- **主屏快捷操作 (Home Screen Quick Actions)**：
  - 3D Touch / 长按 App 图标快速唤起「搜索书籍」（直达分类搜索）与「继续阅读」（自动打开最近阅读的书籍）。

---

## 📖 书源制作与兼容性规范指南

书源使用 Android **Legado（阅读 3.0）** 的常用 JSON 字段；管理、扫码和整源粘贴均支持 JSON 数组或单对象。以下为常用规则写法，具体执行边界见 [Plan.md](Plan.md)：

### 1. 核心属性
| 字段 | 类型 | 说明 | 示例 |
|---|---|---|---|
| `bookSourceName` | String | 书源名称 | `"示例书源"` |
| `bookSourceUrl` | String | 书源基准 URL | `"https://example.com"` |
| `bookSourceGroup`| String? | 书源分类分组 | `"日轻,网络小说"` |
| `bookSourceType` | Int? | 类型：`0` 文本小说，`1` 音频，`2` 图片漫画 | `0` |
| `enabled` | Bool? | 是否启用该源 | `true` |
| `enabledExplore` | Bool? | 是否启用发现流 | `true` |
| `header` | String? | 全局 HTTP 请求头 (JSON 字符串) | `{"User-Agent": "Mozilla/5.0..."}` |
| `loginUrl` | String? | 账号登录交互 URL | `"https://example.com/login"` |
| `loginUi` | String? | 简单表单配置（RowUi JSON；按钮尚未执行） | `"[{\"name\":\"账号\",\"type\":\"text\"}]"` |

### 2. 搜索规则 (`ruleSearch` & `searchUrl`)
- `searchUrl`: 目标地址，支持 GET 与 POST：
  - GET: `https://example.com/search?q={{key}}&page={{page}}`
  - POST: `https://example.com/search,{"method":"POST","body":{"kw":"{{key}}","p":{{page}}}}`
- `bookList`: 书籍列表选择器（如 `$.data.list[*]`、`div.book-item` 或 `//div[@class='book-item']`）。
- `name` / `author` / `bookUrl` / `coverUrl` / `intro` / `kind` / `lastChapter` / `wordCount`: 对应书籍属性提取规则。

### 3. 详情与目录规则 (`ruleBookInfo` & `ruleToc`)
- 当前详情执行 `init` 根节点预处理、name / author / intro / kind / wordCount / coverUrl / lastChapter / tocUrl；支持详情 → 独立目录请求。`updateTime` 尚未执行。
- 目录解析：
  - `chapterList`: 章节列表选择器（如 `$.chapters[*]` 或 `div.chapter-list a`）。
  - `chapterName`: 章节标题（如 `$.title` 或 `text`）。
  - `chapterUrl`: 章节正文请求地址（如 `$.url` 或 `href`，自动补全相对路径）。
  - `nextTocUrl`: 分页目录下一页地址。
  - `isVolume` / `isVip` / `isPay` / `updateTime`: 求值分卷、VIP、已购买标记及章节 tag；无链接分卷保留为不请求网络的目录项。
  - `formatJs`: 合并所有目录页、去重 / 反转 / 编号后执行，提供共享 `gInt`、1 起算 `index`、`chapter` 与 `title`；脚本异常保留原标题。v0.3.0 在显式刷新目录时执行 `preUpdateJs`，支持 `java.refreshTocUrl()` / `java.reGetBook()`；初次请求默认不执行。v0.3.1 已接入执行预算与取消中断，细节见 [运行时说明](docs/SourceRuntime.md)。

### 4. 正文规则 (`ruleContent`)
- `content`: 正文提取选择器。若为 HTML 内容建议使用 `@html`（如 `div#content@html`）。
- **插图自动提取**：使用 `@html` 时，阅读器会自动抽取其中的 `<img src="...">` 标签并渲染为插图，自动携带 `Referer` 防盗链头。
- `replaceRegex`: 正文清洗正则表达式，语法为 `正则##替换内容##正则##替换内容`。
- `nextContentUrl`: 长章节跨页抓取下一页地址。

### 5. 发现分类规则 (`exploreUrl`)
支持以下 3 种写法：
1. **标准 JSON 数组**：
   ```json
   [
     {"title": "分类", "url": ""},
     {"title": "玄幻", "url": "/sort/1?page={{page}}"},
     {"title": "仙侠", "url": "/sort/2?page={{page}}"}
   ]
   ```
2. **换行文本格式**：
   ```text
   玄幻::/sort/1?page={{page}}
   仙侠::/sort/2?page={{page}}
   ```
3. **动态 JavaScript 脚本**：`<js>JSON.stringify([...])</js>`。

---

## 🏗️ 架构设计

工程按核心库与应用层组织；`BookStore` 仍承担部分导入、持久化与业务编排：

```text
Legado-iOS/
├── Sources/
│   ├── LegadoCore/               # 跨平台纯 Swift 核心逻辑库
│   │   ├── Engine/               # 规则引擎（JSEngine, RuleAnalyzer, RuleTokenizer）
│   │   ├── Models/               # 数据实体（Book, BookSource, ReadConfig, Bookmark, ReplaceRule, SearchScope, SearchKeyword, RuleModels, RssModels）
│   │   ├── Service/              # 业务服务（NetworkClient, BookContentService, BookContentSearchService, ContentProcessor, ChangeSourceService, ReaderStore, ReplaceRuleStore, BookSearchService, BookExploreService, RssService, TocCache, LocalWebServer, LaunchIntent, WebDAVService, EpubParser, BookExportService...）
│   │   └── Utils/                # 工具组件（CharsetDetector, ChapterMatcher, ChineseConverter, TolerantJSON, JSONValue, CryptoUtils, JSONPath, BookUrlMatcher, ScanPayload）
│   └── LegadoApp/                # SwiftUI 交互层与应用入口
│       ├── LegadoApp.swift       # 应用入口 + AppDelegate/SceneDelegate（快捷操作桥接）+ MainTabView（4 Tab 根界面）+ URL Scheme 监听
│       ├── Services/             # 应用状态管理（BookStore, SearchViewModel, AudioBookService, LaunchRouter, TabBarVisibility）
│       ├── Theme/                # 阅读主题与排版配置（ReaderConfig）
│       └── Views/                # 用户界面视图
│           ├── Bookshelf/                # 书架二级菜单功能页（缓存管理/导出、添加网址、远程书籍）
│           │   ├── CacheManageView.swift # 缓存管理（章节数/体积 + TXT/EPUB 整书导出 + 导出所有）
│           │   ├── AddUrlSheet.swift     # 添加网址（三级书源匹配）+ 书架管理（分组显示开关）
│           │   └── RemoteBooksView.swift # WebDAV 远程目录浏览与文件导入
│           ├── QR/                       # 扫码（相机 / 相册识别、二维码分享、结果识别与部分导入分流）
│           ├── BookshelfView.swift       # 书架（分组胶囊、三列网格/列表、5 种排序、批量管理、书架二级菜单）
│           ├── CategoryExploreView.swift # 分类页（快速切源胶囊、预设分类流）
│           ├── ExploreBookListView.swift # 单分类书籍流（下拉刷新、触底分页）
│           ├── BookDetailView.swift      # 书籍详情（信息编辑、整书换源、变量弹窗、目录居中与反转）
│           ├── RssViews.swift            # RSS 订阅（订阅源/文章流/纯文本正文/收藏夹/源编辑/三阶段调试台）
│           ├── AudioPlayView.swift       # 在线有声书独立播放器（圆形封面/倍速/定时/目录）
│           ├── SourceManagerView.swift   # 书源管理（搜索/三态胶囊/批量启禁删导/并发校验）
│           ├── SourceDetailView.swift    # 书源详情与信息展示
│           ├── SourceWebLoginView.swift  # WebKit 书源交互式登录
│           ├── EditSourceSheet.swift     # 6-Tab 常用字段编辑器 + 四阶段流式调试台
│           ├── SearchBookView.swift      # 搜索页（多源并发增量流、书架匹配、搜索历史）
│           ├── WebDAVSyncView.swift      # WebDAV 备份恢复 + 本地备份包导出/导入
│           ├── Reader/                   # 全屏沉浸式阅读器
│           │   ├── ReaderView.swift      # 阅读画布顶层控制器、手势调度、常驻状态栏、底栏控制、选词浮动菜单
│           │   ├── Canvas/               # 统一排版与滚动画布（ChapterTypography 统一排版真理源, ReaderScrollCanvasView 原生长卷滚动画布, TextSelection 选词几何）
│           │   ├── Panels/               # 界面样式面板、更多设置、朗读控制、悬浮条、点击区域
│           │   └── Sheets/               # 书签列表、整书/本章换源、章节内容编辑、起效的替换、全书搜索
│           ├── Search/                   # 搜索范围选择面板
│           ├── Settings/                 # 替换规则管理
│           └── SettingsView.swift        # 我的（Android pref_main 同构：书源管理/规则四页/主题模式/Web服务/备份恢复/其它设置/书签/阅读记录/关于）
├── Runtime/                      # 固定 QuickJS 源码、C 宿主桥与 Swift 适配器，已接入 App
├── Tests/                        # 自动化测试（31 文件 404 例：Core + App + Runtime）
├── tools/xcode_add_sources.py    # Xcode 工程源文件同步脚本
└── Legado.xcodeproj              # Xcode 工程配置文件
```

---

## 🛠️ 编译与测试门禁

### 环境要求
- macOS 12.0+
- Swift tools 5.7+ / Xcode 14.0+；CI 优先使用 Xcode 15.4（本次未验证最低 Xcode 版本）
- iOS 15.0+ 部署目标

### 本地编译
1. 克隆代码仓库：
   ```bash
   git clone git@github.com:SeitoMoyi/Legado-iOS.git
   cd Legado-iOS
   ```
2. 运行自动化单元测试（Swift Package Manager）：
   ```bash
   swift test --skip LiveSourceTests   # 397 项非联网测试，缺少外部样本时显式 skipped
   swift test                          # 另含 7 项真实书源联网冒烟，共 404 项；不可达时会跳过
   ```
   v0.3.0 发布验证为 363 项；v0.3.2 数据兼容（2026-10-26）macOS SPM 报告 397 项、3 skipped、0 失败。两个 EPUB 样本用例与一个 Android ZIP 样本用例因未提供文件而显式 `XCTSkip`。可设置 `LEGADO_TEST_EPUB` / `LEGADO_TEST_BACKUP_ZIP` 补验。此结果不证明完整 Android 往返兼容，另已通过 iOS Simulator 编译，并在 iPhone 13 / iOS 17.2 模拟器验证主题恢复后首开本地滚动阅读与本地 HTTP 样本分页阅读；另在 iPhone 11 / iOS 15.5 模拟器用实际机翻机器人书源验收简介 JS 与第 63 话标题两行；未做真机交互验收。

   测试会写用户缓存与偏好。在受限工作区，可使用隔离目录重现本次非联网测试（依赖须已检出）：
   ```bash
   review_home=$(mktemp -d /tmp/legado-tests.XXXXXX)
   env CFFIXED_USER_HOME="$review_home" \
     CLANG_MODULE_CACHE_PATH="$review_home/clang" \
     SWIFTPM_MODULECACHE_OVERRIDE="$review_home/swift" \
     swift test --disable-sandbox --cache-path "$review_home/spm" --skip-update --skip LiveSourceTests
   ```
3. 打开并运行 Xcode 工程：
   ```bash
   open Legado.xcodeproj
   ```
   在 Xcode 中选择模拟器或真机目标设备，按 `Cmd + R` 即可运行。新增 Swift 文件后必须登记进 Xcode 工程，否则 `xcodebuild` 会静默忽略它们：
   ```bash
   python3 tools/xcode_add_sources.py --check                      # 列出尚未登记的文件
   python3 tools/xcode_add_sources.py Sources/Path/NewFile.swift   # 登记指定文件
   ```

---

## 📦 安装与侧载方式

项目的 [GitHub Actions 工作流](.github/workflows/release.yml) 构建未签名 IPA。可使用适配设备系统版本的侧载工具签名安装，或在 Xcode 配置自己的开发团队后运行；未签名 IPA 不能直接当作已签名安装包使用。

---

## 📄 开源许可证

本项目基于 [GPLv3](LICENSE) 许可证开源，遵循与原版 Legado 相同的开源精神与社区规范。
