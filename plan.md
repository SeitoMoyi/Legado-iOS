# Legado iOS v0.2.3 迭代实施计划 (Plan.md)

> 配套文档：
> - 功能差距清单：[FEATURE_GAP_ANALYSIS.md](FEATURE_GAP_ANALYSIS.md)
> - 历史版本记录：[UPDATE_LOG.md](UPDATE_LOG.md)
>
> **目标版本**：`v0.2.3`
> **核心定位**：清理 P0 遗留底层暗坑、打通全部断头 UI 接线、补齐「书源管理页（搜索/分组/多选/导出/并发校验）」高频刚需。
> **工程约束**：保持 100% 纯 Swift，不引入任何新第三方 SPM 依赖；同时通过 macOS (`swift build` / `swift test`) 与 iOS (`xcodebuild`) 双平台编译与单测门禁。
>
> **状态**：Part 1-18 已随 **v0.2.3** 发布，逐项落地记录见 [UPDATE_LOG.md](UPDATE_LOG.md)；本文件保留为实施设计与文件清单。

---

## 一、 迭代范围总览

| 阶段 | 模块 | 核心改动点 | 涉及文件 |
|---|---|---|---|
| **Part 1** | **底层静默 Bug 与数据安全修复** | 1.1 `RuleAnalyzer` 补齐 XPath 执行引擎<br>1.2 `WebDAVService` 备份/恢复扩充至 6 类核心数据<br>1.3 `JSEngine` 接通 `book.getVariable` / `setVariable`<br>1.4 `enabledExplore` 发现源过滤与开关 | `RuleTokenizer.swift`<br>`RuleAnalyzer.swift`<br>`WebDAVService.swift`<br>`JSEngine.swift`<br>`CategoryExploreView.swift` |
| **Part 2** | **UI 断点闭环与阅读器细节完善** | 2.1 `BookDetailView` 接入「整书换源」按钮与 Sheet<br>2.2 目录列表增强（自动定位当前章、正倒序切换、已缓存图标）<br>2.3 阅读器 `progressBarBehavior`（按页/按章）与 `imageStyle`（纯文字/单图等）接线 | `BookDetailView.swift`<br>`ReaderView.swift`<br>`MoreSettingsPanel.swift`<br>`BookContentService.swift` |
| **Part 3** | **书源管理页全面升级 (P1 核心)** | 3.1 实时搜索过滤（支持名称/URL/`group:xx`）+ 分组胶囊栏<br>3.2 多选批量操作（全选/反选/启用/禁用/删除/导出 JSON）<br>3.3 并发书源有效性与响应耗时校验（自动标记失效源） | `SourceManagerView.swift`<br>`BookStore.swift` |

---

## 二、 详细技术方案

### Part 1：底层静默 Bug 与数据安全修复

#### 1.1 XPath 规则执行引擎 (`RuleAnalyzer.swift`)
- **问题**：`RuleTokenizer` 已将 `//`、`/`、`@XPath:` 识别为 `RuleStep.StepType.xpath(String)`，但 `RuleAnalyzer` 的 `getElements` 和 `getStringList` 中完全遗漏了 `.xpath` 分支，导致所有 XPath 书源静默返回空。
- **方案**：
  - 在不引入 C 桥接或外部依赖的前提下，在 `RuleAnalyzer` 内实现轻量级 **XPath → SwiftSoup Elements 转换与求值器**，覆盖 Legado 书源 95%+ 的 XPath 语法：
    - 识别并剥离 `@XPath:` 前缀（在 `RuleTokenizer` 中兼容 `@XPath:` / `@xpath:`）；
    - 支持轴路径 `//tag`（后代）、`/tag`（直接子元素）、`*` 通配；
    - 支持谓词：`[@id='xx']`、`[@class='xx']`、`[contains(@class, 'xx')]`、`[contains(text(), 'xx')]`、`[position()=N]` / `[N]`（1-based 索引）及 `[last()]` / `[last()-N]`；
    - 支持尾部提取器：`/text()`、`/node()`、`/@href`、`/@src`、`/@attr`（自动映射为属性提取步骤）。
- **验证**：新增 XPath 专项单测，验证列表提取、属性提取、`text()` 提取、谓词过滤与索引定位。

#### 1.2 WebDAV 备份与恢复扩充 (`WebDAVService.swift` & `BookStore.swift`)
- **问题**：目前 `createBackupZip` 与 `restoreFromZip` 仅处理 `bookshelf.json` 和 `bookSource.json`，丢弃了已实现且键名对齐 Android 的书签、替换规则、搜索历史和阅读样式配置。
- **方案**：
  - `createBackupZip` 扩展可选参数（带默认值保持向后兼容）：
    - `bookmark.json`（`[Bookmark]`）
    - `replaceRule.json`（`[ReplaceRule]`）
    - `searchHistory.json`（`[SearchKeyword]`）
    - `readConfig.json`（`ReadStyleConfig`）
  - `restoreFromZip` 与 `restore` 返回扩展结构体 `BackupRestorePayload`（同时保留旧版元组接口或平滑升级调用方 `WebDAVSyncView` / `BookStore`），恢复时合并书签、替换规则、搜索历史并刷新 `ReaderConfig`。
- **验证**：单元测试断言打包后的 ZIP 内包含上述 6 个标准 JSON 文件，且解压恢复 round-trip 数据无损。

#### 1.3 JS 引擎 `book.getVariable` / `setVariable` 真实持久化 (`JSEngine.swift` & `Book.swift`)
- **问题**：`JSEngine.swift:239-240` 中 `getVariable` 恒返回 `""`，`setVariable` 为空闭包。
- **方案**：
  - 在 `Book` 模型上提供 `customVariableMap` 辅助方法（解析/序列化 `book.variable` JSON 字符串，支持 `getVariable(key)` 与 `putVariable(key, value)`）。
  - 在 `JSEngine.init` 及 `eval` 上下文中注入当前 `book` 变量字典及更新回调，支持：
    - `book.getVariable("custom")` / `book.putVariable("key", "val")` / `book.setVariable("val")`
    - `source.getVariable()` / `source.setVariable("val")`（基于 `UserDefaults` 按 `sourceVariable_<url>` 存储）
- **验证**：单测验证 JS 脚本内读写 `book.putVariable` / `book.getVariable` 可跨调用保持。

#### 1.4 `enabledExplore` 过滤与控制 (`CategoryExploreView.swift` & `SourceManagerView.swift`)
- **问题**：`CategoryExploreView.availableSources` 只检查了 `enabled != false`，忽略了 `enabledExplore`。
- **方案**：
  - `CategoryExploreView.availableSources` 改为 `(s.enabled ?? true) && (s.enabledExplore ?? true) && !(s.exploreUrl ?? "").isEmpty`。
  - `BookStore` 增加 `toggleSourceExplore(sourceUrl:)`；`SourceManagerView` 长按菜单增加「启用/禁用发现」操作。

---

### Part 2：UI 断点闭环与阅读器细节完善

#### 2.1 书籍详情页换源入口 (`BookDetailView.swift`)
- **方案**：
  - 在 `BookDetailView` 的「书源信息」卡片右侧及导航栏菜单中加入「换源」按钮。
  - 点击弹出 `ChangeSourceSheet(book: currentBook, mode: .wholeBook, ...)`，换源成功后调用 `bookStore.changeSource` 并自动刷新详情页的章节列表。

#### 2.2 目录列表增强 (`BookDetailView.swift` & `ReaderView.swift` & `BookContentService.swift`)
- **方案**：
  - `BookContentService.shared` 提供同步查询方法 `isChapterCached(bookUrl: String, index: Int) -> Bool`（检查 `ChapterCache/<md5>/<index>.txt` 是否存在）。
  - 在详情页目录与阅读器目录 Sheet 中：
    - 打开目录时通过 `ScrollViewReader` 自动滚动定位到 `book.durChapterIndex`（居中显示）；
    - 顶栏增加「正序 / 倒序」切换按钮（`@State private var isReversedTOC = false`）；
    - 已缓存章节右侧显示绿色轻量化缓存标识（`checkmark.icloud` / `arrow.down.circle.fill`），未缓存显示浅灰或留空。

#### 2.3 阅读器 `progressBarBehavior` 与 `imageStyle` 接线 (`ReaderView.swift` & `MoreSettingsPanel.swift`)
- **方案**：
  - **`progressBarBehavior`**：
    - 在 `MoreSettingsPanel` 恢复「进度条行为」选项（`page` 按页 / `chapter` 按章）。
    - 在 `ReaderView` 底栏进度条中：当设为 `"page"` 且处于翻页模式且总页数 > 1 时，Slider 绑定当前章页码（`0 ..< currentPages.count`），左右按钮保持切换上一章/下一章；当设为 `"chapter"` 或处于滚动模式时，Slider 绑定章节索引。
  - **`imageStyle`**：
    - 在 `ReaderView.parseContentBlocks` 或渲染层读取 `readerConfig.prefs.imageStyle`：
      - `.textOnly`（`TEXT`）：过滤掉所有 `[image:...]` 块，纯文本阅读；
      - `.full`（`FULL`）：图片铺满容器宽度；
      - `.single`（`SINGLE`）：图片独立成页（翻页模式下每个图片块单独占一页）。

---

### Part 3：书源管理页全面升级 (`SourceManagerView.swift` & `BookStore.swift`)

#### 3.1 搜索框与分组筛选胶囊栏
- **方案**：
  - 接入 `.searchable(text: $searchText, prompt: "搜索书源名称、域名或 group:分组名")`；
  - 顶部精简为固定 3 个状态分组胶囊：「全部 / 已启用 / 已禁用」。

#### 3.2 多选管理与批量操作
- **方案**：
  - 右上角 `⋯` 菜单内提供二级选项「选择」进入多选模式（多选状态下右上角显示「完成」退出）；
  - 底部浮出批量操作栏 (`SelectActionBar`)：
    - 全选 / 反选（针对当前筛选结果）
    - 批量启用 / 批量禁用
    - 批量导出 JSON（剪贴板拷贝选中书源的格式化 JSON）
    - 批量删除（带确认弹窗）
#### 3.3 并发书源校验 (`SourceValidator`)
- **方案**：
  - 在 `SourceManagerView` 菜单提供「校验当前书源」（针对当前筛选列表或选中书源，测试词默认「我的」）。
  - 使用 `withTaskGroup` 限制并发度（如 6 并发），对每个书源执行 `BookSearchService.shared.searchSingleSource`（15s 超时）：
    - 成功返回非空列表：记录 `respondTime`（毫秒），移除「失效」分组标签；
    - 抛错、超时或结果为空：向该书源的 `bookSourceGroup` 追加「失效」分组标签并记录失败原因；
  - 顶栏实时展示校验进度条（`已校验 X / Y · 失效 Z`）与「停止」按钮。

---

## 三、 验证与门禁标准

1. `swift build`（macOS 目标零错误）
2. `swift test`（全部既有单测 + 新增 XPath / WebDAV 6 类备份 / JS 变量 / 缓存检测单测全部通过）
3. `xcodebuild -project Legado.xcodeproj -scheme LegadoApp -sdk iphonesimulator build`（iOS 模拟器目标零错误，所有新增文件如果创建则通过 `tools/xcode_add_sources.py --check` 校验）
4. 同步更新 `FEATURE_GAP_ANALYSIS.md` 与 `UPDATE_LOG.md` 的完成度状态。

---

## 四、 第二阶段（P1 核心推进）：书架布局与批量管理、6-Tab 书源全字段编辑器与调试台、书籍信息编辑

| 模块 | 核心改进点 | 涉及文件 |
|---|---|---|
| **Part 4：书架布局、排序与多选管理** | 4.1 列表视图 / 三列封面网格视图切换（持久化）<br>4.2 4 种排序方式（最近阅读 / 最近更新 / 书名 / 作者）<br>4.3 右上角 `⋯` 二级菜单「选择」进入书架批量管理（全选/反选/批量清理缓存/批量删除） | `BookshelfView.swift`<br>`BookStore.swift` |
| **Part 5：6-Tab 书源全字段编辑器 + 书源调试台** | 5.1 `EditSourceSheet` 升级为完整 6-Tab（基本 / 搜索 / 发现 / 详情 / 目录 / 正文）全规则字段编辑器 + 整源 JSON 拷贝/粘贴<br>5.2 新增内置「书源调试台 (`SourceDebugSheet`)」：支持输入关键字或 URL，实时流式输出「搜索 → 详情 → 目录 → 正文」四阶段解析结果与耗时 | `EditSourceSheet.swift`<br>`SourceManagerView.swift` |
| **Part 6：书籍详情编辑与快捷操作** | 6.1 `BookDetailView` 新增「编辑书籍信息 (`BookInfoEditSheet`)」：支持自定义书名、作者、封面 URL、内容简介<br>6.2 右上角菜单补齐「置顶本书」、「拷贝书籍/目录 URL」 | `BookDetailView.swift`<br>`Book.swift` |

---

## 五、 第三阶段：全部书签管理、本地备份导出、搜索页书架匹配与源/书变量编辑

| 模块 | 核心改进点 | 涉及文件 |
|---|---|---|
| **Part 7：全部书签汇总页 (`AllBookmarksView`)** | 7.1 设置页挂载「所有书签」入口，按「书名 · 作者」分组展示全站书签<br>7.2 支持全局书签内容/备注搜索、编辑/删除书签、一键导出全站书签（JSON / Markdown 至剪贴板） | `SettingsView.swift`<br>`BookmarkSheet.swift` |
| **Part 8：本地备份包导出与恢复 (`LocalBackup`)** | 8.1 `WebDAVSyncView` 增加「生成并导出本地备份包 (`backup*.zip`)」能力（无需配置 WebDAV 即可离线导出/导入完整 6 类数据） | `WebDAVSyncView.swift` |
| **Part 9：搜索页书架匹配区块 (`SearchBookView`)** | 9.1 输入或搜索关键词时，若本地书架存在书名/作者匹配的藏书，在顶部优先展示「书架已有」快捷卡片 | `SearchBookView.swift` |
| **Part 10：源变量与书籍变量编辑弹窗 (`VariableDialog`)** | 10.1 在 `BookDetailView` 菜单提供「设置书籍变量」与「设置源变量」弹窗（显示 `variableComment` 提示，读写持久化变量） | `BookDetailView.swift`<br>`BookStore.swift` |

---

## 六、 第四阶段：TXT 目录拆分规则联动、阅读记录自动计时、字典规则管理与阅读内查词、在线有声书独立播放页、条漫全屏浏览

| 模块 | 核心改进点 | 涉及文件 |
|---|---|---|
| **Part 11：TXT 目录规则管理与动态切章** | 11.1 设置页上线 `TxtTocRuleListView`，支持正则规则增删改查、预装默认规则与 JSON 导入导出<br>11.2 `BookStore.importTxt` 与 `BookDetailView` 支持指定规则重新切章 | `RuleModels.swift`<br>`SettingsView.swift`<br>`BookStore.swift`<br>`BookDetailView.swift` |
| **Part 12：阅读记录自动追踪与统计** | 12.1 `ReaderView` 自动累计有效阅读时长并落盘 `ReadRecordStore`<br>12.2 设置页新增 `ReadRecordListView`，按书展示时长、上次阅读时间与全局总时长汇总 | `RuleModels.swift`<br>`ReaderView.swift`<br>`SettingsView.swift` |
| **Part 13：字典规则管理与阅读器查词 Tab** | 13.1 设置页上线 `DictRuleListView` 与编辑器，内置百度汉语/汉典预设<br>13.2 阅读器搜索 Sheet 扩展「查字典」Tab，支持快速多字典释义提取 | `RuleModels.swift`<br>`SettingsView.swift`<br>`ReaderView.swift` |
| **Part 14：网络音频书独立播放器 (`AudioPlayView`)** | 14.1 新建 `AudioPlayView`，支持封面黑胶旋转、流媒体播放、快进退 15s、倍速调节、定时停止与章节目录<br>14.2 书架与详情页针对 `bookSourceType == 1` 或包含音频标签的书籍自动路由至音频播放器 | `AudioPlayView.swift`<br>`BookshelfView.swift`<br>`BookDetailView.swift` |
| **Part 15：条漫 / 漫画长图全屏与缩放预览** | 15.1 `ChapterImageView` 支持全屏缩放、双向手势滚动与清晰大图预览 | `ReaderView.swift` |
| **Part 16：章节区间离线缓存 (`ChapterRangeDownloadSheet`)** | 16.1 阅读页溢出菜单上线「离线下载章节...」，支持起止章滑块、后续 50/100/全部下载及后台限流下载 | `ReaderView.swift`<br>`BookContentService.swift` |
| **Part 17：书架分组体系 (`BookGroup`)** | 17.1 支持书架顶栏分组横向胶囊切换（全部/本地/自定义分组）<br>17.2 支持自定义分组 CRUD (`BookGroupManageSheet`)，多选模式支持批量移入分组 | `RuleModels.swift`<br>`BookshelfView.swift`<br>`BookStore.swift` |
| **Part 18：WebDAV 完整 8 类数据备份互通** | 18.1 备份/恢复全覆盖：`bookshelf`, `bookSource`, `bookmark`, `replaceRule`, `searchHistory`, `readConfig`, `txtTocRule`, `readRecord`（+ `bookProgress/`） | `WebDAVService.swift`<br>`BookStore.swift`<br>`WebDAVSyncView.swift` |
