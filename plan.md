# Legado iOS 实现计划

> 配套文档：`ios/FEATURE_GAP_ANALYSIS.md`（完整差距清单）。本文件只写**怎么做**，不重复罗列缺口。
>
> 结构：**第一部分 = P0（8 项，本次交付）**；第二/三部分（P1/P2）待 P0 落地后补写。
>
> 硬约束（已核实）：
> - `Package.swift` `swift-tools-version: 5.7`，platforms `.iOS(.v15) / .macOS(.v12)` → **不能用 SwiftData / Observation / Swift Regex**，统一 `ObservableObject` + `NSRegularExpression`。
> - 现有依赖仅 `SwiftSoup 2.6+`、`ZIPFoundation 0.9.16`。P0 **不引入任何新依赖**（简繁转换用系统 `CFStringTransform`，字符集检测用 `NSString.stringEncoding(for:)`）。
> - 持久化沿用现有范式：`UserDefaults` + `JSONEncoder`（`BookStore.swift:9-13,120-130`），不引数据库。
> - 所有落盘的 JSON **键名必须与 Android 实体属性名逐字一致**，否则 WebDAV 备份无法互通（Android 端是 GSON 直接序列化，无字段映射层）。
> - 后台音频需在 `Legado.xcodeproj` 的 Info.plist 加 `UIBackgroundModes: audio` —— **SPM 的 Package.swift 声明不了，必须改 Xcode 工程**。当前 `Sources/LegadoApp/Info.plist` 只有 `NSAppTransportSecurity`，需在此追加。
> - ⚠️ **本工程同时维护 macOS 构建**（`swift build` 当前 macOS 目标通过；12 个文件里已有 `#if os(iOS)` 守卫，`AudioBookService.swift:21-24,41-42` 就是范例）。P0 中所有 iOS-only 能力（亮度、`UIApplication.isIdleTimerDisabled`、`MPVolumeView`、`AVAudioSession`）**必须用 `#if os(iOS)` 包裹并提供 macOS no-op 分支**，否则 `swift build` 与 GitHub Actions 会挂。

### 0.1 语言/依赖边界（实测结论）

已用 `swift 5.7.2` 工具链实机编译验证，P0 **可 100% 纯 Swift 完成**：

| 维度 | 结论 |
|---|---|
| 新增 SPM 依赖 | **0**（沿用 `SwiftSoup` + `ZIPFoundation`，两者皆纯 Swift） |
| 新增 C/ObjC 源文件 / bridging header / modulemap | **0**（`find` 确认当前工程非 Swift 源文件数为 0） |
| 新增 `import` | **只有 `MediaPlayer`**（`MPVolumeView` / `MPRemoteCommandCenter` / `MPNowPlayingInfoCenter`，系统框架，Swift 直接可用） |
| 已在用、P0 继续用的系统框架 | Foundation、UIKit、SwiftUI、CoreText、AVFoundation、JavaScriptCore、WebKit、CryptoKit、UniformTypeIdentifiers |
| 不可避免的「第二语言」 | 仅存在于**数据层**：书源规则里的 JavaScript（`JavaScriptCore` 执行）、正则（`NSRegularExpression`）、CSS/HTML 选择器（`SwiftSoup`）。这是 Legado 生态的格式本身，Android 端同样是 Rhino + JSoup + Java 正则，不可去除 |
| ⚠️ P1 的唯一例外 | **XPath**。Swift 无内置 XPath 实现；若 P1 做书源编辑器要支持 XPath，需 `import libxml2`（iOS SDK **自带** C 库，加一个 20 行的 `module.modulemap` 即可 Swift 调用，仍不引第三方）。不在 P0 范围，但提前标注避免返工 |


---

# 第一部分：P0

## 0. 实施顺序与依赖

按依赖排，不按编号排：

| 步 | 项 | 依赖 | 说明 |
|---|---|---|---|
| 1 | **P0-2 配置持久化 + `ReadStyleConfig` 模型** | — | 所有 UI 面板的地基，先做 |
| 2 | **P0-8 字符集识别 + `nextContentUrl`/`nextTocUrl`** | — | 纯 core 层，直接提升大量书源可用率 |
| 3 | **P0-5 替换净化（`ContentProcessor`）** | 2 | 插在内容管线里，2 完成后管线才稳定 |
| 4 | **P0-1 阅读页菜单骨架 + 样式/更多设置面板** | 1、3 | 面板要读 config、要挂净化开关 |
| 5 | **P0-3 书签** | 1、4 | 挂在菜单骨架上 |
| 6 | **P0-6 朗读面板** | 1、4 | 同上，且要改 `AudioBookService` 结构 |
| 7 | **P0-4 换源** | 2、3 | 换源后要能正确取正文 |
| 8 | **P0-7 搜索范围 + 搜索历史** | — | 独立，可并行 |

### 文件清单

**新增（LegadoCore）**

| 文件 | 内容 |
|---|---|
| `Sources/LegadoCore/Models/ReadConfig.swift` | `ReadStyleConfig`（Android `readConfig.json` 形状）、`ReaderPrefs`（亮度/常亮/点击区域/音量键/简繁/自动换源） |
| `Sources/LegadoCore/Models/Bookmark.swift` | Android `bookmark.json` 形状 |
| `Sources/LegadoCore/Models/ReplaceRule.swift` | Android `replaceRule.json` 形状 |
| `Sources/LegadoCore/Models/SearchKeyword.swift` | Android `searchHistory.json` 形状 |
| `Sources/LegadoCore/Service/ContentProcessor.swift` | 正文净化管线 |
| `Sources/LegadoCore/Service/ChangeSourceService.swift` | 换源候选搜索 + 章节映射 |
| `Sources/LegadoCore/Utils/CharsetDetector.swift` | 字符集探测与解码 |
| `Sources/LegadoCore/Utils/ChineseConverter.swift` | 简繁转换（`CFStringTransform`） |
| `Sources/LegadoCore/Utils/ChapterMatcher.swift` | `getDurChapter` 进度映射 + Jaccard + 中文数字 |

**新增（LegadoApp）**

| 文件 | 内容 |
|---|---|
| `Views/Reader/Panels/ReadStylePanel.swift` | 「界面」样式面板 |
| `Views/Reader/Panels/MoreSettingsPanel.swift` | 「更多设置」面板 |
| `Views/Reader/Panels/ReadAloudPanel.swift` | 朗读控制面板 |
| `Views/Reader/Panels/BrightnessOverlay.swift` | 亮度竖条 |
| `Views/Reader/Panels/TapZoneOverlay.swift` | 3×3 点击区域 + 动作分发 |
| `Views/Reader/Sheets/BookmarkSheet.swift` | 书签列表/编辑 |
| `Views/Reader/Sheets/ChangeSourceSheet.swift` | 整书/单章换源 |
| `Views/Reader/Sheets/EffectiveReplacesSheet.swift` | 「起效的替换」 |
| `Views/Settings/ReplaceRuleListView.swift` | 替换规则列表（含编辑 sheet） |
| `Views/Search/SearchScopeSheet.swift` | 搜索范围选择 |
| `Services/VolumeKeyObserver.swift` | `MPVolumeView` 音量键拦截 |

**修改**

| 文件 | 改动要点 |
|---|---|
| `LegadoApp/Theme/ReaderConfig.swift` | 改为 `ReadStyleConfig` 数组 + 索引 + `ReaderPrefs` 的包装，全部字段落盘 |
| `LegadoApp/Views/Reader/ReaderView.swift` | 菜单骨架、面板挂载、`currentSource` 可变、点击区域、缩进/边距取值、书签/换源/朗读接入 |
| `LegadoApp/Services/BookStore.swift` | 新增 bookmarks / replaceRules / searchHistory 三套 `@Published` + key + save；`changeSource(...)` |
| `LegadoApp/Services/AudioBookService.swift` | 整章单 utterance → 段队列；语速/定时/上下段/后台/锁屏控制 |
| `LegadoApp/Services/SearchViewModel.swift` | `selectedSourceUrl` → `SearchScope`；三桶排序；停止/继续 |
| `LegadoApp/Views/SearchBookView.swift` | 历史 chips、范围入口、精准搜索开关 |
| `LegadoCore/Service/NetworkClient.swift` | 解码走 `CharsetDetector`；`ParsedRequest` 加 `charset`/`retry` |
| `LegadoCore/Service/BookContentService.swift` | 净化插入点、nextUrl 循环、本地 txt 解码 |
| `LegadoCore/Service/BookSearchService.swift` | 并发上限（换源要用） |
| `LegadoCore/Models/Book.swift` | 加 `useReplaceRule`、`customCoverUrl`、`variable` |
| `LegadoCore/Models/BookSource.swift` | 加 `var groups: [String]` 计算属性、`ua` 字段 |
| `Legado.xcodeproj`（Info.plist） | `UIBackgroundModes: audio` |
| `Tests/LegadoCoreTests/LegadoCoreTests.swift` | 见 §9 验证 |

---

## P0-1 阅读页菜单骨架 + 更多设置面板

### 1.1 现状与问题

`ReaderView.swift:91-231` 的 `body` 是一个 `GeometryReader { ZStack { … } }`，overlay 分支只有 4 个：关闭蒙层（:145-154）、`topNavigationBar`（:157-166）、`bottomControlPanel`（:169-178）、`readingSettingsCard`（:181-200）。状态只有一级 `showControls`（:72）+ `showSettings`（:70）。

顶栏右上角是**空占位**（:659），底栏 `bottomActionRow`（:904-958）只有 4 个按钮（目录/搜索/听书/界面）。

### 1.2 目标结构（对齐 Android 三级菜单）

```
ZStack
├── 内容层（infiniteScrollView / pageByPageView）
├── TapZoneOverlay          ← 新增，两种模式共用（见 1.6）
├── BrightnessOverlay       ← 新增（见 1.4）
├── topNavigationBar        ← 扩展（见 1.3）
├── bottomControlPanel      ← 扩展（见 1.3）
├── ReadStylePanel          ← 替换现有 readingSettingsCard
├── MoreSettingsPanel       ← 新增
└── ReadAloudPanel          ← 新增（P0-6）
```

面板状态改为**单一枚举**，避免多个 Bool 互相打架：

```swift
enum ReaderPanel: Equatable { case none, style, moreSettings, aloud, brightness }
@State private var panel: ReaderPanel = .none
@State private var showControls = false      // 一级菜单
```

`showSettings`（:70）删除，由 `panel == .style` 取代；`.sheet($showTOC)` / `.sheet($showSearch)` 保留。

### 1.3 顶栏与底栏按钮

**顶栏**（改 `topNavigationBar` :627）：

| 位置 | 按钮 | 动作 | 依赖 |
|---|---|---|---|
| 左 | ‹ 书架 | `dismiss()` | 现有 |
| 中 | 书名 | 点击 → `BookDetailView` | 现有 |
| 中下（附加区，可关） | 章节名 / 章节 URL | 点击 → 拷贝；长按 → `ShareLink`/外部浏览器 | — |
| 中下 | 书源名按钮 | Menu：登录 / 编辑书源 / 禁用书源 | 现有登录能力 |
| 右 | 换源 | → `ChangeSourceSheet(.wholeBook)`；长按 Menu：单章换源 / 整书换源 | P0-4 |
| 右 | 刷新 | Menu：刷新本章 / 之后章节 / 全部章节（清 `chapterCache` + `BookContentService.clearCache`） | — |
| 右 | ⋯ 溢出 | 见下表 | — |

**溢出菜单**（P0 只做能落地的项，其余标灰或留到 P1）：

| 项 | P0 | 说明 |
|---|---|---|
| 添加书签 | ✅ | P0-3 |
| 替换净化（Toggle） | ✅ | P0-5，写 `book.useReplaceRule` |
| 起效的替换 | ✅ | P0-5，`EffectiveReplacesSheet` |
| 移除重复标题（Toggle） | ✅ | `ContentProcessor` 第 1 步开关 |
| 重新分段（Toggle） | ⚠️ 占位 | 见 §10 降级说明，P0 只做「按空行重排」简化版 |
| 翻页动画（本书） | ✅ | 写 `book.readConfigPageAnim`，覆盖全局 |
| 编辑内容 | ❌ P1 | 需正文回写 + 缓存改写 |
| 拉取/覆盖云端进度 | ❌ P1 | WebDAV 已有自动同步 |
| 图片样式（默认/完整/纯文字/单图） | ✅ | `ContentProcessor` 里控制 `[image:]` 标记是否保留 |
| 更新目录 | ✅ | 重跑 `loadTOCAndStart()` |
| 反转内容 / 模拟追读 / 日志 / 帮助 | ❌ P2 | |

**底栏**（改 `bottomActionRow` :904-958，从 4 个扩到 6 个）：

`目录` | `书签` | `朗读`（点击=播放/暂停，**长按=展开 `ReadAloudPanel`**） | `替换净化` | `界面` | `更多`

`chapterNavigationRow`（:745-790）保留，但进度 Slider 行为按「进度条行为」配置切换（本章页数 / 章节位置），后者首次拖动弹确认 —— 对齐 Android `progressBarBehavior`。

### 1.4 亮度

全工程当前**没有任何亮度代码**。

```swift
// BrightnessOverlay.swift
#if os(iOS)
UIScreen.main.brightness = CGFloat(value) / 255.0   // 0...255 → 0...1
#endif
```

- 竖条 Slider，左右位置可换（`brightnessVwPos`），仅 `panel == .brightness` 时显示。
- `autoBrightness` 开关：开启时读系统亮度且 Slider 禁用。
- 日/夜分别记忆：`brightness` / `nightBrightness`（Android 同名键）。
- macOS 分支隐藏整个控件（无公开 API）。
- 退出阅读器**不恢复**系统亮度（Android 行为一致：`readBrightness` 是持久的）。

### 1.5 屏幕常亮

```swift
.onAppear { UIApplication.shared.isIdleTimerDisabled = prefs.keepScreenOn }
.onChange(of: prefs.keepScreenOn) { UIApplication.shared.isIdleTimerDisabled = $0 }
.onDisappear { UIApplication.shared.isIdleTimerDisabled = false }   // 必须复位
```

整段包 `#if os(iOS)`（macOS 上 `UIApplication.shared` 不存在，直接编译失败）。macOS 等价物是 `IOPMAssertionCreateWithName`，P0 不做，置灰即可。

选项对齐 Android `keep_light`：默认(0) / 1分钟(60) / 5分钟(300) / 10分钟(600) / 常亮(-1)。非「常亮」值需要自己起 `Timer` 到点关屏 —— iOS 无法强制熄屏，**降级为：到时把 `isIdleTimerDisabled` 置 false 交还系统**（记入 §10）。

### 1.6 点击区域自定义

Android 是 3×3 九宫格 + 14 种动作。iOS 现状：`pageByPageView` 硬编码 3 分区（:504-530，30%/40%/30%），滚动模式是整屏一个 tap（:359-364）。

**统一改为一个覆盖层，两种模式共用**：

```swift
// TapZoneOverlay.swift
enum ClickAction: Int, CaseIterable, Codable {
    case menu = 0, nextPage = 1, prevPage = 2, nextChapter = 3, prevChapter = 4,
         aloudPrev = 5, aloudNext = 6, addBookmark = 7, editContent = 8,
         toggleReplace = 9, openToc = 10, openSearch = 11, syncProgress = 12,
         aloudToggle = 13
}
struct TapZoneOverlay: View {
    let actions: [ClickAction]      // 9 个，行优先 TL TC TR / ML MC MR / BL BC BR
    let onAction: (ClickAction) -> Void
    // GeometryReader → 3×3 等分 Rectangle.fill(.clear).contentShape(Rectangle())
    //                    .onTapGesture { onAction(actions[i]) }
}
```

- 默认值与 Android 一致：`[2,2,1, 2,0,1, 2,1,1]`。
- **约束（照抄 Android `AppConfig.kt:606-611`）**：若 9 个值乘积 ≠ 0（没有任何区域是「菜单」），强制把 MC 设为 `menu`，否则用户会被锁死在阅读器里。
- 配置 UI：3×3 网格，每格点开一个 action Picker。
- **不做** Android `trRect` 左边界 0.36 的历史怪癖，用干净三等分（记入 §10）。
- 滚动模式接入后，原来整屏 tap 的 `.onTapGesture`（:359-364）必须删除，否则双重触发。

### 1.7 音量键翻页

iOS 没有 key event。两条路，**按可用性双保险**，整体包在 `#if os(iOS)` 内（`MPVolumeView` 在 macOS 不存在）：

**优先路径 —— iOS 17+ 正规 API**（`AVAudioApplication.addInputVolumeButtonHandler(for:handler:)`）：

```swift
if #available(iOS 17.0, *) {
    upToken = try? AVAudioApplication.shared.addInputVolumeButtonHandler(for: .up) { [weak self] in
        self?.onUp(); return true          // 返回 true = 吞掉，不改系统音量
    }
    downToken = try? AVAudioApplication.shared.addInputVolumeButtonHandler(for: .down) { ... }
}
```

- 需要**活跃的 `AVAudioSession`**，故 `.playback / .spokenAudio` 已在 `AudioBookService.setupAudioSession()`（:20-29）配好，复用即可。
- 退出阅读器必须 `removeInputVolumeButtonHandler(token:)`，否则阅读器关了音量键还失灵。

**降级路径 —— iOS 15/16 用隐藏 `MPVolumeView`**（工程 floor 是 iOS 15，必须留）：

```swift
final class SilentSlider: UISlider { override func point(inside p: CGPoint, with e: UIEvent?) -> Bool { false } }
struct VolumeKeyObserver: UIViewRepresentable {
    var onUp: () -> Void; var onDown: () -> Void
    // makeUIView: MPVolumeView(frame: CGRect(x:-2000,y:-2000,width:1,height:1))
    //             遍历 subviews 找到 UISlider 换成 SilentSlider
    //             .addTarget(.valueChanged) → newValue > oldValue ? onUp() : onDown()
    //             触发后把 slider.value 复位，避免音量真的漂移
}
```

> 注：命令行 `NSClassFromString("MPVolumeView")` 返回 false 只是因为脚本没链接 MediaPlayer 框架，**不代表 API 不存在**；`import MediaPlayer` 后可用。

相关开关：`volumeKeyPage`（默认开）、`volumeKeyPageOnPlay`（默认关，朗读时是否仍翻页）、`keyPageOnLongPress`（长按连翻 vs 600ms 防抖）。

- 防抖：leading-edge 触发 + 600ms 窗口（对齐 Android `keyPageDebounce`）。
- 菜单展开时不拦截（对齐 Android `onKeyDown` 首个判断）→ `panel != .none || showControls` 时直接 return。
- **只能真机验证**，模拟器无音量键。
- macOS 分支：`MPVolumeView`/`AVAudioApplication` 均不可用 → 用 `NSEvent.addLocalMonitorForEvents(matching: .keyDown)` 监听 `NX_KEYTYPE_SOUND_UP/DOWN`（媒体键）或直接置灰该开关。P0 选**置灰**，面板里注明「仅 iOS 可用」。


### 1.8 翻页动画

现状：`PageMode` 只有 2 个 case（`ReaderConfig.swift:30-35`），`turnPage(forward:)`（:585-624）改 `currentPageIndex` 配 `.easeInOut(0.18)`。

**扩展为 Android 的 5 值枚举，Int rawValue 与 Android `PageAnim` 一致**（0覆盖 1滑动 2仿真 3滚动 4无动画）：

```swift
enum PageAnim: Int, CaseIterable, Codable { case cover = 0, slide = 1, simulation = 2, scroll = 3, none = 4 }
```

实现策略（`pageByPageView` :449-550 内）：

| 动画 | 实现 |
|---|---|
| `none` | 直接换 index，无 `withAnimation` |
| `slide` | 双层 ZStack：新页从 `offset(x: ±width)` 推入，旧页同步反向移出；`DragGesture` 的 `translation.width` 直接驱动 offset（跟手），松手按阈值 + 速度决定完成/回弹 |
| `cover` | 旧页固定不动，新页从侧边覆盖上来（只有一层在动） |
| `scroll` | 走现有 `infiniteScrollView`（保持 `PageMode.scroll` 的既有实现） |
| `simulation` | ⚠️ **P0 降级为 `cover`**，UI 里该项标注「暂用覆盖效果」。真实仿真翻页需要 `CATransform3D` + 卷曲 shader，成本远超收益，放 P2 |

- 每本书可覆盖：`Book.readConfigPageAnim: Int?`，nil 时用全局。
- 滚动模式与翻页模式互转时保持阅读位置的逻辑（`handlePageModeChange` :848-902）已存在，动画改造不要破坏它 —— 改造后必须回归测试这条路径。

### 1.9 首行缩进 / 页边距

- **首行缩进**：`parseContentBlocks`（:1396-1444）里 `"　　"` 硬编码在 :1415 / :1430 / :1439-1440。**全部删除**，缩进改由 `ContentProcessor` 第 7 步统一加（见 P0-5），避免两处叠加。UI 提供 5 档：无 / 一 / 二 / 三 / 四字符（`""`、`"　"`…`"　　　　"`）。
- **页边距**：硬编码在 3 处 —— `.padding(24)`（:497-499）、`calculateLayoutMetrics()` 的高度 `-48`（:1484）、`paginate` 的宽度 `-48`（:1537）。改为读 `config.padding{Top,Bottom,Left,Right}`，并让 `calculateLayoutMetrics` 接收 `containerSize` 与 padding 后计算可用宽高。滚动模式的 `.padding` 同步改。
- **行距/段距/字距**：`lineSpacing` 目前只有设置 tab 能调（`SettingsView.swift:62`）。样式面板里补齐 4 条 Slider：字号(5–50)、字距(−0.5…0.5)、行距、段距。字距/段距在 scroll 模式用 `Text` 的 `.kerning()` / 段间 `spacing`；在 pageByPage 模式要传进 `CTTypesetter`（`splitParagraphIntoLines` :1497-1517）的 `kCTTypesetterCharacterSpacingAttribute` 与 `CTParagraphStyle` 的 `lineSpacingMultiple`/`paragraphSpacing`。
- **两端对齐 / 底部对齐**：pageByPage 已用 `CTLineCreateJustifiedLine`（:1992）恒开；改成受 `textFullJustify` 开关控制。scroll 模式的 `Text` 无法两端对齐 → 开关在 scroll 模式下置灰（记入 §10）。

### 1.10 「更多设置」面板条目（P0 范围）

照 `pref_config_read.xml` 挑 iOS 能落地的 18 项，其余留 P1/P2：

屏幕方向 · 屏幕超时 · 隐藏状态栏 · 平板/横屏双页(❌P2) · 进度条行为 · 使用自定义中文分行(❌P2) · 文字两端对齐 · 文字底部对齐(❌P2) · 音量键翻页 · 朗读时音量键翻页 · 按键长按翻页 · 滑动翻页阈值 · 自动换源 · 长按选择文本(❌P1，需 UITextView 选型) · 显示亮度调节控件 · 禁用滚动点击动画 · 点击预览图片 · 点击区域设置 · 禁用返回键 · 展示顶部工具栏附加区域 · 工具栏样式跟随页面

---

## P0-2 配置持久化（地基，先做）

### 2.1 问题

`ReaderConfig.swift:40-42` 的 `fontSize` / `lineSpacing` / `theme` 是裸 `@Published`，**没有 `didSet`**；`init`（:50-57）只读 `pageMode`。结果：用户调好的字号/行距/主题冷启动全部回默认。

### 2.2 方案：引入 Android 兼容的 `ReadStyleConfig`

新建 `Sources/LegadoCore/Models/ReadConfig.swift`，字段名 = Android `help/config/ReadBookConfig.Config` 的属性名（GSON 键名），这样将来 `readConfig.json` 备份可直接互通：

```swift
public struct ReadStyleConfig: Codable, Identifiable {
    public var id: Int { index }          // 供 SwiftUI ForEach
    public var index: Int = 0             // iOS 自用，Android JSON 里没有 → encode 时跳过
    public var name: String = ""
    public var bgStr: String = "#EEEEEE"
    public var bgStrNight: String = "#000000"
    public var bgStrEInk: String = "#FFFFFF"
    public var bgAlpha: Int = 100
    public var bgType: Int = 0            // 0颜色 1内置图 2外部图（P0 只支持 0）
    public var darkStatusIcon: Bool = true
    public var textColor: String = "#3E3D3B"
    public var pageAnim: Int = 0          // PageAnim.rawValue
    public var textFont: String = ""      // P0 只支持 ""=系统
    public var textBold: Int = 0          // 0正常 1粗体 2细体
    public var textSize: Int = 20         // sp → iOS pt 需换算，见下
    public var letterSpacing: Float = 0.1
    public var lineSpacingExtra: Int = 12
    public var paragraphSpacing: Int = 2
    public var paragraphIndent: String = "　　"
    public var titleMode: Int = 0         // 0居左 1居中 2隐藏
    public var titleSize: Int = 0
    public var paddingBottom: Int = 6
    public var paddingLeft: Int = 16
    public var paddingRight: Int = 16
    public var paddingTop: Int = 6
    public var headerMode: Int = 0
    public var footerMode: Int = 0
    public var showHeaderLine: Bool = false
    public var showFooterLine: Bool = true
    public var tipHeaderLeft: Int = 2     // ReadTipConfig.time
    public var tipHeaderMiddle: Int = 0
    public var tipHeaderRight: Int = 3    // battery
    public var tipFooterLeft: Int = 1     // chapterTitle
    public var tipFooterMiddle: Int = 0
    public var tipFooterRight: Int = 6    // pageAndTotal
    // … Night / EInk 变体字段 P0 先不建（iOS 无 E-Ink 模式），P2 补
}
```

**`index` 字段的坑**：Android JSON 里没有它，Codable 会自动写出去。必须自定义 `encode(to:)` 跳过 `index`，并在 `init(from:)` 里容错（`decodeIfPresent`），否则导出的 `readConfig.json` 塞回 Android 会多字段（GSON 会忽略未知字段，其实不炸，但保持干净）。

**字号换算**：Android `textSize` 是 sp（默认 20），iOS 现有 `fontSize` 是 pt（默认 18，范围 12–32）。两者不能直接混用。方案：`ReaderConfig.fontSize` 仍是 pt 作为**唯一真源**，`ReadStyleConfig.textSize` 只在导入/导出 Android 配置时按 `pt = sp * 0.9` 换算，并在代码里写死这个系数 + 注释说明。

**样式 ↔ 现有 4 主题映射**（迁移用，保留旧数据不丢）：

| 现 `ReaderTheme` | → `bgStr` / `textColor` |
|---|---|
| `.white` 默认白 | `#FAFAFA` / `#262626` |
| `.parchment` 复古羊皮纸 | `#F2E6D1` / `#382E26` |
| `.eyeCare` 护眼绿 | `#E0F0E0` / `#264026` |
| `.dark` 夜间暗黑 | `#1F1F1F` / `#CCCCCC` |

### 2.3 `ReaderConfig` 改造

```swift
public final class ReaderConfig: ObservableObject {
    public static let shared = ReaderConfig()
    @Published public var configs: [ReadStyleConfig]      // 至少 1 个
    @Published public var selectedIndex: Int
    @Published public var prefs: ReaderPrefs              // 见下
    public var style: ReadStyleConfig { get set }         // configs[selectedIndex] 的便捷读写
}
```

`ReaderPrefs`（非样式类偏好，Android 键名对齐，存 `config.xml` 语义）：

```swift
public struct ReaderPrefs: Codable {
    var brightness: Int = 128; var nightBrightness: Int = 64
    var brightnessAuto: Bool = true; var brightnessVwPos: Bool = false
    var showBrightnessView: Bool = true
    var keepLight: Int = 0                     // 0默认 60 300 600 -1常亮
    var hideStatusBar: Bool = false
    var screenOrientation: Int = 0
    var progressBarBehavior: Int = 0           // 0本页数 1章节位置
    var textFullJustify: Bool = true; var textBottomJustify: Bool = false
    var volumeKeyPage: Bool = true; var volumeKeyPageOnPlay: Bool = false
    var keyPageOnLongPress: Bool = false; var mouseWheelPage: Bool = true
    var pageTouchSlop: Int = 0
    var autoChangeSource: Bool = false
    var noAnimScrollPage: Bool = false
    var previewImageByClick: Bool = true
    var clickActions: [Int] = [2,2,1, 2,0,1, 2,1,1]
    var disableReturnKey: Bool = false
    var showReadTitleAddition: Bool = true
    var readBarStyleFollowPage: Bool = false
    var chineseConverterType: Int = 0          // 0关 1繁→简 2简→繁
    var replaceEnableDefault: Bool = true
    var ttsSpeechRate: Int = 5                 // 0...45
    var ttsTimer: Int = 0                      // 0...180 分钟
    var ttsFollowSys: Bool = true
    var readAloudByPage: Bool = false
    var searchScope: String = ""; var searchGroup: String = ""
    var precisionSearch: Bool = false
}
```

### 2.4 落盘

- key：`legado_read_config_v1`（`configs` 数组）、`legado_read_style_select_v1`（索引）、`legado_reader_prefs_v1`（`ReaderPrefs`）。
- 写法照抄 `BookStore.saveBookshelf()`（:126-131）：`JSONEncoder` → `UserDefaults.set(data,forKey:)`。
- **每个 `@Published` 都要 `didSet { save() }`**，`save()` 内做 200ms debounce（避免拖 Slider 时每帧写盘）。
- **迁移**：`init` 里若 `legado_read_config_v1` 不存在但旧 `reader_page_mode`（`ReaderConfig.swift:46`）存在 → 构造一个默认 `ReadStyleConfig`，`pageAnim` 由旧值映射（`scroll→3`、`pageByPage→0`），然后删除旧 key。
- `SettingsView.swift:46/62` 现有的字号/行距 Slider 改为绑定 `readerConfig.style.textSize` / `.lineSpacingExtra`，保证两处 UI 同源。

---

## P0-3 书签体系

### 3.1 模型（`bookmark.json` 兼容）

```swift
// Sources/LegadoCore/Models/Bookmark.swift
public struct Bookmark: Codable, Identifiable, Equatable {
    public var time: Int64            // 主键 = 创建毫秒时间戳（Android @PrimaryKey）
    public var bookName: String
    public var bookAuthor: String
    public var chapterIndex: Int
    public var chapterPos: Int        // 章内字符偏移，含标题行
    public var chapterName: String
    public var bookText: String       // 书签所在页/段的原文
    public var content: String        // 用户备注
    public var id: Int64 { time }
}
```

**关联键是 `bookName + bookAuthor`，不是 bookUrl** —— 这是 Android 的设计，好处是换源后书签依然有效。iOS 必须照做，否则 P0-4 换源会把书签全孤立。

### 3.2 存储（BookStore）

照 `bookshelf` 范式（`BookStore.swift:9,12,126`）加：

```swift
@Published private(set) var bookmarks: [Bookmark] = []
private let bookmarksKey = "legado_bookmarks_v1"
func saveBookmarks()
func addBookmark(_ b: Bookmark)                 // 同 time 覆盖
func updateBookmark(_ b: Bookmark)
func deleteBookmark(time: Int64)
func bookmarks(bookName: String, author: String) -> [Bookmark]   // 排序：chapterIndex, chapterPos
func searchBookmarks(bookName:author:key:) -> [Bookmark]         // chapterName/content contains
```

### 3.3 添加书签

`ReaderView` 已有所需数据：`currentChapterIndex`（:56）、`currentChapterCharOffset()`（:1446-1467，翻页模式累加页字符数、滚动模式累加到 `currentReadingBlockId`）。

```swift
func makeBookmark() -> Bookmark {
    Bookmark(time: Int64(Date().timeIntervalSince1970 * 1000),
             bookName: book.name, bookAuthor: book.author,
             chapterIndex: currentChapterIndex,
             chapterPos: currentChapterCharOffset(),
             chapterName: chapters[currentChapterIndex].title,
             bookText: currentPageText().trimmingCharacters(in: .whitespacesAndNewlines),
             content: "")
}
```

`currentPageText()`：翻页模式取 `currentLoadedChapter.pages[currentPageIndex]` 的 blocks 拼接；滚动模式取 `currentReadingBlockId` 对应 block 的文本。

添加后弹 `BookmarkSheet` 让用户填 `content`（对齐 Android：新建也过一遍编辑对话框，可取消）。

### 3.4 跳转还原

现有 `loadInitialChapter(at:targetPageIndex:scrollToTargetEnd:)`（:1238-1334）已经实现了「按 `durChapterPos` 字符偏移定位到页」（:1264-1296）。**把它泛化**：

```swift
func loadInitialChapter(at index: Int, targetCharPos: Int? = nil, targetPageIndex: Int? = nil, scrollToTargetEnd: Bool = false)
```

书签跳转 = `loadInitialChapter(at: bm.chapterIndex, targetCharPos: bm.chapterPos)`。滚动模式则用 `scrollToChapterId` / `ReaderScrollPreferenceKey`（:29-41）机制滚到对应 block。

### 3.5 UI

`BookmarkSheet`：仿 `ChapterListView`（`BookDetailView.swift:537-606`，已带过滤 TextField :556-566）——顶部搜索框、List 行显示 `章节名 / 原文（2行截断）/ 备注`、点击跳转、左滑删除、点行右侧铅笔进编辑。编辑表单：章节名（只读）、原文（只读）、备注（可编辑）、删除/取消/确认。

底栏「书签」按钮 → 该 sheet；溢出菜单「添加书签」→ 直接新建。

**P0 不做**「所有书签」跨书页面（P2），但数据结构已兼容，届时只是换个数据源。

---

## P0-4 换源

### 4.1 现状障碍

`ReaderView.swift:49` 是 `let source: BookSource?`，`effectiveSource`（:51）是 computed。换源必须能改源 → 改为：

```swift
@State private var currentSource: BookSource?
// init 里：_currentSource = State(initialValue: source ?? BookStore.shared.findSource(for: book))
```

所有 `effectiveSource` 引用点换成 `currentSource`。

### 4.2 `ChangeSourceService`

```swift
// Sources/LegadoCore/Service/ChangeSourceService.swift
public final class ChangeSourceService {
    public struct Candidate: Identifiable {
        public let source: BookSource
        public let searchBook: SearchBook
        public var toc: [BookChapter]?          // 可选加载
        public var mappedIndex: Int?
        public var wordCount: Int?
        public var respondTime: Int64?
        public var id: String { source.bookSourceUrl }
    }

    /// 整书换源候选：书名完全相等 + （可选）作者包含
    public func candidates(book: Book, checkAuthor: Bool, sources: [BookSource],
                           maxConcurrent: Int = 8) -> AsyncStream<Candidate>

    /// 自动换源用的精确匹配：书名与作者都完全相等
    public func preciseCandidates(book: Book, sources: [BookSource]) -> AsyncStream<Candidate>
}
```

**候选搜索算法**（对齐 `ChangeBookSourceViewModel`）：

1. 源集合 = 全部 `enabled != false && searchUrl != nil`；若 `prefs.searchGroup` 非空则限该分组（复用 P0-7 的 scope 解析）。
2. `TaskGroup` 并发，**上限 `maxConcurrent`**（现有 `BookSearchService.searchMultiSources` :151-172 是无限并发，需加分批或信号量）。
3. 每源 `withTimeout(60s)` 调 `BookSearchService.search(source:key:page:1)`（:9）。
4. 过滤：`r.name == book.name && (!checkAuthor || clean(r.author).contains(clean(book.author)))`，其中 `clean` = 去掉 `^\s*作\s*者[:：\s]+` 与 `\s+著`（Android `AppPattern.authorRegex`）。
5. 可选加载（三个开关，对齐 Android）：`changeSourceLoadInfo` → `fetchBookDetail` 补 tocUrl；`changeSourceLoadToc` → 拉目录缓存进 `Candidate.toc`；`changeSourceLoadWordCount` → 用映射后的当前章抓正文、过 `ContentProcessor`、取 `count` 作字数。
6. 排序：字数模式优先 `wordCount > 1000`，其余按 `respondTime` 升序。

### 4.3 章节位置映射（最关键，直接决定换源后是否跳错章）

新建 `Sources/LegadoCore/Utils/ChapterMatcher.swift`，**逐字复刻 Android `BookHelp.getDurChapter`**（`help/book/BookHelp.kt:499-555`）：

```swift
public enum ChapterMatcher {
    /// 返回新目录中的章节下标
    public static func mapChapter(oldIndex: Int, oldTitle: String,
                                  oldCount: Int, newToc: [BookChapter]) -> Int
}
```

算法步骤（不可省略，顺序有意义）：

1. `oldIndex <= 0` → 0；`newToc.isEmpty` → `oldIndex`。
2. 比例估算：`est = oldIndex * oldCount / newCount`（注意 `newCount` 为 0 时先返回 `oldIndex`）。
3. 窗口：`lower = max(0, min(oldIndex, est) - 10)`，`upper = min(newToc.count - 1, max(oldIndex, est) + 10)`。
4. 窗口内对 `pureChapterName(title)` 求 **Jaccard 相似度**（字符集合交/并），取最大者 `newIndex` / `nameSim`。
   - `pureChapterName` = 去掉所有非「字母数字 + CJK」的字符。
5. 若 `nameSim < 0.96` 且旧标题能提取章号：
   - 正则1 `.*?第([\d零〇一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]+)[章节篇回集话]`
   - 正则2 开头数字式 `^\s*([\d…]+)`
   - 先全角转半角、去空白，中文数字用 `chineseNumberToInt()` 转换（需自己实现十/百/千/万/亿进位）
   - 窗口内找章号**相等**者，找到即 break；否则取差值最小者。
6. 判定：`nameSim > 0.96 || abs(newNum - oldNum) < 1` → 用 `newIndex`；否则**回退** `min(max(0, newToc.count - 1), oldIndex)`（按原 index 钳位）。

`chapterPos`（章内字符偏移）**原样保留**，不做内容匹配 —— 这是 Android 既有行为，新旧源正文有差异时落点会偏，接受。

单测必须覆盖：等长目录、缩短目录、增长目录、标题带卷号、纯数字标题、中文数字标题、完全不匹配（回退钳位）。

### 4.4 整书换源落库

`BookStore` 新增：

```swift
@discardableResult
func changeSource(oldBook: Book, to newBook: Book, source: BookSource,
                  newToc: [BookChapter], mappedIndex: Int, mappedPos: Int) -> Book
```

步骤：
1. 在 `bookshelf` 中找到 oldBook，**原地替换**（不换数组位置，保留 order）：写入 `newBook` 的 `bookUrl / origin / originName / tocUrl / coverUrl / intro / kind / wordCount / totalChapterNum / latestChapterTitle`；进度写 `durChapterIndex = mappedIndex`、`durChapterPos = mappedPos`、`durChapterTitle = newToc[mappedIndex].title`、`durChapterTime` 保留。
2. `BookContentService.shared.clearCache(for: oldBook.bookUrl)`（:274）—— 旧 bookUrl 的缓存目录 `Caches/ChapterCache/<md5>/` 与新 bookUrl 天然隔离，但仍要清掉省空间。
3. `saveChapters(newToc, for: newBook)`（:468）—— 目录缓存文件 key 是 `chapters_<md5(bookUrl)>.json`，会随新 bookUrl 重建。
4. `saveBookshelf()` → 触发 WebDAV 进度上传（:239-244）。
5. 书签不用动（key 是 name+author）。

`ReaderView` 侧：换源成功后 `currentSource = source`、`book` 需要可变 → 把 `let book: Book`（:48）改为 `@State private var book: Book`，然后 `chapters = newToc; currentChapterIndex = mappedIndex; chapterCache.removeAll(); loadedChapters.removeAll(); scrollSessionId = UUID()`，重跑 `loadInitialChapter(at: mappedIndex, targetCharPos: mappedPos)`。

### 4.5 单章换源

Android **没有** chapter 级 `origin` 字段，做法是把外部源抓到的正文直接写进「当前书当前章」的缓存文件。iOS 照做，最省：

```swift
// ChangeSourceSheet(.singleChapter(index:title:))
// 1. 拉候选书目录 → ChapterMatcher.mapChapter 预选中最相近章
// 2. 用户在目录里手动点章（可改选）
// 3. BookContentService.fetchChapterContent(chapter: 候选章, source: 候选源)
// 4. BookContentService.saveCachedChapterContent(bookUrl: 当前书.bookUrl,
//                                                chapterIndex: 当前章index, content: 结果)
// 5. ReaderView: chapterCache[index] = nil; 重新 getOrFetchChapter(at: index)
```

注意第 4 步写的是**当前书的 bookUrl**，所以 `fetchChapterContent` 的缓存命中分支（`BookContentService.swift:179-181`）下次会直接返回它。UI 上要给用户一个「恢复默认」入口 = 删掉该章缓存文件重新抓。

### 4.6 自动换源

开关 `prefs.autoChangeSource`（默认关，对齐 Android）。两个触发点：

- **目录失败**：`loadTOCAndStart()` 的 catch（`ReaderView.swift:1183-1186`，现在只设 `errorMessage`）。
- **正文失败**：`getOrFetchChapter(at:)`（:1190-1206）返回 nil 时。

逻辑：`preciseCandidates`（书名+作者都完全相等）→ 逐个试 `fetchBookDetail` + 当前章 `fetchChapterContent` → 第一个全成功的执行整书换源，并在顶部显示一条可自动消失的横幅「已自动换源到 XXX」。全程不弹 modal，不打断阅读。失败则维持现有 errorMessage 行为。

### 4.7 UI

`ChangeSourceSheet`：
- 顶部：当前源名（点击滚到该行）+ `TextField` 筛选 + 停止/开始搜索按钮 + 「校验作者」「加载目录」两个 Toggle。
- 列表行：源名、作者校验标记、字数（若加载）、目录数（若加载）；点击 = 换源（带 `ProgressView` 等待）；长按 Menu：编辑源 / 禁用源 / 删除源。
- 底部：滚动到顶 / 滚动到底。
- 两种模式共用一个 View，`.singleChapter` 多一个目录选择步骤。

---

## P0-5 替换净化

### 5.1 模型（`replaceRule.json` 兼容）

```swift
// Sources/LegadoCore/Models/ReplaceRule.swift
public struct ReplaceRule: Codable, Identifiable, Equatable {
    public var id: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
    public var name: String = ""
    public var group: String? = nil
    public var pattern: String = ""
    public var replacement: String = ""
    public var scope: String? = nil
    public var scopeTitle: Bool = false
    public var scopeContent: Bool = true
    public var excludeScope: String? = nil
    public var isEnabled: Bool = true
    public var isRegex: Bool = true
    public var timeoutMillisecond: Int64 = 3000
    public var order: Int = 0        // ⚠️ JSON 键必须是 "order"，Android DB 列叫 sortOrder 但 GSON 用属性名
}
```

**坑**：Android 的 DB 列名是 `sortOrder`，但备份 JSON 里的键是 `order`。iOS 直接用 `order` 即可天然兼容。`timeoutMillisecond <= 0` 时按 3000 处理。

### 5.2 scope 匹配语义

Android 是在 SQL 里做**子串 LIKE**（`ReplaceRuleDao.kt:56-72`），不是分号列表：

```
命中条件 = isEnabled && scopeContent
  && (scope 为空/nil || scope.contains(bookName) || scope.contains(bookOrigin))
  && (excludeScope 为 nil || (!excludeScope.contains(bookName) && !excludeScope.contains(bookOrigin)))
按 order 升序
```

`scope` 为空串 `""` 在 SQL LIKE 里不命中任何非空串 → 等效全局；`excludeScope` 为空串同理等效不排除。Swift 实现要严格照这个真值表写单测。

### 5.3 `ContentProcessor`

```swift
// Sources/LegadoCore/Service/ContentProcessor.swift
public struct ProcessedContent {
    public let title: String
    public let lines: [String]           // 已加首行缩进
    public let effectiveRules: [ReplaceRule]
    public let sameTitleRemoved: Bool
}

public final class ContentProcessor {
    public static let shared = ContentProcessor()

    public static func matchingRules(bookName: String, bookOrigin: String,
                                     all: [ReplaceRule], forTitle: Bool) -> [ReplaceRule]

    public func process(rawContent: String, chapterTitle: String,
                        book: Book, prefs: ReaderPrefs, style: ReadStyleConfig,
                        rules: [ReplaceRule],
                        useReplace: Bool = true, chineseConvert: Bool = true,
                        keepImages: ImageStyle = .default) -> ProcessedContent
}
```

`process` 步骤顺序（对齐 Android `ContentProcessor.getContent`）：

1. **去除与标题重复的开头**：正则 `^(\s|\p{P})*<escapedTitle>(\s)*`（标题里的空白换成 `\s*`，书名用 `NSRegularExpression.escapedPattern`），命中则截掉。可被「移除重复标题」开关关掉。
2. **图片样式**：`.textOnly` → 删除所有 `[image:...]` 标记；`.single` → 每页只留第一张；`.default`/`.full` → 保留。（`[image:]` 标记由 `BookContentService.cleanHtml` :331 产生。）
3. **简繁转换**：`ChineseConverter.convert(text, mode: prefs.chineseConverterType)`。
4. **逐行 trim** 后按 `order` 升序逐条应用规则：
   - `isRegex` → `NSRegularExpression`；`replacement` 以 `@js:` 开头时对每个匹配调 `JSEngine.eval`，绑定 `result` = 匹配串，返回值作替换文本。
   - 非 regex → `String.replacingOccurrences`。
   - 只有真正改变了文本的规则计入 `effectiveRules`。
   - **超时**：把替换包进 `Task` + `withTimeout(rule.timeoutMillisecond)`；超时 → 该规则 `isEnabled = false` 并回写 BookStore + 记 log，**丢弃本条规则的结果继续下一条**。
5. **标题替换**：对 `chapterTitle` 单独跑 `scopeTitle == true` 的规则集，然后 `title + "\n" + body`（`includeTitle` 语义）。
6. **`\u00A0` → 普通空格**：Android 只在 SDK 26–27 做，iOS **无条件做**。
7. **首行缩进 + 拆行**：按 `\n` 拆，每行 trim 掉 `code <= 0x20` 和全角空格 `　`，空行丢弃；第一行（标题）不缩进，其余前缀 `style.paragraphIndent`。

### 5.4 插入点（关键设计决策）

**缓存里存"未净化的原文"，净化在每次读取时做。**

理由：Android 缓存的是净化后文本，导致「改了规则/关了净化」必须清缓存才生效。iOS 把净化放在缓存之后，规则变更即时生效，且不需要缓存失效逻辑。

`BookContentService.fetchChapterContent`（:151-246）改造：

```
L153-176  本地文件短路   → 读出 raw 后同样走 processor
L179-181  缓存命中        → 不再直接 return，改为 raw = cached，跳到净化
L205-220  网络抓取        → raw = getString(contentRule.content) + nextContentUrl 循环(P0-8)
L223-236  replaceRegex    → 保留（书源级规则，语义修正为多段 ##pattern##replacement## 循环）
L239      cleanHtml       → raw = cleanHtml(...)
L241-243  写缓存          → 写的是 cleanHtml 后的 raw（未净化）★
L245      return          → return ContentProcessor.shared.process(rawContent: raw, ...)
```

函数签名需要加参数：

```swift
public func fetchChapterContent(chapter: BookChapter, source: BookSource? = nil,
                                book: Book? = nil,          // 净化需要 bookName/origin
                                nextChapterUrl: String? = nil)  // P0-8 续页终止条件
    async throws -> String
```

`book == nil` 时跳过净化（保持向后兼容，`preDownloadChapters` :287 等调用点可先不传）。ReaderView 的 5 个调用点（:1197、:1214、:1226、:1254、:1355）全部补上 `book:` 与 `nextChapterUrl:`。

**同时删掉 `ReaderView.parseContentBlocks`（:1415/:1430/:1439-1440）里硬编码的 `"　　"`**，否则缩进会叠加两次。

### 5.5 存储与 UI

- `BookStore`：`@Published var replaceRules: [ReplaceRule]`、key `legado_replace_rules_v1`、`saveReplaceRules()`、CRUD + `move(from:to:)` 重排 + `setRuleEnabled(_:id:)`（超时自动禁用要用）。
- `Book.useReplaceRule: Bool?`（新增字段，nil = 用全局 `prefs.replaceEnableDefault`）。
- `ReplaceRuleListView`：List + 每行启用 Toggle / 名称+分组 / 编辑 / 删除，`.onMove` 重排，toolbar「+」新建、「导入」（粘贴 JSON 数组，Android 兼容）、「导出」（`ShareLink` JSON）。挂到 `SettingsView` 新 Section。
- `ReplaceRuleEditSheet`：规则名称、分组、替换内容(pattern)、替换为(replacement)、正则替换 Toggle、作用于标题 Toggle、作用于正文 Toggle、替换范围(scope)、排除范围(excludeScope)、超时时间。
- 阅读器：溢出菜单「替换净化」Toggle + 「起效的替换」→ `EffectiveReplacesSheet` 列出本章命中的规则名，点击进编辑。

### 5.6 简繁转换（已实测，无需外部词典）

`Sources/LegadoCore/Utils/ChineseConverter.swift` 全文只用系统能力，**不打包 OpenCC 词典、不引任何依赖**：

```swift
public enum ChineseConverter {
    /// mode: 0=关闭 1=繁→简 2=简→繁  （Android AppConfig.chineseConverterType 同义）
    public static func convert(_ text: String, mode: Int) -> String {
        guard mode != 0 else { return text }
        // 实测确认的方向映射，勿改动：
        //   "Simplified-Traditional" + reverse:false == 简→繁
        //   "Simplified-Traditional" + reverse:true  == 繁→简
        let toSimple = (mode == 1)
        return text.applyingTransform(StringTransform("Simplified-Traditional"),
                                      reverse: toSimple) ?? text
    }
}
```

三个必须写进代码注释的实测结论：

1. `StringTransform` **没有** `.simplifiedTraditional` 静态成员（Swift 5.7），只能用字符串名。
2. `String.applyingTransform(_:reverse:)` 返回 `String?`，`nil` 时**必须原样返回输入**，不能吞掉正文。
3. 抽查与 Android OpenCC + `fixT2sDict()` 排除表的结果**一致**：
   - 输入 `開源閱讀軟件列印函式雪梨硬碟介面`
   - 输出 `开源阅读软件列印函式雪梨硬碟介面`
   - `開→开`、`讀→读`、`軟→软` 正常转换；`列印`/`函式`/`硬碟`/`介面` **保持不转** —— 正是 Android 排除词条（含「列印」「函式/函数」「硬碟/光碟」「介面」）期望的结果。
   - 这是抽样验证不是全量对齐，剩余差异见 §10 第 2 条。

作用于两处（对齐 Android）：正文（`ContentProcessor` 第 3 步）与章节标题（`ContentProcessor` 第 5 步的 `scopeTitle` 之前）。

---

## P0-6 朗读控制面板

### 6.1 `AudioBookService` 重构

现状（`AudioBookService.swift`）：`speak(text:)`（:31-50）把**整章塞进一个 `AVSpeechUtterance`**，因此无法做「上一句/下一句」、无法高亮、无法定位。`speechRate`（:11）已存在但无 UI。

改为**段（paragraph）队列**，对齐 Android「朗读单元 = 段，不是句」：

```swift
public final class AudioBookService: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    public static let shared = AudioBookService()

    @Published public private(set) var paragraphs: [String] = []
    @Published public private(set) var currentIndex: Int = 0
    @Published public private(set) var isPlaying = false
    @Published public private(set) var isPaused = false
    @Published public var currentCharPos: Int = 0        // 章内偏移，供高亮/书签/进度
    @Published public var speechRatePref: Int = 5        // 0...45，落盘到 ReaderPrefs.ttsSpeechRate
    @Published public var timerMinutes: Int = 0          // 0...180
    @Published public private(set) var timerRemaining: Int = 0

    public var onRequestChapterChange: ((Int) -> Void)?  // ±1，由 ReaderView 注入

    public func load(chapterText: String, startCharPos: Int = 0)
    public func play() / pause() / resume() / stop()
    public func nextParagraph() / prevParagraph()
    public func speakParagraph(at index: Int)
}
```

要点：

- `load` 切分：`chapterText.split("\n")` → 过滤空行 → 跳过纯标点段（正则 `^[\s\p{C}\p{P}\p{Z}\p{S}]+$`，对齐 Android `AppPattern.notReadAloudRegex`）。`startCharPos` 用来定位起始段（逐段累加 `length + 1` 直到超过 pos）。
- `currentCharPos` 计算：`paragraphs[0..<currentIndex].reduce(0) { $0 + $1.count + 1 }`。这个值直接喂给 `BookStore.updateProgress` 与书签，量纲与 Android `durChapterPos` 一致。
- 推进：`delegate didFinish` → `currentIndex += 1`（跳过纯标点段）→ 播下一段；到末尾 → `onRequestChapterChange?(+1)`，ReaderView 换章后调 `load(chapterText:)` 继续。`prevParagraph` 同理，跨章传 `-1`（新章从最后一段开始）。
- 语速换算（对齐 Android）：`utterance.rate = clamp((Float(speechRatePref) + 5) / 10, min: AVSpeechUtteranceMinimumSpeechRate, max: AVSpeechUtteranceMaximumSpeechRate)`，默认 pref=5 → 1.0x。`ttsFollowSys` 开启时用 `AVSpeechUtteranceDefaultSpeechRate` 且禁用滑块。
- 额外提供 `pitch`（0.5–2.0）与 `volume` —— Android 无对应，属 iOS 增益，不影响兼容。
- 定时：`Timer.scheduledTimer(60s)`，**仅 `isPlaying && !isPaused` 时递减** `timerRemaining`，到 0 → `stop()`。快捷档 `[0,5,10,15,30,60,90,180]`。`timerMinutes` 落盘（Android `ttsTimer` 同名语义）。
- 高亮：`ReaderView` 观察 `currentCharPos`，滚动模式给对应 block 加 `.background(高亮色)`；翻页模式在 P0 只做「当前段离开本页时自动翻页」，段级着色需要给 `CoreTextUIView`（:1963-2012）加 attribute range 支持 → **P0 降级，记入 §10**。

### 6.2 后台播放与锁屏控制（必须改 Xcode 工程）

1. `Legado.xcodeproj` → Target → Signing & Capabilities → **Background Modes → Audio, AirPlay, and Picture in Picture**。等价于 Info.plist 加：
   ```xml
   <key>UIBackgroundModes</key><array><string>audio</string></array>
   ```
   当前全工程 grep 无 `UIBackgroundModes`，不加则退后台立即静音。
2. `AVAudioSession` 已配好（:20-29，`.playback / .spokenAudio / .duckOthers`），保留。
3. 新增 `MPRemoteCommandCenter` 注册（`play` / `pause` / `togglePlayPause` / `nextTrack`→下一段 / `previousTrack`→上一段 / `changePlaybackPosition`），以及 `MPNowPlayingInfoCenter` 写 `title = 书名`、`artist = 章节名`、`playbackRate`。
   - 这一步**顺带把「耳机按键控制朗读」做掉了**（Android 的 `MediaButtonReceiver` 等价物），无需单独实现。
   - 注意 `stop()`（:82-88）里有「paused 时先 resume 防 mediaserverd 死锁」的既有 workaround，重构时保留。

### 6.3 UI（`ReadAloudPanel`）

沿用 `readingSettingsCard`（:1010-1033）的 ZStack overlay + `.transition(.move(edge:.bottom))` 范式：

```
┌ 上一章 │ 上一段 │ ⏯播放/暂停 │ ⏹停止 │ 下一段 │ 下一章 ┐
│ 定时  ────●────  12 分钟      [0/5/10/15/30/60/90/180] │
│ 语速  ────●────  1.2x     [−] [+]   □ 跟随系统          │
│ 目录 │ 主菜单 │ 后台 │ 设置                              │
└─────────────────────────────────────────────────────────┘
```

- 「主菜单」= 关本面板 + `showControls = true`。
- 「后台」= `dismiss()` 但**不停朗读**（`onDisappear` 里的 `audioService.stop()`（:224/:226）必须改成「仅当用户主动退出且未开启后台朗读」才 stop；加一个 `keepPlayingInBackground` 标志）。
- 「设置」= 跳 `MoreSettingsPanel` 的朗读分区（忽略音频焦点 / 来电暂停 / 按页朗读 / 流式播放 —— P0 只做「按页朗读」，其余 P1）。
- 入口：底栏「朗读」按钮点击 = 播放/暂停，**长按 = 展开本面板**（对齐 Android）。SwiftUI 用 `.simultaneousGesture(TapGesture().onEnded{...})` + `.onLongPressGesture{...}` 组合，或 `Menu` 包装。

---

## P0-7 搜索范围 + 搜索历史

### 7.1 搜索历史模型（`searchHistory.json` 兼容）

```swift
// Sources/LegadoCore/Models/SearchKeyword.swift
public struct SearchKeyword: Codable, Identifiable, Equatable {
    public var word: String          // 主键
    public var usage: Int = 1
    public var lastUseTime: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
    public var id: String { word }
}
```

`BookStore` 加 `@Published var searchHistory: [SearchKeyword]` + key `legado_search_history_v1` +：

```swift
func recordSearchKeyword(_ word: String)   // 存在→usage+=1,lastUseTime=now；否则插入
func deleteSearchKeyword(_ word: String)
func clearSearchHistory()
var historyByTime: [SearchKeyword]         // lastUseTime DESC（输入框为空时）
func history(matching key: String) -> [SearchKeyword]   // contains, usage DESC（有输入时）
```

写入点：`SearchViewModel.startSearch()`（:47-48 取到 key 之后立刻调）。

### 7.2 `SearchScope`（对齐 Android 序列化格式）

Android 用一个 `String` 表达三态，iOS 照抄以便 `searchScope`/`searchGroup` 两个 pref 互通：

```swift
public struct SearchScope: Equatable {
    public let raw: String                 // "" = 全部；"A,B" = 分组；"名称::URL" = 单源
    public var isAll: Bool { raw.isEmpty }
    public var isSource: Bool { raw.contains("::") }
    public var groups: [String] { isAll || isSource ? [] : raw.split(",").map(String.init) }
    public var sourceUrl: String? { isSource ? String(raw.split("::").last!) : nil }

    /// 剔除已无启用源的分组，并回写（Android getBookSourceParts 行为）
    public func resolved(sources: [BookSource]) -> (scope: SearchScope, list: [BookSource])
}
```

需要 `BookSource` 支持多分组：加计算属性

```swift
public var groups: [String] {
    (bookSourceGroup ?? "").split(whereSeparator: { ",、;；".contains($0) })
                            .map { $0.trimmingCharacters(in: .whitespaces) }
                            .filter { !$0.isEmpty }
}
```

`SearchViewModel`：把 `@Published var selectedSourceUrl: String?`（:15）**替换**为 `@Published var scope: SearchScope`，`targetSources`（:27）改为 `scope.resolved(sources: availableSources).list`。持久化写 `ReaderPrefs.searchScope` / `.searchGroup`（`searchGroup` 仅在「单个分组」时非空，照 Android `SearchScope.save()`）。

`availableSources`（:23）过滤条件保持 `enabled != false && searchUrl != nil`。

### 7.3 精准搜索与三桶排序

`SearchBook`（`Book.swift:155-192`）加 `origins: [String]`（默认 `[origin]`，`Codable` 容错解码），用于跨源合并计数。

`SearchViewModel.appendDeduplicated`（:141）现在只按 `seenBookIds` 去重。改为：

1. 合并键 = `(name, author)`；命中则 `existing.origins.append(new.origin)`（去重）并补全空字段（封面/简介/最新章）。
2. 每次 yield 后重排三桶（对齐 Android `SearchModel.mergeItems`）：
   - `equal`：`name == key || author == key` → 按 `origins.count` 降序
   - `contains`：`name.contains(key) || author.contains(key)` → 按 `origins.count` 降序
   - `other`：其余 → 保持到达顺序，**仅 `!precisionSearch` 时保留**
   - 最终 = equal + contains + (other)
3. `precisionSearch` 开关（`ReaderPrefs.precisionSearch`）切换后需用当前 key 重搜。

### 7.4 停止 / 继续

`cancelAndReset()`（:35）已存在但没有 UI 入口。加：

- 搜索中 → 右下 FAB / toolbar 显示「停止」，点击置 `isManualStop = true` 并 cancel。
- 已停止且 `hasMore` → 显示「继续」，调 `loadNextPage()`（:96）。
- 空结果且范围非全部 → alert「XX 搜索结果为空，是否切换到全部书源？」；若开着精准搜索则先问「是否关闭精准搜索？」（对齐 Android `searchFinishLiveData`）。

### 7.5 UI

`SearchBookView.swift`：

- **空态区（:99-109）**改为：`搜索历史` 标题 + 右侧「清除」（confirm alert）+ `FilterChip`（组件在 :208-225，直接复用）流式布局；chip 点击 = 填入并提交（若书架已有同名书则只填入不提交，对齐 Android）；chip **长按 = 删除单条**。有输入时展示 `history(matching:)` 过滤结果。
- **源过滤 chips 行（:43-71）**改为单个「范围」按钮，显示当前 scope 摘要（`全部书源` / `2 个分组` / 源名），点击弹 `SearchScopeSheet`：
  - 顶部 segmented「分组 / 书源」
  - 分组模式：已启用分组的复选列表
  - 书源模式：单选列表 + 顶部 `.searchable` 过滤
  - 底部「全部书源」/「取消」/「确定」
  - 保留原来的单源快捷 chips 作为「常用源」补充（可选）
- toolbar 加 Menu：「精准搜索」Toggle、「书源管理」入口、「日志」（P1）。

---

## P0-8 字符集自动识别 + `nextContentUrl` / `nextTocUrl`

### 8.1 `CharsetDetector`

现状：`NetworkClient.swift:133` 与 `:163` 两处都是

```swift
let bodyStr = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
```

`String(decoding:as:)` 的 fallback 会把非法字节替换成 U+FFFD —— **原始 GBK 数据在 `bodyString` 里已损坏**，但 `NetworkResponse.data`（:3-15）保留了原始字节，`headers` 也保留了（:126-131），所以可以在同一层补救。

新建 `Sources/LegadoCore/Utils/CharsetDetector.swift`：

```swift
public enum CharsetDetector {
    /// declared: URL 选项里的 charset（Android 语义是"请求编码"，iOS 兼作响应解码提示）
    public static func decode(_ data: Data, headers: [String: String],
                              declared: String? = nil) -> String
    public static func encoding(named name: String) -> String.Encoding?
}
```

解析链（对齐 Android `OkHttpUtils.ResponseBody.text()` + `EncodingDetect.getHtmlEncode`）：

1. **剥 UTF-8 BOM**（`EF BB BF`）。
2. `declared` 非空 → 直接用它解（解不出再往下）。
3. **HTTP 头**：大小写不敏感找 `Content-Type`，正则 `charset=([\w\-]+)`。
4. **HTML meta 嗅探**：取前 4KB 按 `.ascii` 粗解，正则找 `<head>[\s\S]*?</head>`（找不到就全文前 4KB），再匹配
   - `<meta[^>]+charset=["']?([\w\-]+)`
   - `<meta[^>]+http-equiv=["']?content-type["']?[^>]+content=["']?[^"']*charset=([\w\-]+)`
5. **统计检测**：`NSString.stringEncoding(for:encodingOptions:convertedString:usedLossyConversion:)`。
6. **候选严格解码打分兜底**：依次试 `[.utf8, gb18030, big5, shiftJIS, eucKR, isoLatin1]`，判据是 **`String(data:encoding:) != nil`（严格解码是否成功）** + CJK 字符占比。
7. 全失败 → `.utf8` 强解（保持现状行为，不退化）。

#### 实测校正（Swift 5.7.2 编译运行，务必按此实现，别照直觉写）

| # | 实测事实 | 对方案的影响 |
|---|---|---|
| A | `NSString.stringEncoding(for:)` 返回 **`UInt`**，不是 `String.Encoding` | 必须 `String.Encoding(rawValue: detected)` 包一层 |
| B | `usedLossyConversion` 出参在 GBK / UTF-8 / Big5 三种样本上**恒为 `true`** | ⚠️ **原计划「`lossy == false` 才采纳」是错的，会拒掉所有检测结果**。该出参不可作为判据，删除这条 |
| C | GBK 样本 detected = **2147485234**，与 `CFStringEncodings.GB_18030_2000` 换算值**完全相等**；UTF-8 样本 detected = **4** = `.utf8` | 统计检测对 **UTF-8 / GB 系可靠**，可作第 5 步主力 |
| D | Big5 样本 detected = **2147484707**，≠ `CFStringEncodings.big5` 的 **2147486211** | ⚠️ **统计检不出 Big5**。繁中站必须依赖第 3/4 步的 `charset=` 声明；两者都缺时走第 6 步打分，且要把 big5 排在 shiftJIS/eucKR 之前 |
| E | GBK 字节用 `.utf8` 解 → **返回 `nil`**（不是乱码字符串） | 好消息：第 6 步打分可用「严格解码是否成功」这个干净信号，不需要额外的 U+FFFD 计数。现有代码的 `?? String(decoding:as:UTF8.self)` 才是产生乱码的元凶 |
| F | `StringTransform` **没有** `.simplifiedTraditional` 静态成员 | 只能写 `StringTransform("Simplified-Traditional")` / `StringTransform("Traditional-Simplified")` 字符串名 |
| G | `String.applyingTransform(_:reverse:) -> String?` **存在且可用**（`NSMutableString` 上的同名 mutating 版被它覆盖） | 简繁转换不需要自己维护字典文件，一行搞定 |
| H | 方向语义实测确认：`("Simplified-Traditional", reverse:false)` = **简→繁**；`("Simplified-Traditional", reverse:true)` = **繁→简**；`("Traditional-Simplified", reverse:false)` 亦为繁→简 | 采用**同一对** `StringTransform("Simplified-Traditional")` 的 `reverse` true/false 表达两个模式，与 Android `chineseConverterType` 1=繁→简 / 2=简→繁 对齐 |

编码名映射表（`encoding(named:)`，先归一化：`lowercased()` + 去 `-`/`_`/空格）：

| 归一化后的输入 | `String.Encoding` |
|---|---|
| `utf8` | `.utf8` |
| `gbk` / `xgbk` / `gb2312` / `gb18030` | `CFStringEncodings.GB_18030_2000`（实测值 2147485234，一个值通吃三种叫法） |
| `big5` / `big5hkscs` | `CFStringEncodings.big5` / `.big5_HKSCS_1999` |
| `shiftjis` / `sjis` | `.shiftJIS` |
| `euckr` / `ksc56011987` / `iso2022kr` | `CFStringEncodings.EUC_KR` |
| `eucjp` / `ujis` | `CFStringEncodings.EUC_JP` |
| `iso88591` / `latin1` / `windows1252` | `.isoLatin1` / `.windowsCP1252` |
| 未知 | 返回 nil，交给第 6 步 |

> 注意 `x-gbk` 归一化后是 `xgbk`，Android/网页里很常见，**必须显式列进映射表**，否则会掉到打分兜底且 Big5 场景会误判。


### 8.2 接线

- `NetworkClient.ParsedRequest`（:25-30）加 `charset: String?`、`retry: Int`。
- `parseLegadoUrl`（:34，JSON 选项解析在 :68-95）增加读取 `charset` / `retry` 两个键（现在只认 `method`/`headers`/`body`，其余静默丢弃）。
- `request(parsed:)` 的 :133 与 `requestSync` 的 :163 换成 `CharsetDetector.decode(data, headers: respHeaders, declared: parsed.charset)`。
- `retry`：`for attempt in 0...parsed.retry { … }`，仅对抛错/5xx 重试，间隔 300ms。**上限硬编码 3** 防书源写飞。
- 顺手修 `BookContentService.swift:167` 本地 txt 读取的硬编码 `.utf8` → 走 detector；`BookStore.importTxt`（:519）已有的 GB_18030 fallback 统一收敛到 detector，避免两套逻辑。

### 8.3 `nextContentUrl` 循环

`BookContentService.fetchChapterContent`（:205-220）现在是**单次请求**。改为：

```swift
var visited: Set<String> = []
var fragments: [String] = []
var pageUrl = chapter.url
var pageBase = source.bookSourceUrl

while !pageUrl.isEmpty {
    let abs = RuleAnalyzer.resolveAbsolute(pageBase, pageUrl)
    if visited.contains(abs) { break }
    visited.insert(abs)

    let parsed = NetworkClient.parseLegadoUrl(pageUrl, defaultHeader: header, baseUrl: pageBase)!
    let resp = try await NetworkClient.shared.request(parsed: parsed)
    let analyzer = RuleAnalyzer(content: resp.bodyString, baseUrl: abs, bookSource: source, jsEngine: js)
    fragments.append(analyzer.getString(contentRule.content))

    // 下一页
    let nexts = analyzer.getStringList(contentRule.nextContentUrl, isUrl: true)
    guard let first = nexts.first, !first.isEmpty else { break }
    if nexts.count > 1 {
        // Android 语义：多 URL 时并发抓取，且并发分支内不再递归取下一页
        let rest = await withTaskGroup { … 抓 nexts[1...] 的 content，按序 append … }
        fragments.append(contentsOf: rest)
        break
    }
    let firstAbs = RuleAnalyzer.resolveAbsolute(abs, first)
    // 终止条件：下一页 == 下一章 URL
    if let nextChapterUrl, RuleAnalyzer.resolveAbsolute(abs, nextChapterUrl) == firstAbs { break }
    pageUrl = first; pageBase = abs
    if visited.count >= 50 { break }        // ★ iOS 额外硬上限，Android 没有
}
let raw = fragments.joined(separator: "\n")
```

- `nextChapterUrl` 由调用方传入（ReaderView 知道 `chapters[index+1].url`）。Android 在未传时回退查 DB 的 index+1 章，iOS 同样在 `fetchChapterContent` 内部可从 `BookStore.getChapters` 兜底取。
- **硬上限 50 页**是 iOS 新增的保险（Android 只靠 visited 去重 + 下一章比对），必须在 §10 记为有意偏离。

### 8.4 `nextTocUrl` 循环

`fetchBookDetail`（:9-142，目录解析在 :30-64）同构改造：

```swift
while … { 抓一页 → 解析 chapterList/chapterName/chapterUrl → 累加 chapters
          → nexts = getStringList(tocRule.nextTocUrl, isUrl: true)
          → 单个则续循环，多个则并发且不再递归 → visited 去重 → 上限 200 页 }
```

收完后处理（对齐 Android `BookChapterList.kt:59-134`）：

1. `tocRule.chapterList` 前缀 `-` → 整体 `reverse()`（`+` 忽略）。
2. 按 `url` 去重（保序，等价 Android 的 `LinkedHashSet`）。
3. 重排 `index` 为 `0..<count`。
4. `chapterUrl` 为空的章：卷用 `title + index` 顶替，普通章用 baseUrl 顶替（Android 行为）。
5. `formatJs` / `preUpdateJs` / `isVolume` / `isVip` **P0 不做**（P1），但去重与重排必须做，否则续页会产生重复章节。

### 8.5 顺带修的 `replaceRegex` 语义

`BookContentService.swift:223-236` 现在把 `replaceRegex` 按 `##` 切成 pattern/replacement **只做一次替换**。Android 语义是 `##regex##replacement##` 可多段串联。改为 `split("##")` 后按 `[pattern, replacement]` 成对循环应用。这是书源级规则，与 P0-5 的用户级 `ReplaceRule` 是两套，都要跑（书源级在前）。

---

## 9. 验证方案

### 9.1 单元测试（`Tests/LegadoCoreTests/LegadoCoreTests.swift`，现有 848 行，已有 MockURLProtocol 可复用）

| 模块 | 用例 |
|---|---|
| `ReadStyleConfig` | Codable round-trip；**用 Android 导出的真实 `readConfig.json` 片段解码**，断言 `bgStr/textSize/paragraphIndent/tipFooterRight` 等键名对得上；encode 后不含 `index` 键 |
| `ReaderPrefs` | round-trip；旧 `reader_page_mode` 迁移路径 |
| `Bookmark` | Codable 键名断言（`time/bookName/bookAuthor/chapterIndex/chapterPos/chapterName/bookText/content`）；按 name+author 检索；换 bookUrl 后仍可检索 |
| `ReplaceRule` | JSON 键必须是 `order` 而非 `sortOrder`；scope/excludeScope 真值表全组合（nil / "" / 命中书名 / 命中 origin / 排除命中）；`timeoutMillisecond <= 0 → 3000` |
| `ContentProcessor` | 去重标题（含标点/空白前缀）；简繁三档；正则规则 + 非正则规则；`@js:` replacement；effectiveRules 只含真正改变文本的；`\u00A0` 替换；首行缩进档位；图片样式四档；超时规则被自动禁用且不污染输出 |
| `CharsetDetector` | UTF-8 BOM 剥离；`Content-Type: text/html; charset=gbk` 头；`<meta charset="gb18030">` 嗅探；`<meta http-equiv>` 嗅探；**用真实 GBK 字节 fixture** 断言解出正确中文；**断言「GBK 字节用 `.utf8` 严格解返回 nil」这一判据成立**（实测校正 E）；`x-gbk`/`gb2312`/`big5-hkscs`/`ks_c_5601-1987` 归一化命中；无声明时 Big5 fixture 走打分路径仍能解出 |
| `ChineseConverter` | **方向锁定测试**：`mode:1` 繁入出简、`mode:2` 简入出繁（防 §5.6 映射写反）；`mode:0` 原样返回；列印/函式/硬碟/介面 保持不转；超长文本性能（每章调一次，需 < 5ms） |
| `nextContentUrl` | MockURLProtocol 造 3 页链，断言拼接顺序与 `visited` 去重；造环（A→B→A）断言不死循环；造 nextUrl == 下一章 URL 断言提前终止；多 URL 并发分支 |
| `nextTocUrl` | 造 2 页目录，断言合并 + 按 url 去重 + index 重排；`chapterList` 前缀 `-` 断言 reverse |
| `ChapterMatcher` | 等长/缩短/增长目录；标题带卷号；纯数字；中文数字（`第一百二十三章`）；相似度 < 0.96 且章号可匹配；完全不匹配 → 钳位回退；`oldIndex == 0`；空新目录 |
| `SearchScope` | 三态解析；`resolved` 剔除空分组并回写；单源 `名称::URL` 切分 |
| `SearchKeyword` | 重复记录 → usage+1 且 lastUseTime 更新；`historyByTime` 与 `history(matching:)` 两种排序 |
| 三桶排序 | equal/contains/other 分桶 + `origins.count` 降序 + 精准模式下 other 被丢弃 |

### 9.2 手工验证（必须真机）

| 项 | 为什么必须真机 |
|---|---|
| 音量键翻页 | 模拟器无音量键 |
| 后台朗读 + 锁屏控制 | 需 `UIBackgroundModes` 生效 + 锁屏界面 |
| 亮度调节 | 模拟器 `UIScreen.brightness` 无效 |
| 屏幕常亮 | 模拟器不熄屏 |

真机走查清单：
1. 调字号/行距/主题 → 杀进程重启 → 配置仍在（P0-2 回归）。
2. 打开一本 GBK 站的书 → 正文不乱码（P0-8）。
3. 打开一本分页正文的书源 → 章节内容完整不截断（`nextContentUrl`）。
4. 打开一本分页目录的书源 → 目录章数与网页一致（`nextTocUrl`）。
5. 加一条替换规则（如去广告尾巴）→ 立即生效，无需清缓存；关掉「替换净化」→ 立即恢复原文。
6. 加书签 → 跳到别的章 → 从书签跳回 → 落在同一段。
7. 整书换源 → 章节位置不跳错（重点验证长目录书）；单章换源 → 只有该章内容变化，目录不变。
8. 断网状态打开一本已缓存的书 → 自动换源不误触发（`autoChangeSource` 默认关）。
9. 朗读 → 锁屏 → 通知栏/锁屏能暂停、上一段、下一段；定时 5 分钟到点自动停。
10. 搜索历史：搜 3 个词 → 退出重进 → 历史按时间倒序；点历史词直接搜；长按删单条；清除全部有确认。
11. 搜索范围切到单个分组 → 结果只来自该组；切「全部书源」→ 恢复。
12. 点击区域把 MC 改成「下一页」→ 保存 → 系统强制把 MC 改回「菜单」（防锁死）。
13. WebDAV 备份 → 在 Android legado 里恢复 → 书签 / 替换规则 / 搜索历史 三项都能读出来（**键名兼容性的终极验证**）。

### 9.3 回归风险点

- `ReaderView.swift` 改动面最大（菜单骨架 + 点击区域 + 缩进/边距 + 面板）。**必须回归**：滚动↔翻页模式互转保持位置（`handlePageModeChange` :848-902）、下拉加载上一章（:345-358）、跨章无缝滚动（:314-321）、`durChapterPos` 恢复（:1264-1296）。
- `BookContentService.fetchChapterContent` 签名变更影响 5 个 ReaderView 调用点 + `preDownloadChapters`（:287）。给 `book`/`nextChapterUrl` 设默认值 `nil` 以保持编译兼容，再逐个补。
- 净化插入到缓存之后 → 首次读取会比现在慢（多一次正则遍历）。规则数 > 50 时考虑给 `NSRegularExpression` 做缓存（`[pattern: NSRegularExpression]` 字典）。
- `Book` 新增字段必须用 `decodeIfPresent` + 默认值，否则老 `legado_bookshelf_v1` 数据解码失败会**清空书架**（现有 `init(from:)` 是全字段 `try?` 容错，照抄这个风格）。

### 9.4 每个子项完成后的构建门禁（双平台都要过）

```bash
cd ios
swift build                    # macOS 目标（当前基线：Build complete in 3.37s）
swift test                     # 单测
xcodebuild -project Legado.xcodeproj -scheme Legado \
  -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 14' build   # iOS 目标
```

`swift build` 从「通过」变成「失败」= 某个 iOS-only API 忘了加 `#if os(iOS)`。这条必须在每个 P0 子项收尾时跑，不要攒到最后。

---

## 10. 有意偏离 Android 的地方（必须记录，避免日后当 bug 修）

| # | 偏离 | 原因 |
|---|---|---|
| 1 | 仿真翻页（`PageAnim.simulation`）P0 降级为覆盖效果 | 卷曲动画需 `CATransform3D` + shader，成本远超收益；P2 再评估 |
| 2 | 简繁转换用系统 `CFStringTransform`，不打包 OpenCC 词典 | **零依赖，且实测结果优于预期**：抽查词表（列印/函式/硬碟/介面）与 Android `fixT2sDict()` 排除词条的期望输出一致。残余风险：系统 transform 的 phrase 覆盖度不如 OpenCC 全量词典，长文中个别多音/多义字（如「乾/干/幹」「後/后」语境）可能有差异，但**不影响阅读可用性**。若日后要严格对齐，改成打包 OpenCC t2s/s2t + 排除表 JSON 即可，接口 `ChineseConverter.convert(_:mode:)` 不变 |
| 3 | 「重新分段」P0 只做「按空行重排 + 合并碎行」简化版 | Android `ContentHelp.reSegment` 含 `Math.random()` 概率断行，**无法逐字节复现**，且引号配对状态机复杂度高 |
| 4 | 点击区域用干净三等分，不复制 `trRect` 左边界 0.36 的历史怪癖 | Android 那个值是遗留 bug，复制过来只会让右上区判定诡异 |
| 5 | 替换规则超时后：取消任务 + 自动禁用 + 丢弃该规则结果 | Android 会把整章内容替换成「规则名+堆栈」并在 3 秒后**杀进程重启**（因 Java 正则不可中断）。Swift 的 `NSRegularExpression` 可在 Task 里取消，不需要这种自残行为 |
| 6 | `nextContentUrl` 加 50 页硬上限、`nextTocUrl` 加 200 页 | Android 只靠 visited 去重 + 与下一章 URL 比对终止，书源写错时可能长时间空转 |
| 7 | 缓存存「未净化原文」，净化在读取时做 | Android 缓存净化后文本，改规则/关净化必须清缓存。iOS 这样做规则即时生效，代价是每次读取多一遍正则 |
| 8 | 「屏幕超时」非「常亮」档位到时只是交还系统熄屏权 | iOS 无 API 可强制熄屏 |
| 9 | 两端对齐开关在滚动模式下置灰 | SwiftUI `Text` 不支持强制两端对齐；只有 CoreText 路径（翻页模式）能做 |
| 10 | 朗读段级高亮 P0 只在滚动模式实现 | 翻页模式的 `CoreTextUIView`（:1963-2012）需要加 attribute range 渲染支持，P1 做 |
| 11 | `ReadStyleConfig.textSize`(sp) 与 iOS `fontSize`(pt) 用固定系数 0.9 换算 | 两套单位体系，无法精确对齐；只在导入/导出 Android 配置时用到 |
| 12 | `ReaderPrefs` 存单一 UserDefaults key，不拆成 Android 的 `config.xml` 独立键 | iOS 无 SharedPreferences；将来做备份互通时需要一层 XML 映射（P2） |
| 13 | Big5 站点**依赖 `charset=` 声明**，声明缺失时靠候选严格解码打分兜底 | 实测 `NSString.stringEncoding(for:)` 对 Big5 返回错误编码（2147484707 ≠ big5 的 2147486211），而 GBK/UTF-8 精确命中。繁中站多数会在头或 meta 里声明 charset，覆盖大部分场景；不声明的会走打分路径，准确率下降但不引入新依赖 |
| 14 | 不使用 `usedLossyConversion` 出参作为任何判据 | 实测三种样本恒返回 `true`，该参数在 Swift 侧不可靠（见 P0-8 实测校正 B） |
| 15 | macOS 目标下亮度调节、屏幕常亮、音量键、`AVAudioSession` 相关能力**置灰/空实现** | 工程实际维护 macOS 构建（`swift build` 通过，12 个文件已有 `#if os(iOS)`）。P0 不为此另开一套 UI，只在面板里对这些控件做 `#if os(iOS)` + disabled |
| 26 | **亮度调节整体删除**（`BrightnessOverlay`、顶栏亮度按钮、`brightness`/`nightBrightness`/`brightnessAuto`/`brightnessVwPos`/`showBrightnessView` 五个 pref 全部移除） | 用户明确要求：iOS 有系统控制中心，App 内再做一条亮度条是重复功能；实现里的旋转 `Slider` 还带来一个压在滑块下方的空矩形，观感像 bug。代价：与 Android 的 `brightness` 系列 pref 不再互通，`TolerantJSON` 会把老存档里的这些键当未知键忽略（有单测锁这条），因此旧数据仍可解码 |
| 27 | 朗读的播放状态由服务自己持有（`state: stopped/speaking/paused`），`isPlaying`/`isPaused` 只是它的镜像；delegate 回调只「对齐」不「决定」状态 | `AVSpeechSynthesizer.pauseSpeaking` 落在两条 utterance 之间时会被静默丢弃，`didPause` 不来 → 原实现里按钮永远停在「暂停」，再点就走 `play()` 重读同一段，表现为「点暂停没反应」。另外 pause 后 150 ms 复查一次，引擎仍在说话就 `stopSpeaking` 硬停，保证「暂停=静音」 |
| 28 | 语速/音调/跟随系统语速/定时四个 `didSet` 加 `oldValue != newValue` 守卫 | 朗读面板 `onAppear` 会把四个偏好原值回写一遍，无守卫时每次都触发「重读当前段落」，一开面板就从头读，且会把刚按下的暂停顶掉 |
| 29 | 三个底部面板（「界面」/「更多设置」/「朗读」）统一走 `ReaderPanelChrome`：`ReaderPanelCard` 一份卡片定义（沿用最初版「界面」的写法：主题底色 + 阴影 + **四角圆角** + 发丝描边 + 10/6pt 外边距）+ `ReaderPanelRow/SwitchRow/MenuRow/SliderRow/StepperRow/NavRow/Value/Header/Section` 一组行原语；统一占屏幕下 1/2（`ReaderPanelMetrics.heightFraction`）、统一可滚动 | 根因不是某处颜色写错，而是同一个卡片被抄了三遍：「更多设置」原先用 `List`（系统底色 + 系统分区头，羊皮纸/护眼主题下变成深色块），行标签一份写 0.7 透明度一份写满透明度，高度一份自适应一份 0.34/0.75。「朗读」更严重：几行标签根本没写颜色，继承系统 primary，系统深色模式 + 浅色阅读主题时是白字印在米色底上。收成一份定义后「一模一样」是结构保证 |
| 30 | 净化按钮图标 `eraser.pen` → `wand.and.stars`，并补上「点了到底发生什么」的说明 | `eraser.pen` 不是 SF Symbol（连 `eraser` 都要 iOS 16 才有），iOS 15 上渲染为空白 —— 这就是「净化没有图标」的原因。同类无效符号一并修掉：`chevron.up.down`、`doc.badge.arrow.up`、`photo.badge.exclamationmark`。另外「净化」是 Android 内部术语，现在点按会在底栏上方浮出一句说明（含「没有任何规则」这种看起来像死按钮的情况），长按进入「净化与替换规则」面板 |
| 16 | 音量键翻页用隐藏 `MPVolumeView` 拦截，不用 iOS 17 的 `AVAudioApplication.addInputVolumeButtonHandler` | 工程 SDK 是 Xcode 14.2 / iOS 16.2，编译期看不到 iOS 17 API，而最低部署目标锁定 iOS 15 不能抬高。副作用：物理音量键会**同时**触发系统音量 HUD（MPVolumeView 只能接管不能压制 HUD）；长按连翻靠 600 ms 前沿去抖模拟，手感与 Android 不完全一致 |
| 17 | 滚动模式的自定义点击区域只有「中央=菜单」生效，左右/上下 6 区的翻页动作被忽略 | 滚动模式没有「页」的概念，`nextPage/prevPage` 只能落到章节级；Android 在同一模式下也是把点击翻译成章节跳转，P0 先不让用户误以为九宫格全部生效 |
| 18 | 单章换源直接按 `ChapterMatcher` 自动映射目标章节，不弹 Android 的「选择对应章节」列表 | 自动映射（比例估计 → ±10 窗口 → Jaccard 0.96 → 章节号）在单测里已达 14/14，弹列表等于把置信度问题转嫁给用户；映射错时用户仍可用目录浮窗手动跳 |
| 19 | `readConfig.json` 用**单个** `ReadStyleConfig` 对象落盘，不还原 Android 的 `Config(name, value)` 数组 | Android 那个数组是 SharedPreferences 的镜像（一行一个 key），iOS 侧再摊平成数组只会增加一层无收益的编解码 |
| 20 | 「更多设置」面板只保留**真的生效**的开关 | `progressBarBehavior`、`readBarStyleFollowPage`、`noAnimScrollPage`、`previewImageByClick`、`disableReturnKey` 5 项在 iOS 无对应实现，宁可不显示也不给死开关（待 §12 补) |
| 21 | `ReadStyleConfig` / `ReaderPrefs` 解码走 `TolerantJSON` 默认值覆盖，而非合成 `Codable` | 合成 `Codable` 遇到「Android 导出的老配置缺字段」会整块 throw，表现为**设置全部丢失**；`TolerantJSON` 先解码默认对象再用存档里存在的键覆盖，缺键与多键都能存活 |
| 22 | `SearchScope.sourceUrl` 按**第一个** `::` 切分（Android `split("::")` 取尾段） | 源名不会含 `::`，url 却可能在路径里带；取尾段会把 `https://a/x::y` 截成 `y`。有单测锁这条 |
| 23 | `BookSource.groups` 分隔符对齐 Android `AppPattern.splitGroupRegex = [,;，；]`，额外容忍 `\n`，**不再**按 `、` 切 | 实现期比对了 `AppPattern.kt:21`：`、` 从来不是分隔符，按它切会把「默认、故事汇」这种源名误拆成两组；手写书源 JSON 常一行一组，故加 `\n` |
| 24 | 搜索历史 chip 点击 = 填入关键词并立即搜索，不检查「书架是否已有同名书」；空结果时**不弹**「切换到全部书源 / 关闭精准搜索」引导 | 前者需要把书架书名做子串匹配，收益低于一次多余的搜索；后者属于 P1 的搜索交互打磨，P0 只保证范围与精准开关可用 |
| 25 | 章节缓存存**净化前**文本（同 #7，此处补充其对换源的影响） | 换源后 `BookStore.changeSource` 会清掉旧 bookUrl 的缓存目录，缓存键按 `<bookUrl>` 划分，不会串到新源 |

---

## 11. 工作量估算

| 项 | 新增/改动 | 估算 |
|---|---|---|
| P0-2 配置持久化 + `ReadStyleConfig` | 1 新 + 3 改 | 0.5 天 |
| P0-8 字符集 + 续页 | 1 新 + 2 改 | 1 天（Big5 无嗅探支持，需靠 meta + 候选打分兜底，映射表比原估更厚） |
| P0-5 替换净化 | 3 新 + 3 改 | 1.5 天 |
| P0-1 菜单骨架 + 面板 | 5 新 + 2 改 | 2.7 天（点击区域/音量键双路径/翻页动画各占大头） |
| P0-3 书签 | 2 新 + 2 改 | 1 天 |
| P0-6 朗读面板 | 2 新 + 2 改 + Xcode 工程 + Info.plist | 1.5 天 |
| P0-4 换源 | 3 新 + 3 改 | 2 天（`ChapterMatcher` 单测占一半） |
| P0-7 搜索范围 + 历史 | 2 新 + 3 改 | 1 天 |
| 单测 + 真机走查 | — | 1.5 天 |
| iOS/macOS 双平台 `#if` 守卫 + 构建门禁 | 贯穿 | 0.5 天 |
| **合计** | | **≈ 13.2 人天** |

---

## 12. P0 实施状态（代码落地后回填）

八项全部落地，双平台门禁通过：`swift build` = Build complete，`xcodebuild -scheme LegadoApp -sdk iphonesimulator16.2` = ** BUILD SUCCEEDED **（`-target-triple ...ios15.0-simulator`，最低版本未抬高），`swift test` = 176 例 / 174 通过。

余下 2 例失败是**改造前就在失败**的联网用例 `testFetchBookDetailAuthorAndIntro`、`testBookWithVolumeDividersChapterContiguity`（都打 `https://n.novelia.cc` 真实站点，本沙箱无外网/SSL 受限）。已用 `git stash -u` 回到 P0 之前重跑验证：同样这 2 例失败，与本次改动无关。

| 项 | 新增文件 | 关键改动 | 单测 |
|---|---|---|---|
| P0-2 配置持久化 | `Models/ReadConfig.swift`、`Service/ReaderStore.swift`、`Utils/TolerantJSON.swift` | `Theme/ReaderConfig.swift` 全量重写：`@Published` 存值 + `didSet` 落盘（原实现这三个字段根本没有 `didSet`，是「设置不保存」的根因） | `ReaderConfigTests` 18 |
| P0-8 字符集 + 续页 | `Utils/CharsetDetector.swift` | `NetworkClient` 3 次重试 + 解码链；`BookContentService` 正文 `nextContentUrl` 循环、目录 `nextTocUrl` 循环、`normalizeToc` | `CharsetAndPagingTests` 27 |
| P0-5 替换净化 + 简繁 | `Models/ReplaceRule.swift`、`Service/ReplaceRuleStore.swift`、`Service/ContentProcessor.swift`、`Utils/ChineseConverter.swift`、`Views/Settings/ReplaceRuleListView.swift` | `Book.useReplaceRule`；`ReaderView.parseContentBlocks` 不再手工补 `　　`（会与净化层的缩进叠加） | `ReplaceRuleTests` 27 + `ChineseConverterTests` 5 |
| P0-1 菜单骨架 + 面板 | `Views/Reader/Panels/{ReadStylePanel,MoreSettingsPanel,ReaderOverlays}.swift` | `ReaderView` 拆 `readingCanvas/controlsLayer/panelLayer`（单体 `ZStack` 已超类型检查预算）；`ReaderPanel` 枚举保证同时只开一个面板 | 依赖手工走查 |
| P0-3 书签 | `Models/Bookmark.swift`、`Views/Reader/Sheets/BookmarkSheet.swift` | 按「书名+作者」建索引，换源后书签不丢；`loadInitialChapter(targetCharPos:)` 还原段内位置 | `BookmarkTests` 10 |
| P0-6 朗读 | `Views/Reader/Panels/ReadAloudPanel.swift`、`Service/ReadAloudText.swift` | `AudioBookService` 改段落队列 + `MPRemoteCommandCenter` + `ttsTimer` 定时；Info.plist 加 `UIBackgroundModes: audio` | `ReadAloudTextTests` 10 |
| P0-4 换源 | `Utils/ChapterMatcher.swift`、`Service/ChangeSourceService.swift`、`Views/Reader/Sheets/ChangeSourceSheet.swift` | `BookStore.changeSource` 原地替换书架槽位并清旧缓存；`ReaderView` 单章/整书/自动三条入口 | `ChapterMatcherTests` 14 + `ChangeSourceServiceTests` 6 |
| P0-7 搜索范围 + 历史 | `Models/SearchKeyword.swift`、`Models/SearchScope.swift`、`Views/Search/SearchScopeSheet.swift` | `SearchViewModel` 的 `selectedSourceUrl` → `scope`；`SearchMerger.merge` 按 (name, author) 合并 `origins`，`rank` 做等值/包含/其余三桶（精准时丢其余桶）；停止/继续 | `SearchScopeTests` 36 |

未修就会留下 bug 的两处顺带修复：设置页「清理阅读缓存」原先只弹提示、不删任何文件；阅读页字号/行距/主题不持久化（见 P0-2）。

### 12.0 面板定位 bug（本轮修掉的第三个既有 bug）

`ReaderView.bottomAnchored(maxHeight:)` 把 `.frame(maxHeight:)` 加在 `VStack { Spacer; panel }` **整体**上。
`.frame(maxHeight:)` 会把包起来的视图在父级给到的空间里**居中**，所以凡是传了有限值的面板都悬在屏幕中段，
只有传 `.infinity` 的「界面」恰好填满因而看起来正常。这就是「更多设置位置不对」的真正原因，
前两轮改卡片高度/圆角都没有碰到它。现在把上限收到内容自身，并把 `.transition(.move)` 也移到内容上
（整栈是满高的，滑整栈会让面板从一屏之外飞进来）。

### 12.1 P0 遗留（下次继续做，不是新需求）

- `progressBarBehavior` 接线 + 恢复该 picker（进度条按章 / 按页）。
- 亮度调节已删除（§10 #26），若日后要恢复需重做成不叠加在正文上的控件。
- 滚动模式下的朗读段落高亮（用 `audioService.currentCharPos`）。
- 点击区域 `.editContent` / `.syncProgress` 两个动作码。
- 顶栏「换源 / 刷新」两个图标按钮（目前只在溢出菜单里）。
- **书籍详情页的换源入口**：`ChangeSourceSheet` 与 `BookStore.changeSource` 都可用，但入口目前只在阅读页，`BookDetailView` 里仍无按钮（README 架构图已按实情改掉，不再写「换源」）。
- 仿真翻页卷曲效果（#1）。

### 12.2 手工验证清单（9.2 的 1–13 条尚未逐条走查）

代码门禁覆盖不到 UI 行为，特别是音量键、后台朗读锁屏控制、真机熄屏与 WebDAV 与 Android 互通。这 13 条需要在真机上过一遍再谈 P0 收口。

---

# 第二部分：P1（待补写）

范围见 `FEATURE_GAP_ANALYSIS.md` §23 P1：书源编辑器全字段（6 Tab）、书源调试页、校验书源、书架分组/网格/排序/布局对话框、书架管理多选与批量、本地导入文件树、远程 WebDAV 书籍浏览、书籍信息编辑页与换封面、备份覆盖 21 类 + 恢复忽略列表、TXT 目录规则管理页、二维码扫描/生成。

> 前置：P0-2 的 `ReadStyleConfig` 落盘范式可直接复用到 P1 的各类规则库持久化；P0-5 的 `ContentProcessor` 是 P1「TXT 目录规则」与「字典规则」的公共底座。

# 第三部分：P2（待补写）

范围见 `FEATURE_GAP_ANALYSIS.md` §23 P2/P3：RSS 订阅整模块、我的页 + 4 个子设置页、主题系统、阅读记录/所有书签/文件管理/关于、HttpTTS + 音频书播放页、漫画模式、词典取词、离线缓存与导出、局域网 Web 服务与外部集成（App Intents / Share Extension / URL Scheme / Widget）。
