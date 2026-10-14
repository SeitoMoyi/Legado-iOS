# Legado Android → iOS 功能差距清单（按版面）

> 对比基准
> - **Android**：`/Users/peibinxu/Downloads/legado-master`（`app/` 805 个 Kotlin 文件，`app/` + `modules/` 合计 844；184 个 layout，完整版 3.0）
> - **iOS**：`./ios`（`Sources/LegadoCore` + `Sources/LegadoApp`）—— 对比基线取 **v0.2.0** 的 32 个 Swift 文件 ≈ 10.7k 行，当前为 **66 个 Swift 文件 ≈ 23.8k 行**（LegadoCore 34 + LegadoApp 32）；本清单已随 **v0.2.1**（P0 全部落地）、**v0.2.2**（缓存与离线可用性）与 **v0.2.3**（书源/书架/规则工具链补齐、10 类备份、6-Tab 编辑器与调试台、RSS 订阅、有声书、URL Scheme 与 WiFi 传书）刷新状态，标 ✅ 处见各表与 `UPDATE_LOG.md`（有意偏离 Android 的条目统一记录在 `UPDATE_LOG.md` 的「关键设计决策与 Android 偏离备忘」表）
> - 生成日期：2026-10-12（2026-10-13 按代码复核修正）。所有结论以**代码实际存在**为准，不采信 README 宣传（README 与代码不符项见 §24）。

**图例**

| 标记 | 含义 |
|---|---|
| ✅ | 已实现，行为与 Android 基本对齐 |
| ⚠️ | 部分实现（有入口但功能残缺 / 只覆盖一个分支） |
| ❌ | 完全缺失 |
| 🍎 | Android 专属机制，iOS 需换实现方式（非简单移植） |

---

## 1. 总览：版面完成度矩阵

| # | 版面 | Android | iOS | 完成度 | 主要缺口 |
|---|---|---|---|---|---|
| 1 | 应用外壳 / 底部导航 | 4 tab 可配 | 4 tab 固定 | 55% | 「我的」tab、tab 显隐、默认主页、角标、启动隐私协议、本地密码（**书架/分类/订阅/设置 4 tab 已上线**） |
| 2 | 书架页 | 极重 | 中等 | **50%** | 分组进阶（封面/组内排序/位掩码多选/拖拽）、远程书籍、书单导入导出（**默认分组「全部 / 书源书籍 / 本地书籍」+ 分组增删改、三列网格视图、4 种排序、多选批量删除与清缓存、菜单全量刷新已实现**） |
| 3 | 书籍详情页 | 完整 | 较完整 | **75%** | 二维码分享、上传 WebDAV、变量弹窗（**书籍信息编辑、置顶、拷贝 URL、整书换源、目录正倒序/缓存标记/自动定位已实现**） |
| 4 | 阅读页 | 全站最重 | 中高 | **60%** | 自动翻页、文本选择/词典、书内找字、动画时长、样式编辑器（三级菜单/书签/点击区域/TTS 面板与悬浮条/换源/替换净化/进度条按页或按章/图片样式渲染 **已实现**；亮度与音量键翻页已主动删除） |
| 5 | 发现页 | 书源折叠流 | 三级分类流 | 60% | 形态不同；缺分组筛选、单源操作菜单、ERROR 处理（`enabledExplore` 过滤已实现） |
| 6 | 搜索页 | 多源并发 | 多源并发 | **80%** | 书架匹配区块、空结果引导、后台挂起（历史/范围/精准/停止继续/来源数计数 **P0-7 已实现**） |
| 7 | 订阅 / RSS | 整个模块 | 基础可用 | **40%** | 订阅源全字段编辑器、订阅源调试页、文章样式切换/翻页、已读置灰、网页朗读、资源黑白名单、规则订阅聚合（**源管理/分类/文章流/正文提取/收藏夹/10 类备份已实现**） |
| 8 | 书源管理页 | 极重 | 中高 | **70%** | 拖拽排序、二维码、逐条导入选择（**新建空白源、实时搜索、三态分组胶囊、多选批量启禁删导、并发校验与失效归类已实现**） |
| 9 | 书源编辑页 | 6 tab 全字段 | **6 tab 全字段** | **85%** | 语法高亮与键盘辅助符号条（**基本/搜索/发现/详情/目录/正文 6-Tab 全规则字段编辑 + 整源 JSON 拷贝/粘贴 + 调试入口已实现**） |
| 10 | 书源调试页 | 完整 | 四阶段实时调试台 | **60%** | 各阶段 HTML 源码独立查看器、WebSocket 调试（**搜索→详情→目录→正文四阶段流式日志调试台 `SourceDebugSheet` 已实现**） |
| 11 | 登录 / 内置浏览器 | 完整 | 登录✅ 浏览器❌ | 50% | 通用 WebView 页、过盾、下载、Cookie 管理 |
| 12 | 我的页 | Preference 全表 | 设置中心（无独立「我的」页） | **45%** | 帮助页、其它设置全量项、文件管理、WebDAV 密码加密（**书源/书架与存储/备份/替换净化/TXT目录/字典规则/HttpTTS/所有书签/阅读记录/外观模式/局域网服务已就绪**） |
| 13 | 设置（其它/主题/封面/启动/备份） | 约 90 项 | 约 25 项 | **30%** | 启动图/其它设置全量项（**替换净化、TXT目录规则、字典规则、HttpTTS、本地备份包导出/导入、清理缓存、外观模式已实现**） |
| 14 | 规则管理（替换/字典/TXT目录/HttpTTS） | 4 个完整 CRUD 页 | 4 个完整 CRUD 页 | **80%** | 拖拽排序/多选/分组过滤/二维码导入（**替换净化✅、TXT目录规则✅、字典规则✅、HttpTTS✅ 均支持 CRUD、导入导出与预装默认**） |
| 15 | 文件管理 / 阅读记录 / 所有书签 / 关于 | 4 页 | 3 页 | **75%** | 私有文件浏览器（**所有书签✅、阅读记录✅、关于（名称/版本/内核）✅ 已实现**） |
| 16 | Web 服务 / 外部集成 | 完整 LAN server | 轻量 LAN server | **25%** | 完整 REST/WebSocket API、静态管理 SPA、通知栏服务（**`LocalWebServer` WiFi 传书已实现**，见 §20） |
| 17 | 核心规则引擎 | 全语法 | CSS+JSONPath+XPath+JS | **65%** | 选项 DSL 缺失、JS 桥不全（**XPath 执行与 `book.getVariable/setVariable` 已实现**） |
| 18 | 本地书格式 | EPUB/TXT/MOBI/AZW3/UMD/PDF | EPUB/TXT | 40% | MOBI/AZW3/UMD/PDF、压缩包内选书 |

**一句话结论**（v0.2.3 后已刷新）：「搜索 → 分类 → 详情 → 阅读 → WebDAV 同步」这条最小闭环已补齐 Android 的核心交互（三级菜单、点击区域、书签、换源、替换净化、朗读面板与悬浮控制条、搜索范围/历史），**书源编辑/调试/校验、书架分组与管理、规则管理 4 页、RSS 订阅、有声书、URL Scheme 与 WiFi 传书**也已落地。剩下的空白集中在**「我的」全量设置体系、主题/封面/启动页、书源/书架拖拽排序与二维码、文本选择与书内全文搜索、漫画模式、完整 LAN API**，以及少量接线类遗留（见 §23 P0 小节）。

---

## 2. 版面一：应用外壳与底部导航

| Android 功能 | 层级 | iOS | 说明 |
|---|---|---|---|
| 底部 4 tab：书架 / 发现 / 订阅 / 我的 | 一级 | ⚠️ | iOS 为 **书架 / 分类 / 订阅 / 设置** 4 个 tab（`MainTabView`）；「发现」被并入「分类」，「我的」以「设置」替代，**「订阅」已上线** |
| 「显示发现」「显示订阅」开关（可隐藏 tab） | 二级 | ❌ | |
| 「默认主页」选择（书架/发现/订阅/我的） | 二级 | ❌ | |
| 书架 tab **待更新数量角标**（BadgeView） | 一级 | ❌ | |
| 双击 tab 回到顶部 / 折叠发现区 | 手势 | ❌ | |
| 返回键：非书架先回书架 → 双击退出「再按一次退出程序」 | 手势 | ❌ | |
| 打开软件自动更新全部书籍目录（`autoRefreshBook`） | 二级 | ⚠️ | iOS 只有手动下拉刷新 |
| 首次启动隐私协议弹窗 | 一级 | ❌ | |
| 本地密码设置（备份加解密） | 二级 | ❌ | iOS 备份为明文 |
| 崩溃日志检测提醒 | 二级 | ❌ | |
| 墨水屏（E-Ink）主题模式 | 二级 | ⚠️ | 阅读器主题含 `ReaderTheme.eink`（纯白底纯黑字），**全局** E-Ink 仍缺 |
| 启动页样式（自定义欢迎图/文字/图标） | 二级 | ❌ | |
| 桌面 App Shortcuts（书架 / 最后阅读 / 朗读） | 三级 | ✅ | `Info.plist` 声明「搜索书籍 / 继续阅读」两项 `UIApplicationShortcutItems`，由 `LegadoAppDelegate.configurationForConnecting` 挂载的 `LegadoSceneDelegate.windowScene(_:performActionFor:)` 接收（App Shortcut 是**场景级**事件，须由 scene delegate 处理），经 `LaunchRouter` 分发：「搜索书籍」切到分类 tab，「继续阅读」打开 `durChapterTime` 最新的书 |

---

## 3. 版面二：书架页

### 3.1 顶栏菜单（`main_bookshelf.xml` 共 12 项）

| Android 按钮 | 二级 / 三级功能 | iOS |
|---|---|---|
| 搜索 | 进入全书源搜索 | ✅ |
| 更新目录 | 刷新当前分组全部书籍 | ✅ | 下拉刷新 + 右上角菜单「刷新全部目录」按钮 |
| 添加本地 | 本地文件导入页 | ⚠️ | iOS 支持 `fileImporter` 选 EPUB/TXT，无独立文件树页 |
| 远程书籍 | WebDAV 书服务器浏览/下载 | ❌ | |
| 添加网址 | 粘贴 URL 匹配书源加架（支持多行） | ❌ | |
| 书架管理 | 多选管理页（见 3.6） | ✅ | 右上角 `⋯` 二级菜单「选择」进入多选批量管理（全选/反选/清理缓存/批量移除） |
| 缓存/导出 | 离线缓存 + epub/txt 导出全套 | ⚠️ | 阅读页「离线缓存章节...」支持自定义区间下载与后台进度报告 |
| 分组管理 | 分组 CRUD（见 3.5） | ⚠️ | `⋯` 菜单「书架分组管理」→ `BookGroupManageSheet`（新建/删除自定义分组）；**无显示开关与拖拽排序** |
| 书架布局 | 布局设置对话框（见 3.4） | ⚠️ | 视图切换与排序直接放在 `⋯` 菜单，**无独立布局对话框** |
| 导出书单 | 生成 `bookshelf.json` | ⚠️ | 备份包内含 `bookshelf.json`，但**无独立「导出书单」入口** |
| 导入书单 | URL / JSON / 选文件 + 多线程精确搜索加架 | ❌ | |
| 日志 | AppLogDialog | ❌ | |

### 3.2 列表与视图

| Android | iOS | 说明 |
|---|---|---|
| 列表视图 | ✅ | |
| 网格 3/4/5/6 列视图 | ✅ | 支持列表视图与三列封面网格视图切换（`@AppStorage` 持久化） |
| 封面显示书名 / 显示作者 / 自定义默认封面图 | ❌ | iOS 用 SF Symbol 占位 |
| 显示「未读章节数」角标 | ⚠️ | iOS 有红点数字，但受开关控制的「显示未读标志」缺失 |
| 显示「上次更新时间」（30s 定时刷新） | ❌ | |
| 更新中转圈 loading | ❌ | |
| 显示最新章节 + 当前阅读进度双行 | ⚠️ | 列表视图显示 `latestChapterTitle` ✅（`BookshelfView:536`）；网格视图显示 `durChapterTitle`/「未读」 |
| 快速滚动条（FastScroll + 字母索引） | ❌ | |
| 空书架引导文案 | ✅ | |

### 3.3 手势

| Android | iOS |
|---|---|
| 单击书 → 直接进入阅读/漫画/听书 | ✅（仅文本阅读） |
| 长按书 → 书籍详情页 | ✅ |
| 下拉刷新 | ✅ |
| 左滑删除 | ✅（Android 无，属 iOS 额外） |
| 长按拖拽排序（手动排序模式） | ❌ |
| 点击分组文件夹进入 / 长按分组编辑 | ❌ |
| 点击封面直接进阅读（`openBookInfoByClickTitle` 反向） | ❌ |

### 3.4 「书架布局」对话框（7 项）

| 选项 | 可选值 | iOS |
|---|---|---|
| 分组样式 | Tab / Folder | ⚠️ 仅 Tab 胶囊栏（`groupTabBar`）；无 Folder 混排 |
| 视图 | 列表 / 网格3 / 网格4 / 网格5 / 网格6 | ⚠️ 列表 / 三列网格（`isGridMode`，`@AppStorage` 持久化） |
| 排序 | 阅读时间 / 更新时间 / 书名 / 手动 / 综合 / 作者 | ⚠️ 最近阅读 / 最近更新 / 书名 / 作者 四种（`BookshelfSortOrder`，`@AppStorage` 持久化）；**无手动排序、无综合排序** |
| 显示未读标志 | 开关 | ❌ |
| 显示上次更新时间 | 开关 | ❌ |
| 显示等待更新数量 | 开关 | ❌ |
| 显示快速滚动条 | 开关 | ❌ |

### 3.5 分组体系

| 功能 | 层级 | iOS |
|---|---|---|
| 分组管理对话框（添加/编辑/显示开关/拖拽排序，上限 64） | 一级 | ⚠️ | `BookGroupManageSheet` 支持新建/删除自定义分组并列出系统内置组；**无编辑改名、显示开关、拖拽排序、上限约束** |
| 编辑分组：分组封面（选图）、名称、组内独立排序、允许下拉刷新、删除 | 二级 | ❌ |
| 分组选择对话框（位掩码多选、可叠加进多个组） | 二级 | ❌ |
| Tab 样式：分组标签栏 + ViewPager + 记住上次 tab + 长按编辑 | 一级 | ⚠️ 顶栏分组胶囊切换（`groupTabBar`）+ `selectedGroupId` 状态；**不持久化上次 tab、无长按编辑、无 ViewPager 横滑** |
| Folder 样式：分组以封面卡片混排在书列表中 | 一级 | ❌ |

### 3.6 书架管理页（多选，Android `BookshelfManageActivity`）

| 功能 | iOS |
|---|---|
| 边缘滑动框选多选 / 全选 / 反选 / 选中所选区间 | ⚠️ | 支持多选、全选、反选（无边缘滑动框选） |
| 顶部筛选框（按书名/作者过滤，显示「筛选 • 组名」） | ❌ | |
| 手动拖拽排序（仅手动排序模式） | ❌ | |
| 每行：勾选 / 书名（可点击进详情）/ 作者 / 来源 / 当前分组 / 分组按钮 / 删除按钮 | ⚠️ | 列表与网格均支持勾选状态指示 |
| 菜单：分组切换、分组管理、导出所有在用书源、点击书名打开详情 | ❌ | |
| 底部批量操作：移入分组、删除（含「删除源文件」复选）、允许更新、禁止更新、加入分组、**批量换源**、清理缓存 | ⚠️ | 底部批量操作栏支持「全选 / 反选 / 清理缓存 / 分组（移入自定义分组或设为未分组）/ 批量移除」；**允许更新、禁止更新、批量换源、删除源文件复选 ❌** |
| 批量换源间隔设置（`batchChangeSourceDelay`） | ❌ |

### 3.7 导入流程

**添加本地 `ImportBookActivity`**

| 功能 | iOS |
|---|---|
| 首次选择书籍保存目录（SAF） | 🍎 ❌ |
| 文件树面包屑 + 上一级 | ❌ |
| 顶部筛选框 | ❌ |
| 选择文件夹 / 按名称·大小·时间排序 / 智能扫描子目录 | ❌ |
| 导入文件名 JS 表达式自定义（`bookImportFileName`） | ❌ |
| 已在书架的标记 → 点击直接开始阅读 | ❌ |
| 压缩包（zip/epub）内选书 | ❌ |
| 底部「放入书架」+ 多选「删除」 | ⚠️ | iOS 导入即加架，无选择流程 |

**远程书籍 (WebDAV) `RemoteBookActivity`**

| 功能 | iOS |
|---|---|
| 浏览远程 `books/` 目录 + 面包屑 + 上一级 | ❌ |
| 服务器配置对话框（多 WebDAV 服务器 CRUD：名称/类型/URL/账号/密码/设为默认） | ❌ |
| 刷新 / 按名称·更新时间排序（升降切换） | ❌ |
| 已在书架的询问「是否重新加入书架？」 | ❌ |
| 下载后加架 | ❌ |
| 帮助 / 日志 | ❌ |

**其他**

| 功能 | iOS |
|---|---|
| 添加书籍网址（多行 URL 批量） | ❌ |
| 导入书单（URL / JSON / 文件 + 精确搜索加架） | ❌ |
| 导出书单（`bookshelf.json`，可走直链上传） | ❌ |
| 外部链接/分享进来的「放入书架」确认弹窗（`AddToBookshelfDialog`） | ❌ 🍎 |

---

## 4. 版面三：书籍详情页（`BookInfoActivity`）

### 4.1 页面元素

| Android | iOS | 说明 |
|---|---|---|
| 封面 + 模糊背景 | ⚠️ | iOS 有封面卡，无模糊背景 |
| 单击封面 → 换封面（候选封面网格） | ❌ | |
| 长按封面 → 大图预览 | ❌ | |
| 点击书名 → 按书名搜索 | ❌ | |
| 点击作者 → 按作者搜索 | ❌ | |
| 点击来源 → 编辑该书源 | ✅ | |
| 最新章节 / 简介 / 分类标签 / 分组 / 当前目录进度 | ⚠️ | iOS 有简介、标签、进度；**无「分组」行** |
| 开始阅读 / 继续阅读 | ✅ | |
| 放入书架 / 删除书籍（含确认 + 删除源文件复选） | ✅ | 无「删除提醒」开关 |
| **换源（整本书）** | ✅ | `BookDetailView` 头部来源行与右上角菜单均接入 `ChangeSourceSheet(.wholeBook)` |
| 下拉刷新详情 | ✅ | |

### 4.2 右上角菜单（`book_info.xml` 16 项）

| 按钮 | 二级功能 | iOS |
|---|---|---|
| 编辑 | 书籍信息编辑页 | ✅ | `BookInfoEditSheet`（可改书名、作者、封面链接、简介并持久化） |
| 分享 | 生成书籍二维码分享 | ❌ | |
| 上传 WebDav | 本地书上传到 WebDAV `books/` | ❌ | |
| 刷新 | 重载书籍信息 | ✅ | |
| 登录 | 书源登录页（有 loginUrl 时） | ❌ | |
| 置顶 | 排到书架最前 | ✅ | `bookStore.pinBook` 排到书架首位并更新时间戳 |
| 设置源变量 | VariableDialog | ✅ | `VariableEditorSheet`（来源行 + 菜单「设置书源变量」，显示 `variableComment`） |
| 设置书籍变量 | VariableDialog | ✅ | `VariableEditorSheet`（菜单「设置书籍变量」） |
| 拷贝书籍 URL | 剪贴板 | ✅ | |
| 拷贝目录 URL | 剪贴板 | ✅ | |
| 允许更新 | 可勾选 | ❌ |
| 拆分超长章节 | 可勾选（本地 txt） | ❌ |
| 删除提醒 | 可勾选 | ❌ |
| 清理缓存 | 单书缓存 | ✅ |
| 日志 | | ❌ |

### 4.3 书籍信息编辑页（`BookInfoEditActivity`）

| 字段 | iOS |
|---|---|
| 书名 / 作者 | ✅ |
| 类型（文字 / 音频 / 图片） | ❌ |
| 封面地址 + 换封面 + 选本地封面 + 刷新封面 | ⚠️ 封面 URL 编辑已支持 |
| 内容简介（自定义简介） | ✅ |
| 保存（并迁移缓存目录） | ✅ |

### 4.4 目录列表页（`ChapterListView` / Android `TocActivity`）

| Android | iOS | 说明 |
|---|---|---|
| 章节列表 + 点击跳转 | ✅ | |
| 目录内搜索 | ✅ | |
| 当前章节高亮 + 定位 | ✅ | 打开目录自动 `scrollTo(currentChapterIndex)` 居中 + 顶栏定位按钮 |
| 正序 / 倒序切换（反转目录） | ✅ | 目录顶栏正序/倒序一键切换 |
| 卷名分组显示（`isVolume`） | ❌ | |
| 章节字数显示（加载字数） | ❌ | |
| 缓存状态图标（未缓存=云朵 / 已缓存=对勾） | ✅ | 已缓存章节展示绿色「已缓存」标签 |
| VIP 锁定图标 | ❌ | |
| 章节标签（时间规则） | ❌ | |
| 「目录 / 书签」双 Tab | ✅ | 阅读器底栏可直达目录与书签页，搜索弹窗支持本章/目录/查字典三 Tab |
| 底部栏：当前章节信息 / 滚动到顶部 / 滚动到底部 | ❌ | |
| 快速滚动条 | ❌ | |
| 长按章节显示完整标题 | ❌ | |
| 菜单：TXT 目录规则、拆分超长章节、反转目录、使用替换、加载字数、日志 | ⚠️ | 本地 TXT 支持在书籍详情页菜单选择 TXT 目录规则一键重新切章，目录支持正序/倒序反转 |

---

## 5. 版面四：阅读页（缺口最大）

### 5.1 输入与手势

| Android | iOS | 说明 |
|---|---|---|
| 九宫格点击区域（3×3 可自定义，14 种动作） | ✅ | P0-1：`TapZoneOverlay` 三等分 + `ClickActionCode` 0–13；保存时强制中央区=菜单（防锁死，同 Android） |
| 点击区域设置对话框（`click_regional_config`） | ✅ | `TapZoneEditorPanel`，含「恢复默认」 |
| 水平滑动翻页 | ✅ | |
| 滑动翻页阈值（`pageTouchSlop` 0–9999） | ✅ | P0-1：驱动 drag 的最小位移 |
| 双指同向翻页 | ❌ | |
| 音量键翻页（含「朗读时音量键翻页」「按键长按翻页」） | ❌ **已整体删除** | iOS 拦音量键只能靠隐藏的 `MPVolumeView`，而它的 slider 一写入就真改系统音量，实测每按一次音量被压低一截直到 0；代价大于收益，代码与三个开关全部移除（`UPDATE_LOG.md` 偏离表 #7/#16） |
| 自定义翻页按键（`prevKeys`/`nextKeys`） | ❌ | |
| 键盘：Space / PageUp / PageDown / Menu | ❌ | |
| 鼠标滚轮翻页 | ❌ | |
| 耳机/媒体按键控制朗读 | ✅ | P0-6：`MPRemoteCommandCenter` play/pause/next/previous |
| 长按 600ms 选择文本（词边界扩展 + 双把手） | ❌ | |
| 禁用返回键开关 | ❌ | 开关已存进 `ReaderPrefs`，iOS 无对应行为，面板里未暴露（`UPDATE_LOG.md` 偏离表 #13） |

### 5.2 翻页动画与屏幕

| Android | iOS |
|---|---|
| 5 种动画：覆盖 / 滑动 / 仿真 / 滚动 / 无动画 | ✅ 5 项可选（`PageAnim.allCases` 全列在样式面板）；`simulation` 的渲染路径降级为 `slide`（`UPDATE_LOG.md` 偏离表 #1） |
| 每本书单独覆盖翻页动画（`menu_page_anim`） | ❌ |
| 动画时长 / 禁用滚动点击动画 | ❌ |
| 屏幕常亮（默认/1min/5min/10min/常亮） | ✅ | `keepLight` + `isIdleTimerDisabled`；非「常亮」档到时交还系统熄屏权 |
| 隐藏状态栏 / 隐藏导航栏 / 沉浸模式 | ⚠️ | `hideStatusBar` 已接 `.statusBarHidden`；导航栏/沉浸由 iOS 决定，无对应 API |
| 扩展到刘海 / 填充刘海区域 | ❌ |
| 屏幕方向（跟随系统/竖/横/传感器/反向竖） | ❌ | `ReaderPrefs.screenOrientation` 字段存在，但**全 App 无任何 UI 与生效逻辑**（「更多设置」面板不含此项） |
| 平板·横屏双页（4 种模式） | ❌ |
| 亮度：自动亮度 + 竖条滑块 + 日/夜分别记忆 + 左右换位 | ❌ **已主动删除** | 走 iOS 系统控制中心调亮度；App 内的亮度条与系统能力重复，且实现有视觉缺陷（见 `UPDATE_LOG.md` 偏离表 #8） |
| 显示亮度调节控件开关 | ❌ | 随亮度功能一起删除 |
| 进度条行为（调整本章页数 / 调整章节位置 + 跳转确认） | ✅ | `MoreSettingsPanel` 可切换按页/按章，翻页模式下 Slider 支持按页调节 |

### 5.3 顶部栏（Android `title_bar` + `title_bar_addition`）

| Android 控件 | 二级 | iOS |
|---|---|---|
| 书名 → 打开详情页 | ✅ | P0-1：顶栏书名 → 详情页 |
| 章节名 → 浏览器打开 / 长按选外部浏览器 | | ❌ |
| 章节 URL → 浏览器打开 | | ❌ |
| 书源按钮 → 登录 / 购买 / 编辑书源 / 禁用书源 | | ❌ |
| 换源（长按：单章换源 / 整书换源） | ✅ | P0-4：`ChangeSourceSheet` 两模式；入口在阅读页溢出菜单「来源」分区 + 书籍详情页来源行与菜单 |
| 刷新（长按：刷新本章 / 之后章节 / 全部章节） | ⚠️ | 有「刷新本章」（清缓存重取）；按区间刷新未做 |
| 离线缓存（章节区间对话框） | ✅ | 阅读页溢出菜单「离线下载章节...」支持选择起止章节滑块或后续 50/100/全部下载，后台并发抓取并防爬虫限流 |
| 本地书：设置编码（可搜索编码表） | | ❌ |
| 本地 TXT：TXT 目录规则 | ✅ | 本地 TXT 导入与详情页菜单均支持选择 TXT 目录规则正则表达式重新切章 |

### 5.4 溢出菜单（`book_read.xml` 全 20 项）

| 项 | iOS |
|---|---|
| 添加书签 | ✅ | P0-3 |
| 编辑内容（改写本章正文/标题，可保存·重置·拷贝） | ❌ | `ClickActionCode.editContent` 已可选但无实现 |
| 翻页动画（本书） | ✅ | P0-1：样式面板内单选，写 `pageAnim` |
| 拉取云端进度 / 覆盖云端进度 | ⚠️ iOS 有自动 WebDAV 进度同步，但无手动双向入口 |
| 反转内容 | ❌ |
| 模拟追读（开关 + 开始日期 + 起始章节 + 日更章数） | ❌ |
| 替换净化（可勾选） | ✅ | P0-5：`Book.useReplaceRule` + 菜单勾选 |
| 移除重复标题（可勾选） | ✅ | P0-5：`ContentProcessor` 第 1 步 |
| 重新分段（可勾选） | ⚠️ | 只做「按空行重排+合并碎行」简化版（`UPDATE_LOG.md` 偏离表 #3） |
| 图片样式：默认 / 完整 / 纯文字 / 单图 | ✅ | `ReadImageStyle` 四 case（`standard`/`full`/`textOnly`/`singleImage`）已接通正文渲染：`.textOnly` 过滤插图、`.full` 铺满；`.standard` 与 `.singleImage` 走同一渲染路径 |
| 删除 ruby 标签 / 删除 h 标签（EPUB） | ❌ |
| 更新目录 | ✅（在详情页菜单） |
| 起效的替换（列出本章命中规则，可点进编辑） | ✅ | P0-5：`EffectiveReplacesSheet` |
| 设置源变量 / 书籍变量 | ✅ | `BookDetailView` 与 `SourceDetailView` 菜单均提供「设置书籍变量」与「设置源变量」编辑弹窗并持久化 |
| 日志 / 帮助 | ❌ |

### 5.5 中部悬浮按钮（Android 4 个 mini FAB）

| 按钮 | iOS |
|---|---|
| 全文搜索 | ⚠️ | 支持已加载正文、目录标题搜索与联网「查字典」三 Tab |
| 自动翻页 | ✅ | 溢出菜单「开启/停止自动翻页」+ 悬浮条（`-1s`/`+1s`，2–30s） |
| 替换净化 | ✅ | P0-5：直达面板 |
| 深色模式切换 | ✅ | P0-1：样式面板主题行含「跟随系统/日/夜」 |

### 5.6 底部栏

| Android | iOS |
|---|---|
| 上一章 / 下一章 | ✅ |
| 阅读进度 Slider | ✅ |
| 目录 | ✅ |
| 朗读（点击播放，长按展开控制面板） | ✅ | P0-6：`ReadAloudPanel` |
| 界面（阅读样式面板） | ✅ | P0-1：`ReadStylePanel` |
| 设置（更多设置面板，30+ 项） | ⚠️ | `MoreSettingsPanel` 已建，只放**真生效**的项（`UPDATE_LOG.md` 偏离表 #13） |

### 5.7 「阅读样式」面板（Android `ReadStyleDialog`）

| 组件 | iOS |
|---|---|
| 顶部 5 快捷按钮：粗细（正常/粗体/细体）、字体、缩进（0–4 字符）、简/繁转换、边距、信息 | ⚠️ | 有缩进（0–4）、简/繁三档、**字体选择器**（系统/楷体/宋体/圆体，写 `textFont`）；粗细快捷、信息对话框仍缺（`ReadStyleConfig.textBold` 字段已存但无 UI） |
| 4 条滑杆：字号 / 字距（−0.5~+0.5）/ 行距 / 段距 | ✅ | P0-1：四条全在 `ReadStylePanel`，字距走 CoreText `kern`（iOS 16+ 生效） |
| 翻页动画单选（5 项） | ✅ | 5 项可选，仿真降级为滑动（`UPDATE_LOG.md` 偏离表 #1） |
| 「文字颜色和背景」样式横滚列表（可新建、长按编辑、日/夜/EInk 三套、共用布局） | ⚠️ | 有 6 套内置主题（白/羊皮纸/护眼/暗黑/水墨屏/自定义）横滚选择 + 自定义 Hex 背景/文字色；**无新建命名样式、无背景图** |
| 样式编辑器：样式名、恢复预设、深色状态栏图标、文字下划线、文字色、背景色、背景透明度、导入/导出、删除、背景图（内置 14 张 + 自选） | ❌ |
| 字体选择对话框（扫描字体目录、系统内置字体样式、默认字体） | ⚠️ | `ReadStylePanel` 提供 4 项硬编码字体（系统/楷体/宋体/圆体），**非**扫描字体目录 |
| 边距对话框（正文 4 + 页眉 4 + 页脚 4 + 两条分隔线开关，共 12 滑杆 2 开关） | ⚠️ | P0-2 把 12 个字段与两条分隔线都存进了 `ReadStyleConfig`（Android 同名键）；「更多设置」面板暴露正文左右/上下四边，页眉/页脚滑杆无 UI |
| 信息（页眉页脚）对话框：标题位置/字号/上下边距；页眉左右中（12 种内容项）、页脚左右中、文字色、分隔线色 | ⚠️ | `headerMode/footerMode/tip*` 与 `ReadTipItem` 12 项枚举已入模型，渲染仍只有「章标题 + 进度」 |

### 5.8 「更多设置」面板（Android `pref_config_read.xml`，30 项）

`MoreSettingsPanel` 已建（P0-1，v0.2.1 起与「界面」共用 `ReaderPanelChrome`：占屏幕下 1/2、贴底、可滚动、全部跟随阅读主题色）。**面板实际条目（逐条核对代码）**：显示组 = 隐藏状态栏 ✅、展示顶部工具栏附加区域 ✅、文字两端对齐 ✅（仅翻页模式）、屏幕常亮 ✅；翻页组 = 滑动翻页阈值 ✅、进度条行为 ✅（按页/按章已接线）；内容组 = 点击区域设置 ✅、简繁转换 ✅、图片样式 ✅、新书默认启用净化 ✅、自动换源 ✅；页边距组 = 左右/上下边距 ✅。

**仍缺且未在面板暴露**（刻意不放死开关）：屏幕方向（`ReaderPrefs.screenOrientation` 存值但**全 App 无任何 UI 与生效逻辑**）、长按选择文本、隐藏导航栏、扩展到刘海 / 填充刘海、平板双页、自定义中文分行、文字底部对齐、鼠标滚轮、禁用滚动点击动画、点击预览图片、绘制优化、禁用返回键、自定义翻页按键、展开选择菜单、工具栏样式跟随、动画时长。其中若干在 iOS 无对应能力。显示亮度调节控件与三个音量键开关随功能删除（`UPDATE_LOG.md` 偏离表 #7/#8）。

### 5.9 书签

| Android | iOS |
|---|---|
| 添加书签（当前页标题+正文） | ✅ | P0-3：`currentPageText()` 取当前页 |
| 书签列表（目录页 Tab）+ 搜索 | ✅ | `BookmarkSheet` + `searchBookmarks` |
| 书签编辑（原文、备注、删除、跳转章节+段内位置） | ✅ | `loadInitialChapter(targetCharPos:)` 还原段内位置 |
| 所有书签页（按书分组 section header） | ❌ | P2 |
| 导出 JSON / 导出 Markdown | ✅ | `exportJSON` / `exportMarkdown` |
| 文本选择 → 快速加书签 | ❌ | 依赖 5.14 文本选择 |
| 书签数据持久化 & 备份（`bookmark.json`） | ✅ | P0-3：以「书名+作者」为 key，换源后书签不丢；键名与 Android 对齐 |

### 5.10 书内找字（`SearchContentActivity`）

| Android | iOS |
|---|---|
| 全书正文联网搜索（多章并发抓取匹配） | ❌ |
| 关键词正则 / 区分大小写 / 全字匹配 | ❌ |
| 结果列表（章节 + 上下文片段高亮）+ 点击跳转 | ⚠️ 仅本章已加载文本逐行匹配 |
| 上一个 / 下一个跳转、当前项高亮 | ❌ |
| 关闭替换净化选项 | ❌ |
| 从文本选择菜单带入关键词 | ❌ |
| 返回时「是否恢复搜索前进度」提醒 | ❌ |

### 5.11 朗读 / 听书（Android 最大子系统之一）

| 能力 | iOS |
|---|---|
| 系统 TTS 播放/暂停/停止 | ✅ `AVSpeechSynthesizer` |
| 朗读控制面板（上一章/下一章/上一句/下一句/播放/停止/目录/主菜单/后台/设置） | ✅ | P0-6：`ReadAloudPanel`，朗读单位=段落（对齐 Android） |
| 定时停止（滑块 0–180 分钟 + 快捷列表 + 保存默认） | ✅ | `ttsTimer` 仅在播放中倒数 |
| 语速调节（SeekBar + 加减按钮 + 跟随系统） | ✅ | `ttsSpeechRate` 0–45 → `(pref+5)/10` 换算，`ttsFollowSys` 开关 |
| 音调调节 | ✅ | `AVSpeechUtterance.pitchMultiplier` |
| 发音人选择（zh-CN 硬编码） | ⚠️ | 语言参数可传，UI 仍默认 zh-CN |
| 多 TTS 引擎列表（系统引擎 + HttpTTS 网络引擎） | ✅ | `AudioBookService.selectedEngineName` + 朗读面板「引擎」菜单（系统原生 / 各 HttpTTS 引擎）；`HttpTTSStore.load()` 解析启用项 |
| **HttpTTS 服务管理页**（名称/URL/内容类型/并发率/登录/请求头 CRUD + 导入导出） | ⚠️ | `HttpTTSListView` + 编辑器已上线（名称/URL/内容类型/请求头 + 导入导出 + 预装默认引擎）；**并发率、登录 URL / loginUi / loginCheckJs、查看·删除登录头 ❌** |
| 逐段朗读 / 按页朗读 | ✅ | P0-6：段落队列 + `readAloudByPage` |
| 当前朗读句高亮 | ⚠️ | 翻页模式可高亮；滚动模式未接 `currentCharPos` |
| 后台播放 + 锁屏 MediaSession + 通知栏控制 | ✅ | Info.plist `UIBackgroundModes: audio` + `MPRemoteCommandCenter` + `nowPlayingInfo`（无通知栏，iOS 锁屏即控制中心） |
| 朗读悬浮控制条（不随菜单/面板收起而消失） | ✅ | v0.2.2：`ReadAloudFloatingBar` 三键 播放/暂停/结束，可见性绑播放状态而非 `showControls` |
| 从**当前页**而非章节开头开始朗读 | ✅ | v0.2.2：`currentAloudStartPos()` 用 `ReadAloudText` 自己的偏移基准把屏幕首段映射进段落队列 |
| 忽略音频焦点 / 来电暂停 / 唤醒锁 | ❌ |
| **音频书播放页**（`AudioPlayActivity`：封面模糊背景、播放/停止、上下章、快进退 0.1X、缓冲进度、定时、倍速、目录、播放模式 4 循环、换源、登录、拷贝播放 URL、编辑书源） | ⚠️ | `AudioPlayView`（~513 行）已上线：黑胶旋转动效、`AVPlayer` 流媒体播放、快进/退 15s、倍速、定时关闭、章节目录；书架与详情页按 `bookSourceType == 1` 或 `kind` 含「音频」自动路由。**缺**：模糊背景、播放模式 4 循环、换源/登录/拷贝播放 URL/编辑书源入口 |
| 网络音频书源（urlRule 直链解析） | ⚠️ | 章节 URL 直接以 `.mp3/.m4a/.aac/.flac` 结尾时直用，否则经 `BookContentService.fetchChapterContent` 取正文作为直链（等价 `urlRule` 语义）；**无独立 `urlRule` 字段解析** |

### 5.12 自动翻页

| Android | iOS |
|---|---|
| 启动 / 停止自动翻页 | ✅ | 溢出菜单「开启/停止自动翻页」（`toggleAutoPageTurn`） |
| 速度滑块（1–30s） | ✅ | 悬浮条 `-1s`/`+1s` 调节，范围 2–30s（`autoTurnIntervalSeconds`） |
| 面板（目录 / 主菜单 / 停止 / 设置翻页动画） | ⚠️ | 悬浮条提供停止与速度调节，无独立面板 |
| 滚动模式逐像素自动滚动 | ⚠️ | 翻页模式 `turnPage(forward:)`；滚动模式退化为 `nextChapter()`（非逐像素平滑滚动） |
| 自动翻页时常亮、弹菜单自动暂停 | ⚠️ | 启动时 `setControls(false)` 收起菜单；**未强制常亮** |

### 5.13 换源对话框

| Android 功能 | iOS |
|---|---|
| 整书换源（当前书并发搜索所有启用源，逐行显示结果） | ✅ | P0-4：`ChangeSourceService` 分块并发 + 每源 60 s 竞速 |
| 单章换源 | ✅ | 按 `ChapterMatcher` 自动映射目标章节（`UPDATE_LOG.md` 偏离表 #9） |
| 筛选框 / 停止·开始搜索 / 书源管理 / 刷新列表 / 校验作者 / 加载字数 / 加载详情页 / 加载目录 / 分组过滤 / 关闭 | ⚠️ | 筛选框 ✅、停止/重新搜索 ✅、校验作者 ✅、加载目录以预估章节 ✅；**书源管理入口、刷新列表、加载字数、加载详情页 ❌**（分组过滤通过关键词匹配 group 字段近似实现） |
| 「当前书源」快捷回位、滚动到顶/底 | ❌ |
| 行长按：置顶 / 置底 / 编辑源 / 禁用源 / 删除源 | ❌ |
| 自动换源（`autoChangeSource`，缺章时后台精确搜索补全） | ✅ | `ReaderView.tryAutoChangeSource`：空正文/取章失败时触发 |
| 批量换源 + 间隔设置 | ❌ | P1 |

### 5.14 文本选择 / 词典 / 翻译

| Android | iOS |
|---|---|
| 长按选词 + 双把手扩缩（跨行跨页） | ❌ | iOS 未接 SwiftUI 文本选择（`ReaderView` 走 CoreText 自绘，无 selection 层） |
| 选择操作菜单：替换 / 复制 / 书签 / 朗读（含两种模式）/ 字典 / 全文搜索 / 浏览器 / 分享 | ❌ |
| 「展开文本选择菜单」开关 | ❌ |
| 词典结果弹窗（多词典 Tab、HTML 渲染、链接可点） | ⚠️ | 阅读器搜索 Sheet 内置「查字典」Tab：多字典切换（`enabledDictRules`）+ `showRule` 提取渲染；**无 HTML 渲染与可点链接** |
| 字典规则管理页 + 编辑器（名称/接口规则/解释规则/启用/排序，导入导出、二维码、剪贴板、拖拽排序） | ⚠️ | `DictRuleListView` + 编辑器（名称/接口 `urlRule` 含 `{{key}}`/解释 `showRule`/启用）+ JSON 导入导出 + 恢复默认（百度汉语/汉典）；**缺排序、二维码、剪贴板、拖拽** |
| 系统「文字操作」`ACTION_PROCESS_TEXT` 集成 | ❌ 🍎 需 App Intents / Share Extension |

### 5.15 漫画模式（`ReadMangaActivity`）

| Android | iOS |
|---|---|
| 条漫长图视图（Webtoon） | ⚠️ | `ChapterImageView` 在滚动模式连续纵向渲染正文插图（跨章自动衔接），可视为条漫基础形态；**无漫画专用布局与预下载** |
| 横向整页翻页 + PagerSnap | ❌ |
| 双击 / 双指缩放、超界回弹 | ⚠️ | 点击图片弹出全屏预览（黑底 + 双向 `ScrollView` 漫游）；**无双指缩放、无回弹** |
| 菜单：预下载 N 页、禁用缩放、禁用点击翻页、自动翻页、开启滚动、翻页速度、横向滚动、禁用水平翻页、禁用翻页动画、页脚配置、滤镜、隐藏标题、墨水屏、墨水屏阈值、图片灰度 | ❌ |
| 页脚配置（章节/章节名/页数/总进度 分别显隐 + 文案 + 对齐） | ❌ |
| 颜色滤镜（亮度 + RGBA 四通道 ColorMatrix） | ❌ |
| 墨水屏二值化 | ❌ |
| 图片缓存保留数量、预加载 | ⚠️ | `ChapterImageView` 有 `NSCache` 内存缓存；**无保留数量设置** |
| 跨章自动衔接、加载更多、重试视图 | ⚠️ | 滚动模式跨章自动衔接 ✅ + 失败重试 ✅；**无「加载更多」** |

### 5.16 图片相关

| Android | iOS |
|---|---|
| 正文插图显示 | ✅ | `ChapterImageView`（含 `Referer` 防盗链） |
| 点击预览图片 / 长按图片弹窗（显示、刷新、保存、菜单、选择目录 + 目录记忆） | ⚠️ | 点击 → 全屏预览 ✅；**长按菜单、刷新、保存、选择目录 ❌** |
| PhotoView 全屏缩放（双指、拖动、旋转、长按保存） | ⚠️ | 全屏预览支持双向滚动漫游；**无双指缩放 / 旋转 / 长按保存** |
| 图片解密（`imageDecode` JS） | ❌ | `ContentRule.imageDecode` 字段可编辑，但**未执行** |
| 图片保存相册 | ❌ 🍎 |

---

## 6. 版面五：发现页 / 分类页

iOS 采用了与 Android 不同的「三级流」设计（Level1 换源胶囊 → Level2 分类标签 + 矩阵抽屉 → Level3 书籍流），核心浏览体验已实现，但与 Android 能力不对等：

| Android 功能 | iOS | 说明 |
|---|---|---|
| 发现首页 = 书源折叠列表（点开源名展开其分类标签） | ⚠️ | 形态不同；iOS 用「胶囊选源 + 分类栏」替代 |
| 顶部搜索框 = **筛选发现源**（按书源名过滤，不搜书） | ❌ | iOS 无发现源过滤（`CategoryExploreView` 无 `searchable`） |
| 右上角「分组」动态子菜单（按 `bookSourceGroup` 过滤有发现功能的分组） | ❌ | |
| 双击 tab 收起当前展开区 | ❌ | |
| 长按书源 → 编辑 / 置顶 / 登录 / 搜索 / 刷新 / 删除 | ⚠️ | iOS 长按菜单在**书源管理页**提供（编辑/置顶/登录/搜索/刷新/删除），发现页本身没有 |
| `exploreUrl` 支持 `<js>` / `@js:` 动态生成 | ✅ | `BookExploreService.parseCategories` 支持 `<js>…</js>` 与 `@js:` 前缀，经 `JSEngine` 求值 |
| exploreUrl 支持 JSON 数组返回（含 `style` 自定义样式） | ⚠️ | iOS 只解析 title/url，**无 FlexChildStyle 颜色/圆角/粗体/字号** |
| 分类解析异常 → `ERROR:xxx` 条目，点击查看堆栈 | ❌ | |
| 分类缓存（MD5 内存缓存 + ACache + Mutex 防并发）+「刷新发现」清缓存 | ⚠️ | iOS 每次进页面重新解析 |
| 发现列表：分页触底加载 + 下拉刷新 + 无更多/错误重试 | ✅ | |
| 书籍卡片：封面 / 书名 / 作者 / 最新章 / 简介 / 分类标签 / **已在书架角标** | ⚠️ | iOS 卡片基本齐全，**缺「加入书架」角标** |
| 点击卡片 → 详情页 | ✅ | |
| 空态「当前没有发现源！」 | ⚠️ | iOS 有各自的空态文案 |
| 403/验证页 → 浏览器过盾后自动重试 | ⚠️ | iOS 只提示「去书源管理登录」，不自动过盾 |
| `enabledExplore` 字段参与过滤 | ✅ | `CategoryExploreView` 已按 `enabledExplore` 过滤，书源编辑与长按菜单可独立开关 |

---

## 7. 版面六：搜索页

| Android 功能 | iOS | 说明 |
|---|---|---|
| 多源并发搜索 + 流式增量结果 | ✅ | iOS 用 `AsyncStream` + `TaskGroup` |
| 结果按 书名+作者 合并去重 | ✅ | P0-7 升级为 `SearchMerger.merge`：`origins` 并集 + 空字段补全 |
| 触底自动搜下一页 / 加载更多分页 | ✅ | |
| 按书源筛选 | ✅ | P0-7：`SearchScope` 三态（全部 / 多分组 / 单书源），胶囊行保留为常用源快捷入口 |
| 搜索范围对话框（分组⇄书源切换 + 筛选 + 全部书源 + 持久化） | ✅ | `SearchScopeSheet`；`searchScope` / `searchGroup` 用 Android 的 `"" / "A,B" / "名::URL"` 格式落盘 |
| **搜索历史**（胶囊展示、按使用时间排序、输入过滤、点击带入、长按爆炸删除、一键清除、持久化 `searchHistory.json`） | ✅ | P0-7：`SearchKeyword{word,usage,lastUseTime}` 键名与 Android 一致；长按→ contextMenu 删除、清除→ confirmationDialog |
| 输入时展示「书架匹配」区块 | ✅ | `SearchBookView.matchedBookshelfBooks`：命中本地书架时展示「书架已有」区块（输入区与结果区各一处） |
| 精准搜索开关（书名/作者必须包含，结果按来源数排序） | ✅ | `SearchMerger.rank` 三桶（等值 / 包含 / 其余），精准时丢「其余」桶 |
| 停止 / 继续搜索 FAB | ✅ | `stopSearch` / `resumeSearch`，结果保留、可续页（Android `isManualStopSearch`） |
| 搜索时线程 pause/resume（退后台挂起） | ❌ | P1 |
| 空结果智能引导弹窗（关精准搜索 / 切全部分组） | ❌ | 见 `UPDATE_LOG.md` 偏离表 #14 |
| 「来源数」徽标（本书被几个源收录） | ✅ | `SearchBook.originCount`，排序即以它为主键 |
| 书源管理入口 / 日志入口 | ⚠️ | 书源管理仍在设置 tab；日志 P1 |
| 「仅在此源搜索」快捷入口 | ✅ | |

---

## 8. 版面七：订阅 / RSS —— 基础闭环已上线，规则层仍有缺口

v0.2.3 起「订阅」为根界面第 3 个 tab，代码位于 `Sources/LegadoApp/Views/RssViews.swift`（`RssSourceListView` / `RssArticleListView` / `RssArticleReaderView` / `RssStarListView` / `RssSourceEditSheet`）、`Sources/LegadoCore/Models/RssModels.swift`、`Sources/LegadoCore/Service/RssService.swift`。以下逐项以代码为准。

### 8.1 订阅首页（RSS tab）

- ✅ 订阅源列表（名称 + 分组胶囊 + URL，`RssSourceListView`）
- ✅ 顶部搜索框（按名称/URL/分组过滤）
- ✅ 右上角：收藏（→`RssStarListView`）/ `⋯` 菜单（新建订阅源 / 导入订阅源 JSON / 恢复默认订阅源 / 导出全部至剪贴板）
- ⚠️ 单击源 → 文章列表（`singleUrl` 字段存在于模型，但**未执行 JS 计算真实 URL**）
- ✅ 长按源：编辑 / 置顶 / 删除（`contextMenu`）
- ❌ 列表头部「规则订阅」入口

### 8.2 文章列表页

- ⚠️ 分类胶囊栏（`RssService.parseCategories` 解析 `sortUrl` 换行 `标题::URL` 格式；**不支持 `<js>` 动态生成，无缓存**）
- ⚠️ 下拉刷新 ✅；`ruleNextPage` 触底翻页 ❌（`fetchArticles(page:)` 已支持 `{{page}}`，但 UI 未接翻页）
- ❌ 三种列表样式切换（左文右图 / 无图 / 双列网格，`articleStyle` 0/1/2）
- ⚠️ 列表显示标题/简介/发布日期/缩略图 ✅；**已读文章置灰 ❌**（`RssArticle.read` 字段存在，UI 未使用）
- ⚠️ 点击进文章 ✅；**自动写阅读记录 ❌**（无 `RssReadRecord` 等价物）
- ❌ 菜单：登录 / 刷新分类 / 设置源变量 / 编辑源 / 切换布局 / 阅读记录 / 清空缓存文章

### 8.3 文章阅读页

iOS 采用**原生 `ScrollView` + 规则提取**（非 WebView），并支持跳转 Safari：

- ⚠️ `ruleContent` 规则抓取 ✅（`RssService.fetchArticleContent` 走 `NetworkClient` + `RuleAnalyzer`）；缓存 description 兜底 ✅；**无「直接 loadUrl」三态决策**
- ❌ 自定义 CSS `style` 注入、默认图片视频宽度压缩
- ❌ 夜间反色、UA / Cookie 应用、`loadWithBaseUrl`、`enableJs`、`injectJs`
- ❌ 资源黑白名单（`contentWhitelist` / `contentBlacklist`）拦截
- ❌ `shouldOverrideUrlLoading` JS 拦截 + JS 桥（`java.searchBook(key)`、`java.addBook(url)`）
- ❌ 非 http scheme → 「跳转其它应用」确认
- ⚠️ 菜单：收藏 ✅（写入 `RssStar`）；**刷新 / 分享 / 网页朗读（TTS）/ 登录 / 浏览器打开 ❌**（Safari 跳转由收藏夹列表的 `Link` 承担）
- ❌ 图片长按保存 + 选择目录（目录记忆）
- ❌ 文件下载（DownloadListener + 后台下载服务 + 通知）
- ❌ 视频全屏（自定义视图 + 横屏 + 常亮）

### 8.4 收藏夹

- ❌ 按分组 Tab 的收藏列表（当前为单列表）
- ❌ 收藏编辑弹窗（改标题、改分组、删除收藏）
- ❌ 菜单：分组跳转 / 删除当前分组 / 删除所有
- ✅ 长按/左滑删除单条（`.onDelete`）
- ✅ `rssStar.json` 备份（已纳入 WebDAV 10 类）

### 8.5 订阅源管理 / 编辑 / 调试

- ⚠️ 订阅源列表管理（搜索 ✅、编辑 ✅、置顶 ✅、删除 ✅；**启用开关 ❌、滑动多选 / 批量启用禁用分组 / 分享 / 区间选中 ❌**）
- ⚠️ 订阅源导入（剪贴板 JSON ✅、恢复默认 ✅；**本地文件 / 网络 URL / 二维码 ❌**）
- ✅ 导出（拷贝全部订阅源 JSON 至剪贴板）
- ⚠️ 订阅源编辑器 `RssSourceEditSheet` 仅 7 字段（sourceName / sourceUrl / sourceGroup / enabled / sortUrl / ruleArticles / ruleTitle / ruleLink）；**缺** sourceIcon、loginUrl、loginUi、header、variableComment、concurrentRate、jsLib、ruleNextPage、rulePubDate、ruleDescription、ruleImage、ruleContent、style、enableJs、loadWithBaseUrl、injectJs、contentWhitelist、contentBlacklist、shouldOverrideUrlLoading
- ❌ 订阅源调试页（列表源码 / 正文源码）
- ❌ 删除源级联删除其缓存文章（`RssArticle` 本就不缓存，故影响有限）

### 8.6 规则订阅（书源/订阅源/替换规则聚合订阅）

- ❌ 规则订阅列表（类型标签 + 名称 + URL、点击导入、编辑、删除、拖拽排序）
- ❌ 添加/编辑对话框（类型三选、名称、URL 查重）
- ❌ `sourceSub.json` 备份（仓库内 `sourceSub` 无任何引用）

---

## 9. 版面八：书源管理页

| Android 功能 | iOS | 说明 |
|---|---|---|
| 列表：名称(分组) + 启用开关 + 编辑 + 更多菜单 | ✅ | iOS 用长按菜单替代 |
| 顶栏搜索框（实时过滤书源，支持 `group:xx` 语法） | ✅ | `.searchable` 支持名称/域名/注释及 `group:xx` 过滤 |
| 排序子菜单：反序 / 手动 / 智能(权重) / 名称 / URL / 最后更新 / 响应时间 / 是否启用 | ❌ | |
| 分组子菜单：分组管理 / 已启用 / 已禁用 / 需要登录 / 未分组 / 已启用发现 / 已禁用发现 / 动态分组 | ⚠️ | 顶部横向分组胶囊栏固定为「全部 / 已启用 / 已禁用」三项（具体分组可通过搜索框 `group:xx` 检索） |
| 按域名分组显示 | ❌ | |
| 新建书源（空白） | ✅ | 右上角菜单「新建空白书源」直接打开 6-Tab 全字段编辑器 |
| 发现状态绿/红角点 | ❌ | |
| 校验结果显示行 + 校验进度条 | ✅ | 顶栏实时校验进度条 + 每行「失效」红标。行内 `ms` 仅在有效测量值时展示(`respondTime < 180000`;Android 的失败罚时 `180000+耗时` 不展示)。**分组胶囊按显示层过滤**(`BookSource.displayGroup`):隐藏 Android 校验判定词与第三方 `good` 标记,源数据本身不改动;每轮的「失效」判定与测量耗时在启动同步后保留 |
| 边缘滑动多选 + 拖拽排序（仅手动排序） | ⚠️ | 支持多选模式（全选/反选），无边缘滑动与拖拽排序 |
| 底部批量：删除 / 全选 / 反选 / 启用所选 / 禁用所选 / 添加分组 / 移除分组 / 启用发现 / 禁用发现 / **校验所选** / 置顶所选 / 置底所选 / 导出所选 / 分享选中源 / 选中所选区间 | ✅ | 右上角 `⋯` 菜单「选择」进入多选，底部批量栏支持全选/反选/启用/禁用/导出 JSON/批量删除 |
| 导入：本地文件 | ✅ | |
| 导入：网络 URL（带历史 URL 管理） | ⚠️ | iOS 有 URL 导入，无历史记录 |
| 导入：剪贴板自动读取 | ⚠️ | iOS 需手动粘贴到 TextEditor |
| 导入：二维码 | ❌ | |
| 导入：旧版格式转换（`myBookShelf.json` / `myBookSource.json`） | ❌ | |
| 导入：逐条勾选 + 新增/更新/已有状态标签 | ❌ | iOS 整包导入，无逐条选择 |
| 导入选项：自定义源分组 / 选中新增源 / 选中更新源 / 保留原名 / 保留分组 / 保留启用状态 | ❌ | |
| 导入：18+ 域名黑名单拦截 | ❌ | |
| 导入：`legado://` / `yuedu://` scheme 一键导入 + 自动类型识别 | ⚠️ | `Info.plist` 注册了两个 scheme，`LegadoApp.onOpenURL` → `handleIncomingURL` 解析 `?src=` / `?url=` 并**下载导入书源 JSON**；无自动类型识别（其余类型 ❌） |
| 导出书源（`bookSource.json` / 导出选中 / 直链上传 / 分享） | ✅ | 支持单源、选中源、全量源 JSON 导出 |
| **校验书源**（并发线程、超时、校验项 搜索/发现/详情/目录/正文、失效分组自动打标签、失败原因写注释、响应时间写回、前台服务 + 通知可取消、完成后自动筛选「失效」） | ✅ | 并发搜索校验、写回 `respondTime`、自动标记「失效」分组、可随时停止 |
| 校验设置对话框（超时秒数 + 校验项目联动） | ❌ | |
| 书源分组管理对话框（添加/重命名/删除，同步所有源） | ❌ | |
| 帮助页（首次进入自动弹） | ❌ | |

**iOS 现状**：已具备「实时搜索（含 `group:`）+ 三态分组胶囊过滤（全部/已启用/已禁用）+ 右上角二级菜单『选择』多选批量启/禁/删/导 + 并发校验与「失效」标记（源数据不改动,分组噪声仅在显示层过滤） + 长按单源菜单（编辑/置顶/发现开关/登录/搜索/刷新/拷贝 JSON/删除）+ 导入(文件/URL/粘贴)」。

---

## 10. 版面九：书源编辑页（已升级为 6-Tab 全字段编辑器）

`EditSourceSheet.swift` 已升级为与 Android 对齐的 6-Tab（基本 / 搜索 / 发现 / 详情 / 目录 / 正文）全规则字段编辑器，并支持整源 JSON 剪贴板导入/导出与一键启动调试。

### 10.1 顶部公共控件

| Android | iOS |
|---|---|
| 类型（文本 / 音频 / 图片 / 文件） | ✅（Picker 0/1/2/3） |
| 启用 / 发现 / CookieJar 复选 | ⚠️ | 启用书源 + 启用发现两个 Toggle 已实现；**CookieJar 复选 ❌**（模型无 `enabledCookieJar` 字段） |
| 6 个 Tab：基本 / 搜索 / 发现 / 详情 / 目录 / 正文 | ✅ |
| 规则自动补全（`@xx:` 前缀 `RuleComplete`） | ❌ |

### 10.2 字段级覆盖

| Tab | Android 字段 | iOS |
|---|---|---|
| 基本 | bookSourceUrl、sourceName、sourceGroup、sourceComment、loginUrl、loginUi、loginCheckJs、coverDecodeJs、bookUrlPattern、header、variableComment | ✅ 全部可编辑 |
| 搜索 | searchUrl、checkKeyWord、bookList、name、author、kind、wordCount、lastChapter、intro、coverUrl、bookUrl | ✅ 全部可编辑 |
| 发现 | exploreUrl、bookList、name、author、kind、wordCount、lastChapter、intro、coverUrl、bookUrl | ✅ 全部可编辑 |
| 详情 | init、name、author、kind、wordCount、lastChapter、intro、coverUrl、tocUrl | ✅ 全部可编辑 |
| 目录 | preUpdateJs、chapterList、chapterName、chapterUrl、formatJs、isVolume、updateTime、isVip、nextTocUrl | ✅ 全部可编辑 |
| 正文 | content、title、nextContentUrl、webJs、sourceRegex、replaceRegex、imageStyle、imageDecode | ✅ 全部可编辑 |

### 10.3 编辑器菜单

| Android | iOS |
|---|---|
| 保存（含 name/url 非空校验、lastUpdateTime 刷新） | ✅ |
| 调试源 | ✅（`SourceDebugSheet` 四阶段实时调试） |
| 登录 | ⚠️ 在书源详情页/书源管理页/阅读器溢出菜单有登录 |
| 拷贝源 / 粘贴源（整包 JSON） | ✅（右上角菜单支持拷贝整源 JSON / 从剪贴板粘贴整源 JSON） |
| 语法高亮与键盘上方辅助符号条 | ❌ |

---

## 11. 版面十：书源调试页（`SourceDebugSheet` 已实现核心四步调试）

- ✅ 输入搜索关键字自动执行「1. 搜索列表 → 2. 书籍详情 → 3. 目录解析 → 4. 首章正文」全链路四阶段实测
- ✅ 流式输出每阶段耗时（`ms`）、解析字段摘要、首末章信息与正文预览，错误阶段标红定位
- ✅ 可从书源管理页长按菜单「调试该源」或书源编辑器右上角菜单「调试该书源」直接启动
- ❌ 各阶段原始 HTML 源码独立查看器、WebSocket 在线调试
- ❌ WebSocket 版在线调试（`/bookSourceDebug`、`/rssSourceDebug`、`/searchBook`）

---

## 12. 版面十一：登录 / 内置浏览器 / 扫码

| 功能 | iOS | 说明 |
|---|---|---|
| 表单式登录（`loginUi` RowUi JSON 动态渲染 text/password/button + JS action） | ⚠️ | iOS `SourceLoginSheet` 解析 `loginUi` 字段并执行 loginUrl JS，基本可用；缺 button 的 flex 样式与 URL 动作 |
| WebView Cookie 登录 + 保存 Cookie 回写 | ✅ | iOS 甚至额外做了 Cookie 镜像到 `HTTPCookieStorage` |
| 登录头查看 / 删除 / 日志菜单 | ❌ | |
| `loginCheckJs` 执行 | ❌ | |
| 登录信息缓存与「已登录」状态 | ⚠️ | iOS 有打码凭证摘要与注销 |
| **通用内置浏览器 `WebViewActivity`** | ❌ | 前进/后退/刷新/完成、浏览器打开、拷贝 URL、全屏、禁用源、删除源、**Cloudflare 过盾自动重试**、图片长按保存、文件下载、scheme 拦截 |
| 源验证（403/验证页自动拉起浏览器过盾后重取正文） | ❌ | |
| 打开外部链接确认弹窗（「xx 正在请求跳转链接/应用，是否跳转？」+ 禁用源/删除源） | ❌ | |
| **二维码扫描页**（仅 QR、全区域识别、停止分析防重复） | ❌ | 🍎 需 `AVFoundation` + 相机权限文案 |
| 二维码 **从相册导入** | ❌ | |
| 二维码被各页调用（书源/订阅源/替换/字典/TXT目录/调试） | ❌ | |

---

## 13. 版面十二：「我的」页 —— iOS 以「设置」tab 替代，覆盖面仍小

iOS 没有独立「我的」页，而是把设置做成了第 4 个 tab（`SettingsView`）。当前设置页实际分区（逐条核对代码）：**书源管理**（→`SourceManagerView`）、**书架与存储**（→所有书签 `AllBookmarksView`、→阅读记录 `ReadRecordListView`、清理缓存）、**外观模式**（跟随系统/浅色/深色）、**数据与局域网服务**（→`WebDAVSyncView`、→`LocalWebServerView`）、**正文处理**（→`ReplaceRuleListView`、→`TxtTocRuleListView`、→`DictRuleListView`、→`HttpTTSListView`）、**关于 Legado iOS**（应用名称 / 当前版本 / 内核引擎）。

Android `pref_main.xml` 全量条目对比：

| 条目 | 跳转 | iOS |
|---|---|---|
| 帮助（appHelp.md 渲染） | | ❌ |
| 书源管理 | | ✅（设置 tab） |
| TXT 目录规则 | | ✅（设置 tab「正文处理」，`TxtTocRuleListView`） |
| 替换净化 | | ✅（设置 tab「正文处理」，`ReplaceRuleListView`） |
| 字典规则 | | ✅（设置 tab「正文处理」，`DictRuleListView`） |
| HttpTTS | | ✅（设置 tab「正文处理」，`HttpTTSListView`） |
| 主题模式（跟随系统/亮/暗/E-Ink） | | ⚠️ App 外观 3 档（跟随系统/浅/深）；**阅读器主题含 水墨屏 E-Ink 与自定义配色**（`ReaderTheme` 6 套），全局 E-Ink 仍缺 |
| Web 服务开关（长按复制地址/浏览器打开） | | ⚠️ 有「WiFi 传书 / Web 服务」入口与开关（`LocalWebServerView`），**无长按复制地址/浏览器打开** |
| 备份与恢复 | | ✅（WebDAV 同步 + 本地 zip 导出/导入） |
| 主题设置 | | ❌（独立主题列表/样式编辑器） |
| 其它设置 | | ❌ |
| 书签（所有书签） | | ✅（设置 tab「书架与存储」，`AllBookmarksView`） |
| 阅读记录 | | ✅（设置 tab「书架与存储」，`ReadRecordListView`） |
| 文件管理 | | ❌ |
| 关于 | | ⚠️ 仅应用名称 / 版本号 / 内核引擎，无菜单条目 |
| 退出 | | ❌ |

---

## 14. 版面十三：设置 · 其它设置（Android 约 35 项，iOS 约 3 项）

**顶层**：语言（跟随系统/简中/繁中/英文，切换后重启）❌ 🍎（iOS 应走 per-app language）

**分组「主界面」**：自动刷新 ❌、自动跳转最近阅读 ❌、显示发现 ❌、显示订阅 ❌、默认主页 ❌

**分组「其它设置」**

| 设置项 | iOS |
|---|---|
| 设置本地密码（备份敏感信息 AES） | ❌ |
| 用户代理（自定义 UA） | ❌（iOS 硬编码 iPhone Safari UA） |
| WebService 唤醒锁 | ❌ |
| 书籍保存位置 | ❌ |
| 源编辑框最大行数 | ❌ |
| 校验设置（超时 + 校验项目） | ❌ |
| 直链上传规则（上传 URL / 下载 URL 规则 / 注释 / 是否压缩 + 测试 + 拷贝粘贴导入默认） | ❌ |
| Cronet 网络组件 | ❌（🍎 无对应） |
| 抗锯齿 | ❌ |
| 图片绘制缓存（1–1024MB） | ❌ |
| 漫画保留数量 | ❌ |
| 预下载（0–9999 章） | ⚠️ `BookContentService.preDownloadChapters(around:count:)` 硬编码 ±10 章，无 UI |
| 默认启用替换净化 | ✅ | `ReaderPrefs.replaceEnableDefault`（「更多设置」面板「新书默认启用净化」） |
| 全程响应耳机按键 / 耳机按键启动朗读 | ⚠️ | `MPRemoteCommandCenter` 已接 play/pause/next/previous；**无独立开关** |
| 忽略音频焦点 | ❌ |
| 自动清除过期搜索数据 | ❌ |
| 返回时提示放入书架 | ❌ |
| 检查更新查找版本（当前/正式/测试/共存） | ❌ |
| 漫画浏览 | ❌ |
| Web 端口（1024–60000，默认 1122） | ⚠️ `LocalWebServer` 固定 1122（`start(port:)` 可传参，UI 不可改） |
| 清理缓存 | ✅ | 设置页「清理阅读缓存」真正删除章节与图片缓存；书架批量栏「清理缓存」按书清理 |
| 清除 WebView 数据 | ❌ |
| 压缩数据库 | ❌ 🍎（iOS 用 UserDefaults，无 DB） |
| 更新和搜索线程数（1–999，默认 16） | ❌ |
| 文字操作显示搜索 | ❌ |
| 记录日志 / 记录堆转储 | ❌ |

---

## 15. 版面十四：设置 · 主题 / 外观（iOS 仅「跟随系统/浅/深」）

| 功能 | iOS |
|---|---|
| 切换桌面图标（7 个 launcher 变体） | ❌ 🍎（iOS 可用 alternate app icon API） |
| 启动界面样式页（自定义欢迎图 + 显示文字 + 显示图标，日/夜两套） | ❌ |
| 沉浸式状态栏 / 沉浸式导航栏 | ❌ |
| 导航栏阴影（elevation 0–32 + 默认） | ❌ |
| 字体大小（App 全局缩放 0.8–1.6） | ❌（iOS 应走 DynamicType `preferredFont`） |
| 封面设置页（见 §17） | ❌ |
| **主题列表**（应用主题、分享、删除、剪贴板导入、内置 4 套预设：默认/典雅蓝/黑白/A屏黑） | ⚠️ | 阅读界面支持 6 套预设（默认白/复古羊皮纸/护眼绿/夜间暗黑/**水墨屏**/自定义）+ 「自定义」背景色与文字色 Hex；**无分享/删除/剪贴板导入/命名样式** |
| 夜间组：以上全部对称 | ❌ |
| E-Ink 主题模式（去阴影去彩色） | ⚠️ 阅读器主题 `ReaderTheme.eink`（纯白底纯黑字）；**全局** E-Ink 仍缺 |
| 内置 14 张阅读背景图（午后沙滩/宁静夜色/山水墨影/…） | ❌ |

---

## 16. 版面十五：备份与恢复 / WebDAV

iOS 这块是**做得最好的部分**（Android 兼容 zip、历史备份选择、进度同步），但覆盖面窄。

### 16.1 已对齐

| 功能 | iOS |
|---|---|
| WebDAV 服务器地址 / 账号 / 密码 / 子目录 / 设备名称 | ✅ |
| 连接测试（PROPFIND + 404 自动 MKCOL） | ✅ |
| 备份文件命名 `backup<yyyy-MM-dd>-<设备>.zip` | ✅ |
| 云端历史备份列表（日期 + 体积，降序）选择恢复 | ✅ |
| 从本地导入 Android 备份 zip（含 `bookProgress/`） | ✅ |
| 阅读进度实时上传 + 拉取合并（`bookProgress/<书名>_<作者>.json`） | ✅ |
| 同步阅读进度 / 同步增强 开关 | ⚠️ iOS 有自动同步，无独立开关 |

### 16.2 缺口

| Android | iOS |
|---|---|
| 备份 **21 类成员**：`bookshelf` `bookmark` `bookGroup` `bookSource` `rssSources` `rssStar` `replaceRule` `readRecord` `searchHistory` `sourceSub` `txtTocRule` `httpTTS` `keyboardAssists` `dictRule` `servers` `directLinkUploadRule` `readConfig` `shareReadConfig` `themeConfig` `coverRule` `config.xml` | ⚠️ **已支持 10 类**：`bookshelf.json`、`bookSource.json`、`bookmark.json`、`replaceRule.json`、`searchHistory.json`、`readConfig.json`、`txtTocRule.json`、`readRecord.json`、`rssSources.json`、`rssStar.json`（+ `bookProgress/`）。缺：`bookGroup`（书架分组）、`httpTTS`、`dictRule`、`sourceSub`、`keyboardAssists`、`servers`、`directLinkUploadRule`、`shareReadConfig`、`themeConfig`、`coverRule`、`config.xml` |
| 备份时上传阅读背景图到 WebDAV `background/`（去重） | ❌ |
| `config.xml` 内 WebDAV 密码与 servers 的 **AES 加密（本地密码）** | ❌（iOS 明文存 UserDefaults） |
| 本地备份（不依赖 WebDAV，写到本地目录 / 只保留最新 `backup.zip`） | ⚠️ `WebDAVSyncView` 支持导出/导入本地 `backup*.zip`（`fileExporter`/`fileImporter`），**无「只保留最新」自动清理** |
| 自动备份（每天一次，App 退出触发） | ❌ |
| **恢复忽略列表**（8 项多选：阅读界面设置/主题模式/主题配置/封面设置/书架布局/显示订阅/线程数/本地书籍） | ❌ |
| 导入旧版数据（`myBookShelf.json` / `myBookSource.json` / `myBookReplaceRule.json` + 规则语法转换） | ❌ |
| WebDAV 目录结构预建 4 个目录（根 / bookProgress / books / background） | ⚠️ iOS 只建根与进度 |
| 多服务器管理（`servers.json`，远程书籍页的 `ServersDialog`） | ❌ |
| 恢复成功后的 `applyDayNight` + 图标重设 | ❌ |
| 首次进入自动弹 webDavHelp | ❌ |
| 日志入口 | ❌ |
| 坚果云文件数限制提示 | ❌ |

---

## 17. 版面十六：设置 · 封面

| 项 | iOS |
|---|---|
| 仅 WiFi 加载封面 | ❌ |
| 封面规则（启用 / 搜索 URL / 封面 URL 规则 + 恢复默认） | ❌ |
| 总是使用默认封面 | ❌ |
| 白天：默认封面图 / 显示书名 / 显示作者 | ❌ |
| 夜间：默认封面图 / 显示书名 / 显示作者 | ❌ |
| 封面磁盘缓存（避免每次重新请求） | ❌ iOS 用 `AsyncImage` 无持久缓存 |

---

## 18. 版面十七：规则管理类页面（iOS 全部缺失）

### 18.1 替换净化（`ReplaceRuleActivity` + `ReplaceEditActivity`）—— **P0-5 已落地核心**

- ✅ 规则列表：启用开关、规则名+分组、编辑、删除（`ReplaceRuleListView`）；导入/导出 JSON
- ✅ 规则编辑器：规则名称、分组、替换为、替换内容、正则替换、作用于标题、作用于正文
- ✅ 净化管线（`ContentProcessor.process`，7 步与 Android `ContentProcessor.getContent` 同序）：
  去除与标题重复正文开头 → 简繁转换 → 逐行 trim + 按 `order` 升序应用规则（超时自动禁用）→
  标题规则 → ` ` 处理 → 首行缩进
- ✅ 「起效的替换」查看（`EffectiveReplacesSheet`）
- ✅ 「默认启用替换净化」`replaceEnableDefault`；单书开关 `Book.useReplaceRule`
- ✅ `replaceRegex` 的 `pattern##replacement##pattern##replacement…` 链式语义
- ⚠️ 超时后行为与 Android 不同：取消任务 + 禁用该规则 + 丢弃其结果，不写回正文、不杀进程（`UPDATE_LOG.md` 偏离表 #4）
- ❌ 长按多选、滑动框选、拖拽排序（模型层 `moveReplaceRule` 已具备）、本地/网络/二维码导入、
  分组过滤菜单、键盘辅助符号条、排除范围 / 超时时间字段、`@js:` 之外的 JS 变量注入
- ⚠️ iOS 仍保留「重新分段」开关位但只做简化版（`UPDATE_LOG.md` 偏离表 #3）

### 18.2 字典规则（`DictRuleListView` + `DictRuleEditSheet`）—— **已实现**

- ✅ 字典规则列表：启用开关、规则名+接口、编辑、删除；导入/导出 JSON、恢复默认字典规则（百度汉语 / 汉典）
- ✅ 字典规则编辑器：字典名称、接口地址（支持 `{{key}}`）、解释提取规则（`showRule`）
- ✅ 阅读器内查词：搜索 Sheet 内置「查字典」Tab，输入词语联网发起请求并按 `showRule` 抽取渲染释义

### 18.3 TXT 目录规则（`TxtTocRuleListView` + `TxtTocRuleEditSheet`）—— **已实现**

- ✅ 目录规则列表：启用开关、规则名+正则、示例、编辑、删除；导入/导出 JSON、恢复默认规则（标准章回节卷、Chapter、纯数字、大写分卷）
- ✅ 目录规则编辑器：规则名称、正则表达式、示例标题、启用开关
- ✅ 本地 TXT 导入与切章联动：导入 TXT 时按启用的规则自动优选切章；书籍详情页菜单支持选择指定规则一键重新切章
### 18.4 HttpTTS 朗读服务（`HttpTTSListView`）—— **已实现**

- ✅ 服务列表管理（选中、编辑、删除、添加、恢复默认引擎、导入/导出 JSON）
- ⚠️ 编辑器字段：名称 / URL / 内容类型 / 请求头（Header）已支持；**并发率、登录 URL、登录 UI、登录检查 JS、查看·删除登录头 ❌**
- ✅ 引擎选择（`AudioBookService.selectedEngineName` + 朗读面板「引擎」菜单，在系统原生 TTS 与各 HttpTTS 引擎间切换）
- ❌ 「书」/「全局」/「取消」三按钮作用域对话框（iOS 为单一全局选择）

### 18.5 辅助按键配置（`KeyboardAssist`）

- ❌ 快捷符号增删改排序 + 导入默认 + `keyboardAssists.json` 备份（仓库内无任何引用）

---

## 19. 版面十八：文件管理 / 阅读记录 / 所有书签 / 关于

### 19.1 文件管理（Android 侧本身很简洁）

- ❌ 私有目录浏览 + 面包屑路径栏 + `..` 返回上级
- ❌ 顶部筛选框
- ❌ 目录/文件排序（目录在前按名称）
- ❌ 单击文件用系统能力打开（🍎 需 QuickLook）
- ❌ 长按删除
- ❌ 自带文件夹/文件选择器 `FilePickerDialog`（创建文件夹、按扩展名置灰、确定）
- ❌ `HandleFileContract` 五种模式（DIR / FILE / DIR_SYS / EXPORT / IMAGE）+「系统选择器 / 自带选择器 / 手动输入路径」

### 19.2 阅读记录（`ReadRecordListView`）—— **已实现**

- ✅ 按书统计阅读累计时长（小时与分钟）与上次阅读时间，顶部展示总阅读时间与读过书籍总数
- ✅ 阅读器自动计时：阅读器挂载到页面时自动累计阅读时长并持久化写入 `ReadRecordStore`
- ✅ 顶部关键词搜索过滤书籍、左滑删除单本记录、一键清空全部阅读记录

### 19.3 所有书签（`AllBookmarksView`）—— **已实现**

- ✅ 设置页「所有书签」统一入口，按「书名 · 作者」分组展示全站书签
- ✅ 关键词全局搜索（书名、章节、摘录内容、用户笔记）
- ✅ 单条书签点击编辑备注、左滑/长按删除
- ✅ 右上角导出菜单：一键将全站书签导出为 JSON 或 Markdown 格式至系统剪贴板
### 19.4 关于

| 项 | iOS |
|---|---|
| 应用名 + 简介描述 | ⚠️ 仅应用名（`Legado iOS (开源阅读)`）+ 版本 + 内核引擎，无简介描述 |
| 菜单：评分 / 分享下载地址 | ❌ |
| 开发人员 | ❌ |
| 更新日志（`updateLog.md` 渲染，summary=版本号） | ❌ |
| **检查更新**（GitHub Releases API + 版本比较 + 更新弹窗 + 下载） | ❌ |
| 崩溃日志列表 / 清除 | ❌ |
| 保存日志（logs+crash+logcat → zip） | ❌ |
| 创建堆转储 | ❌ 🍎 |
| 用户隐私与协议 | ❌ |
| 开源许可 | ❌ |
| 免责声明 | ❌ |
| 版本号 | ✅ v0.2.1 起改读 `Bundle` 的 `CFBundleShortVersionString`（原先硬编码 1.0.0，与 `VERSION` 矛盾） |

---

## 20. 版面十九：Web 服务 / 局域网 API / 外部集成

| 能力 | iOS | 备注 |
|---|---|---|
| 我的页 Web 服务开关 + 地址摘要 | ⚠️ 设置页「WiFi 传书 / Web 服务」入口（`LocalWebServerView`）：开关 + 显示 `http://<LAN IP>:1122` | 与 Android 的 13+13 REST API 不是同一套 |
| HTTP 接口 13 GET + 13 POST（书源、订阅源、书架、目录、正文、封面、图片、阅读配置、替换规则、进度、本地书上传） | ⚠️ 仅 3 个端点：`GET /`（上传门户 HTML）、`POST /upload`（multipart 传 TXT/EPUB 入库）、`GET /books`（书架 JSON） | 其余端点 ❌ |
| WebSocket（书源调试 / 订阅源调试 / 搜索） | ❌ | |
| 内置 Web 静态页（书架/书源/订阅源管理 SPA、WiFi 传书页、帮助文档站 16 篇 md） | ⚠️ 仅 WiFi 传书上传页（内联 HTML） | 其余 ❌ |
| 通知栏 Web 服务前台通知（IP 列表 + 取消） | ❌ | 🍎 iOS 后台常驻 HTTP server 受严格限制 |
| 快捷开关磁贴 | ❌ | |
| ContentProvider 跨 App API | ❌ | 🍎 无对应 |
| `legado://` / `yuedu://` scheme 导入 10 类内容 | ⚠️ `Info.plist` 已注册 `legado` / `yuedu`，`LegadoApp.onOpenURL` 处理 `?src=` / `?url=` **导入书源 JSON**（单一类型） | 其余 9 类 ❌ |
| 文件类型关联（txt/json/epub/pdf/mobi/azw/azw3/zip/rar/7z） | ⚠️ | iOS 仅能通过 `fileImporter` 主动选取（`.epub` / `.plainText`） |
| Share Intent（分享文本 → 搜索 / URL → 加架） | ❌ | 🍎 需 Share Extension |
| `ACTION_PROCESS_TEXT` 长按文字搜索 | ❌ | 🍎 需 App Intents |
| S-Pen 遥控动作 | ❌ | 🍎 |
| 通知渠道（下载 / 朗读 / Web 服务） | ❌ iOS 完全没有使用任何本地通知 | |
| 前台服务清单（Android manifest 9 个 `<service>`，其中 11 处 `startForeground` 调用） | ❌ | 🍎 需 BGTaskScheduler / AVAudioSession 方案 |
| 下载服务（APK 更新、书、文件，通知栏进度） | ❌ | |

---

## 21. 底层能力缺口（不属于某个版面，但直接决定上面多少功能做不了）

### 21.1 规则引擎

| 语法 | Android | iOS |
|---|---|---|
| CSS 选择器 | ✅ | ✅（含 `@` 链式、`tag.index`、`attr/text/href/src/title/content`） |
| JSONPath | ✅ 完整 | ⚠️ 简化：支持 `$.a.b` `[0]` `[-1]` `[*]` `..`；**不支持过滤 `[?()]`、切片 `[1:3]`** |
| **XPath** | ✅ | ✅（`RuleAnalyzer` 内置 XPath 求值器，支持 `//`、`/`、并集 `|`、谓词 `[@attr=...]`、`[contains(...)]`、`[N]`、`[last()]`、`/text()`、`/@attr` 与 `@XPath:` 前缀） |
| 正则 `##pattern##repl` | ✅ | ✅ |
| `||` 默认值 / `&&` 拼接 / `%%` 多结果 | ✅ | ⚠️ 仅 `||`、`&&`（`RuleAnalyzer` 有对应分支；`%%` 无实现） |
| `>` `<` 默认值运算符组合 | ✅ | ❌ |
| `@js:` / `<js></js>` / `{{模板}}` | ✅ | ✅ |
| `@put/@get`、`@set`、`@temp`、`@java:` | ✅ | ⚠️ 仅 `put/get` |
| `AllInOne` 默认规则 | ✅ | ❌ |
| `@@` / `::` 选项分隔语义 | ✅ | ⚠️ `::` 仅用于 exploreUrl 文本 |
| 规则自动补全 | ✅ | ❌ |

### 21.2 JS 引擎（JSEngine）

- ❌ `jsLib` 外部 JS 库预加载
- ⚠️ `webJs` / `formatJs` / `preUpdateJs` / `coverDecodeJs` / `imageDecode` 仅**可编辑**（`EditSourceSheet`）与**建模**（`RuleModels`），**未执行**；`loginCheckJs` 同样只存不执行
- ❌ `java` 桥大量方法：`getCookie`、`getSession`、`opaqueCache`、`cryptos`(AES/RSA/HMAC)、`qsWithoutEncode`、`okHttpNewCall`、`getBookType`（现有 `java.put` / `java.getString` 两个方法）
- ❌ `String.prototype` 扩展（`toJson()` 等）
- ✅ `book.getVariable / putVariable / setVariable` 与 `source.getVariable / setVariable`（已接通持久化）
- ❌ 独立的 `SharedJsScope` 缓存与失效

### 21.3 网络（NetworkClient）

- ❌ URL 选项 DSL：`@charset`、`@retry`、`@http`、`<js>` 之外的 `GET`/`POST`/`charset`/`headers`/`body`/`type`/`webJs` 关键字写法（iOS 只认 `url,{json}` 一种）
- ✅ 字符集自动识别（P0-8 `CharsetDetector`：BOM → 声明 → HTTP 头 → meta 嗅探 → Foundation 统计 → 候选严格解码打分 → UTF-8 兜底；GBK/Big5 站不再乱码）
- ❌ `concurrentRate` 并发限速
- ⚠️ 重试已做（P0-8：抛错或 5xx 时最多 3 次、间隔 300 ms，4xx 不重试）；自定义超时与代理仍缺
- ❌ `ua` 独立字段（模型中甚至没有 UA 字段）
- ❌ CookieJar 按源开关（`enabledCookieJar`）
- ❌ Cronet / 连接池优化
- ❌ 书籍 URL 正则 `bookUrlPattern`、`downloadUrls`

### 21.4 本地书格式

| 格式 | Android | iOS |
|---|---|---|
| EPUB | ✅ | ✅（EPUB3 nav / EPUB2 NCX / spine fallback / 图片 / 锚点 / 分卷识别） |
| TXT | ✅ | ✅（自动正则切章 + GB18030 回退） |
| MOBI / AZW / AZW3 | ✅ | ❌ |
| UMD | ✅ | ❌ |
| PDF | ✅ | ❌ |
| 压缩包（zip/rar/7z）内选书 | ✅ | ❌ |
| 拆分超长章节 | ✅ | ❌ |
| 章节编码手动切换 | ✅ | ❌ |

### 21.5 数据与持久化

| 数据 | Android | iOS |
|---|---|---|
| 存储方式 | Room + SQLite + SharedPreferences | ⚠️ **UserDefaults 整包 JSON** + 沙盒文件（无 DB） |
| Book / 阅读进度 | ✅ | ✅ |
| BookSource + 登录头 | ✅ | ✅ |
| BookGroup（书架分组） | ✅ | ✅ | `BookGroupStore`（`legado_book_groups_v2`）+ `BookGroupManageSheet`；默认组为 全部 / 书源书籍 / 本地书籍，旧默认组 养肥中/已完结 见 v2 迁移 |
| Bookmark | ✅ | ✅ | P0-3：`BookmarkStore` 持久化到 UserDefaults，键名与 Android `bookmark.json` 对齐 |
| ChapterList（在线书目录入库） | ✅ | ✅ | v0.2.2 起在线书也入库（`chapters_<md5>.json` + 10 分钟节流后台刷新），打开改为缓存优先 |
| ReadRecord | ✅ | ✅ | `ReadRecordStore` 落盘 + 设置页 `ReadRecordListView` 汇总（阅读器自动计时） |
| SearchKeyword（历史） | ✅ | ✅ | P0-7：`SearchHistoryStore` 持久化，键名与 Android `searchHistory.json` 对齐 |
| SearchBook（结果缓存表 + 过期清理） | ✅ | ❌ |
| RssSource / RssArticle / RssStar / RssReadRecord | ✅ | ⚠️ | `RssStore`（`legado_rss_sources_v1` / `legado_rss_stars_v1`）落盘订阅源与收藏；`RssArticle` 为抓取结果不缓存，`RssArticle.read` 字段存在但 UI 未使用，无独立 RssReadRecord |
| ReplaceRule / DictRule / TxtTocRule / HttpTTS / RuleSub / KeyboardAssist | ✅ | ⚠️ | ReplaceRule / DictRule / TxtTocRule / HttpTTS 均已落盘（`ReplaceRuleStore`、`DictRuleStore`、`TxtTocRuleStore`、`HttpTTSStore`，键名与 Android 对齐）；RuleSub / KeyboardAssist ❌ |
| ServerConfig（多 WebDAV） | ✅ | ❌ |
| ThemeConfig / ReadBookConfig / ReadTipConfig | ✅ | ⚠️ | `ReadStyleConfig` 与 `ReaderPrefs` 由 `ReaderStore` 落盘（P0-2 已解决冷启动持久化）；独立主题列表与 TipConfig 仍缺 |
| 缓存变量 / SourceConfig / 大规则数据 | ✅ | ❌ |
| 封面 & 背景图磁盘缓存 | ✅ | ❌ |

### 21.6 其它核心

- ✅ 简繁转换（P0-5：`ChineseConverter`，基于 `CFStringTransform`，支持关闭 / 繁转简 / 简转繁 3 档）
- ❌ 智能分词 / 断行（BreakIterator，选词 & 避头尾）
- ❌ `AnalyzeUrl`（相对路径、变量、分页 `{{page}}`、`<js>` URL）——iOS 有基础相对路径解析与 `{{page}}` 替换，**分页变量能力弱**
- ✅ `nextTocUrl` / `nextContentUrl` 续页（P0-8：正文 50 页 / 目录 200 页硬上限，`nextChapterUrl` 终止，visited 去重）
- ✅ 续页的**总时长预算与截断保护**（v0.2.2：请求超时 30s，目录 120s / 正文 30s 预算；被截断的结果一律不写缓存）
- ✅ `ContentProcessor`（P0-5：正文净化管线已实现）
- ❌ 图片 `ImageProvider` LRU 磁盘+内存缓存（正文插图仅有 `NSCache` 内存缓存）
- ❌ 无障碍（把页面内容给 TalkBack）

---

## 22. 版面间共同缺失的交互原语（建议先做组件）

| Android 通用组件 | iOS 缺失影响 |
|---|---|
| `SelectActionBar`（多选底部栏 + 全选/反选/计数/溢出菜单） | ⚠️ 书架与书源管理已各自内联实现（`batchActionBar` / 书源多选栏）；**替换规则、订阅源、导入仍缺** |
| `DragSelectTouchHelper`（边缘滑动框选） | 书架/书源/替换规则/订阅源批量选择 |
| `GroupManageDialog` / `GroupSelectDialog`（分组 CRUD + 位掩码多选） | ⚠️ 书架分组 CRUD 已实现（`BookGroupManageSheet` + 移入分组对话框，单选分组）；**书源分组、替换规则分组、订阅收藏分组、位掩码多选 ❌** |
| `VariableDialog`（源/书变量编辑） | ✅ 已实现（`BookDetailView` / `SourceDetailView` 的 `VariableEditorSheet`） |
| `NumberPickerDialog`（带「默认」按钮） | 约 15 处数值设置（iOS 用 `Stepper` / `Slider` 内联） |
| `CodeDialog` / 语法高亮编辑器 | 书源编辑、规则编辑、查看 JSON |
| `KeyboardToolPop` + `KeyboardAssistsConfig` | 规则编辑效率 |
| `SourcePickerDialog`（批量换源选源） | 批量换源 |
| `AppLogDialog`（内存日志 + 清除） | 至少 8 处「日志」入口 |
| `PhotoDialog`（缩放图片查看） | ⚠️ 正文插图全屏预览已实现（`ChapterImageView`）；**封面大图、漫画缩放 ❌** |
| `WaitDialog`（可取消进度） | 备份/恢复/加架/换源（iOS 用 `ProgressView` + 可取消 Task） |
| `HelpDialog`（Markdown 渲染，16 篇专题帮助） | 全站帮助 |
| 取色器 `ColorPickerDialog` | 主题、样式（iOS 目前为 Hex 文本输入） |
| 二维码 生成 + 扫描 | 分享/导入 6 处 |

---

## 23. 优先级路线图建议

### P0 — 不做就不能称为「阅读 App」 —— **8 项已全部实现**

1. ✅ **阅读页三级菜单 + 更多设置面板**（§5.2–§5.8）：屏幕常亮、翻页动画、首行缩进、页边距、简繁、点击区域（亮度与音量键翻页后来被删除，见 `UPDATE_LOG.md` 偏离表 #7/#8）
2. ✅ **配置持久化修复**：字号/行距/主题此前不写盘（§21.5），现由 `ReadStyleConfig` + `ReaderStore` 落盘
3. ✅ **书签体系**（§5.9）
4. ✅ **整书换源 + 单章换源 + 自动换源**（§5.13、§4.1）
5. ✅ **替换净化**（§18.1）
6. ✅ **朗读控制面板**：语速、定时、上一段/下一段、后台播放（§5.11）
7. ✅ **搜索范围 + 搜索历史**（§7）
8. ✅ **字符集自动识别 + `nextContentUrl`/`nextTocUrl`**（§21.3/§21.6）

遗留（不影响「能用」，影响「对齐」）：滚动模式朗读高亮、`.editContent`/`.syncProgress` 两个动作码（`ClickActionCode` 可选但 `handleClickAction` 为 `break`）、顶栏换源/刷新图标（当前只在溢出菜单）。`progressBarBehavior` 接线已于 v0.2.3 完成。

> 说明：本清单早期版本引用 `plan.md §10 #N` / `§12.1`。v0.2.3 把 `plan.md` 重写为 Part 1-18 的实施设计与文件清单，原 §10「有意偏离 Android 的地方」与 §12「P0 实施状态」已归档，**内容迁移到 `UPDATE_LOG.md` 的「关键设计决策与 Android 偏离备忘」表**（#1–#16）；本文件的所有偏离引用已改指该表。历史版本仍可从 git 取：`git show 07d052c:plan.md`。

### P1 — 生态兼容与可维护性

9. **书源编辑器全字段（6 Tab）**（§10）——最高优先的「写源」能力
10. **书源调试页**（§11）+ **校验书源**（§9）
11. **书架分组 + 网格视图 + 排序 + 书架布局对话框**（§3.4–§3.5）
12. **书架管理多选 + 批量操作**（§3.6）
13. **添加本地（文件树 + 排序 + 智能扫描）** 与 **远程书籍 WebDAV 浏览**（§3.7）
14. **书籍信息编辑页 + 换封面 + 置顶 + 分享**（§4.2–§4.3）
15. **备份覆盖 21 类 + 恢复忽略列表 + 本地备份 + 自动备份**（§16.2）
16. **TXT 目录规则管理页**（§18.3）
17. **二维码扫描/生成 + 各页导入导出**（§12）

### P2 — 完整对齐

18. **RSS 订阅核心模块**：⚠️ **部分落地** —— 独立「订阅」Tab 已支持源管理、分类解析、文章流、正文规则抓取、收藏夹与 10 类 WebDAV 备份；**缺**订阅源全字段编辑器、调试页、文章样式/翻页/已读置灰、规则订阅聚合（§8）
19. **我的页 + 设置中心**：⚠️ 4 Tab 架构已成型；设置页已收敛书源、书架与存储（所有书签/阅读记录）、外观模式、云备份与局域网服务、正文处理（净化/TXT目录/字典/HttpTTS）等入口；**「我的」独立页与其它设置全量条目仍缺**（§13/§14）
20. **主题系统**：⚠️ 阅读器 6 套预设（含水墨屏）+ Hex 背景/文字色自定义；书架 3 列网格 + 4 种排序；**独立主题列表/样式编辑器/背景图 ❌**（§15）
21. **所有书签 / 阅读记录**：✅ 已在设置页实现完整版面；关于页已展示 Bundle 版本与内核说明
22. **HttpTTS 服务管理 + 音频书播放页**：⚠️ `HttpTTSStore` + 设置管理页 + 系统/网络双 TTS 引擎 + `AudioPlayView` 独立有声书播放器均已上线；**HttpTTS 登录/并发率字段与音频页换源/登录/循环模式仍缺**（§5.11、§18.4）
23. **漫画模式**：⚠️ `ChapterImageView` 支持滚动模式连续纵向渲染与点击全屏预览；**无漫画专用布局、双指缩放、预下载、滤镜/墨水屏二值化**（§5.15）
24. **词典取词**：⚠️ 字典规则管理 CRUD 与阅读器「查字典」Tab 已实现；**长按选词与选择菜单仍缺**（§5.14、§18.2）
25. **离线缓存与导出**：✅ 阅读器溢出菜单「离线下载章节...」区间缓存已实现；本地 10 类数据 zip 备份导出已实现
### P3 — Android 专属，iOS 需重新定义

26. 局域网 Web 服务 / WebSocket 调试 / WiFi 传书（§20）——评估 iOS 后台限制后决定是否降级为「文件 App 共享」或 Mac 端工具
27. ContentProvider → App Intents；Share Intent → Share Extension；`legado://` → URL Scheme + Universal Links；PROCESS_TEXT → App Intents
28. 桌面 Widget（书架封面墙 / 最后阅读）、App Shortcuts、后台音频 + CarPlay

---

## 24. 附录 A：历史 Bug 清单（均已修复）与 README 不符项

以下四行为 v0.2.1 实测发现、**已由批次 P0.5 全部修复**的底层问题，保留作回归参考：

| 位置 | 问题（→ 状态） |
|---|---|
| `ReaderView`（v0.2.1 实测） | **离线进入阅读器会卡住**：目录抓取失败时 `loadFailureView` 替换整块画布，3×3 点击区与滑动手势一起消失，唯一能呼出菜单的只有 26pt 高的 `fixedBottomStatusBar`；且「重试」调的是 `loadInitialChapter`，其首行 `guard !chapters.isEmpty` 让它成为死按钮 → **已修复（P0.5 A，v0.2.2）** |
| `ReaderView.loadTOCAndStart` | **网络书的目录从不落盘**：`BookStore.getChapters/saveChapters` 早已存在但只有本地书读它，阅读器抓到后也不回写 → 每次打开必联网、离线即不可用 → **已修复（P0.5 B，v0.2.2 `TocCache`）** |
| `NetworkClient.performOnce` | 未设 `timeoutInterval`（默认 60s），且目录续页 200 页串行无总时长预算 → 慢源最坏可拖数分钟 → **已修复（P0.5 C，v0.2.2：`requestTimeout = 30s` + 目录 120s / 正文 30s 预算）** |
| `ReaderView`（章节级失败） | 正文取失败也用整块失败页盖掉，Android 是 `upMsg()` 当页文本渲染、不打断阅读 → **已修复（P0.5 D，v0.2.2）** |

| 位置 | 问题 |
|---|---|
| `ReaderView.bottomAnchored` | ~~有限 `maxHeight` 的面板（更多设置 / 朗读）悬在屏幕中段而不是贴底~~ **已修复**：`.frame(maxHeight:)` 加在了 `VStack { Spacer; panel }` 整体上，而它会把内容居中；上限应加在内容自身 |
| ~~`SettingsView` 「清理阅读缓存」是 no-op~~ | **已修复（P0-5）**：现在真正删除缓存目录，并在删除前统计释放空间；书籍详情里的单书清除保留 |
| `README.md` 阅读器「覆盖翻页 / 左右平滑翻页 / 纵向连续滚动 三种模式」 | **P0-1 已补**：`PageAnim` 5 case（覆盖/滑动/仿真/滚动/无动画）+ 动画过渡；仿真按 `UPDATE_LOG.md` 偏离表 #1 降级为滑动。README 的措辞现在基本成立 |
| `README.md`「随心调节 字号、行距、内边距与避头尾规则」 | **P0-1/P0-2 已补**：字号/行距/字距/段距/内边距均有控件并持久化；避头尾仍无独立开关（CoreText 默认行为） |
| `README.md`「机翻机器人书源深度集成个人中心（阅读历史、默认收藏夹）」 | **已从 README 删除该说法**（v0.2.1）：确实**无「我的/个人中心」tab、无阅读历史、无收藏夹**，属 P2 |
| `README.md` 架构图「BookDetailView（目录、简介、**换源**、缓存清理）」 | **已修复**：`BookDetailView` 现已接入整书换源入口（来源行按钮 + 右上角菜单） |
| `README.md`「一键导入剪贴板」「批量更新书源」 | 剪贴板需**手动粘贴**到 TextEditor；**批量校验书源与多选管理已实现** |
| `README.md`「完整支持标准 ZIP 备份格式，保留 100% 书籍元数据」 | **已扩充至 10 类成员**：`bookshelf.json`、`bookSource.json`、`bookmark.json`、`replaceRule.json`、`searchHistory.json`、`readConfig.json`、`txtTocRule.json`、`readRecord.json`、`rssSources.json`、`rssStar.json`（+ `bookProgress/`） |
| `README.md` 主题命名（柔光暗调 / 护眼草绿 等） | ~~写「四套」~~ **已修复（2026-10-13 复核）**：README 已改为 6 套纯色主题（默认白/复古羊皮纸/护眼绿/夜间暗黑/水墨屏/自定义），**无背景图**；透明度（`bgAlpha`）与持久化已由 P0-2 解决 |
| `README.md` 架构图 Services 行列出的 `VolumeKeyObserver` | ~~不存在~~ **已修复（2026-10-13 复核）**：架构图该行已删除 `VolumeKeyObserver`（音量键翻页整体移除，见偏离表 #7） |
| `README.md` 测试例数（原第 42 行「196 例，确定性 191 例」/ 架构图「176 例」） | ~~过时~~ **已修复（2026-10-13 复核）**：两处均改为「224 例（确定性 219 例 + 联网冒烟 5 例）」，与 `swift test --skip LiveSourceTests` 实测一致 |
| ~~`SettingsView.swift`「当前版本 1.0.0」与 `VERSION` 文件自相矛盾~~ | **已修复（v0.2.1）**：改读 `Bundle.main` 的 `CFBundleShortVersionString`，UI 不再可能落后于 `MARKETING_VERSION` |
| ~~`RuleTokenizer.swift` 定义了 `case xpath(String)`，但 `RuleAnalyzer` 从不执行 XPath~~ | **已修复**：`RuleAnalyzer` 已实现完整 XPath 求值分支（含并集 `|`） |
| ~~`JSEngine` `book.getVariable / book.setVariable` 是空桩~~ | **已修复**：`Book.variableMap` 与 `JSEngine` 已实现跨调用变量读写与持久化 |
| `BookSource` 模型 | 缺 `ua`、`jsLib`、`enabledCookieJar`、`ruleReview`、`payAction` 等字段（`bookUrlPattern` / `exploreScreen` / `weight` / `loginCheckJs` / `coverDecodeJs` **已建模**，`bookUrlPattern` 未参与匹配逻辑） |
| ~~`CategoryExploreView` `enabledExplore` 未被用于过滤发现源~~ | **已修复**：已按 `enabledExplore` 过滤并在书源编辑/菜单提供开关 |
| ~~`Info.plist` `UIApplicationShortcutItems` 声明了快捷操作但无处理~~ | **已修复**：新增 `LegadoAppDelegate`（仅提供 `UISceneConfiguration` 挂载 scene delegate）+ `LegadoSceneDelegate.windowScene(_:performActionFor:)`（App Shortcut 属场景级事件）+ `LaunchRouter` + `LaunchIntent`（纯数据映射与「最近阅读」解析，可单测）。「搜索书籍」→ 分类 tab；「继续阅读」→ 打开 `durChapterTime` 最新的书。`LaunchIntentTests` 覆盖类型映射与选书边界 |

## 25. 附录 B：iOS 做得比 Android 更好的地方（保留）

- 左滑删除书籍、长按进详情（Android 需进管理页多选删除）
- 「分类」三级流（源胶囊 → 分类矩阵 → 书籍流）比 Android 的发现折叠列表更适合触屏
- WebDAV 备份包秒级完成（Android 串行网络循环 30s+）
- 登录 WebView 的 **Cookie 双域镜像到 `HTTPCookieStorage.shared`**，后续 URLSession 请求自动携带，比 Android 手动同步 CookieStore 更干净
- ESJ Zone 双域（one/cc）一键切换（虽为硬编码）
- EPUB 分卷连贯性处理（解决多卷小说卷标导致目录断连）

---

## 26. 附录 C：数字摘要

| 指标 | Android | iOS |
|---|---|---|
| 源码文件 | 805 Kotlin（`app/`；含 `modules/` 844） | **66 Swift**（LegadoCore 34 + LegadoApp 32；v0.2.0 前 32） |
| 源码行数 | — | **≈23,800 行** |
| 布局 XML | 184 | 纯代码 SwiftUI |
| Activity | Manifest 声明 50 个 `<activity>`（44 个 `*Activity` 类；62 个含 `class .*Activity` 的文件） | — （`Views/` 下 13 个顶层 View 文件，全模块 66 个 `: View` 结构体） |
| Fragment | 23 个 `*Fragment.kt` | — |
| Room 实体 / DAO | 21 / 21（`@Entity` / `@Dao` 标注） | 0（UserDefaults 整包 JSON） |
| 前台服务 | Manifest 声明 9 个 `<service>`（11 处 `startForeground` 调用） | 0 |
| 偏好设置项（`PreferKey` 常量） | 182 | `ReadStyleConfig` **51** 项 + `ReaderPrefs` **25** 项（均由 `ReaderStore` 落盘） |
| 备份数据类 | 21 | **10**（bookshelf / bookSource / bookmark / replaceRule / searchHistory / readConfig / txtTocRule / readRecord / rssSources / rssStar） |
| 规则管理页（书源/订阅/替换/字典/TXT/HttpTTS/规则订阅） | 7 | **5**（书源 + 替换规则 + TXT目录 + 字典 + HttpTTS） |
| 底部 tab | 4 | 4（书架 / 分类 / 订阅 / 设置） |
| 测试 | — | 13 文件 / **224 例**（确定性 219，`LiveSourceTests` 5 例联网冒烟） |
