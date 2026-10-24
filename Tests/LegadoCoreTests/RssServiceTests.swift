import XCTest
@testable import LegadoCore

/// Plan Phase 1 Part 1: RSS 订阅深度完善 — 分类解析、列表解析、ruleNextPage 翻页与已读状态。
final class RssServiceTests: XCTestCase {

    private var defaults: UserDefaults!
    private let suiteName = "LegadoRssServiceTests"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    // MARK: - ruleNextPage 翻页

    private func source(ruleNextPage: String?) -> RssSource {
        RssSource(
            sourceUrl: "https://example.com",
            sourceName: "测试源",
            ruleArticles: "//item",
            ruleNextPage: ruleNextPage
        )
    }

    func testResolveNextPageFollowsRelativeLink() {
        let html = """
        <div class="list">
          <a href="/p/1">一</a><a href="/p/2">二</a>
        </div>
        <a class="next" href="/list/page/2">下一页</a>
        """
        let next = RssService.shared.resolveNextPageUrl(
            pageBody: html,
            source: source(ruleNextPage: "a.next@href"),
            currentPageUrl: "https://example.com/list/page/1"
        )
        XCTAssertEqual(next, "https://example.com/list/page/2")
    }

    func testResolveNextPageReturnsNilWithoutRule() {
        let html = "<a class=\"next\" href=\"/list/page/2\">下一页</a>"
        let next = RssService.shared.resolveNextPageUrl(
            pageBody: html,
            source: source(ruleNextPage: nil),
            currentPageUrl: "https://example.com/list/page/1"
        )
        XCTAssertNil(next)
    }

    func testResolveNextPageReturnsNilWhenBlankRule() {
        let html = "<a class=\"next\" href=\"/list/page/2\">下一页</a>"
        let next = RssService.shared.resolveNextPageUrl(
            pageBody: html,
            source: source(ruleNextPage: "   "),
            currentPageUrl: "https://example.com/list/page/1"
        )
        XCTAssertNil(next)
    }

    func testResolveNextPageGuardsAgainstSelfLoop() {
        // 页面里「下一页」指向自身（常见于最后一页）：必须返回 nil 停止拼装。
        let html = "<a class=\"next\" href=\"/list/page/1\">下一页</a>"
        let next = RssService.shared.resolveNextPageUrl(
            pageBody: html,
            source: source(ruleNextPage: "a.next@href"),
            currentPageUrl: "https://example.com/list/page/1"
        )
        XCTAssertNil(next)
    }

    func testResolveNextPageGuardsAgainstSourceLoop() {
        let html = "<a class=\"next\" href=\"https://example.com\">首页</a>"
        let next = RssService.shared.resolveNextPageUrl(
            pageBody: html,
            source: source(ruleNextPage: "a.next@href"),
            currentPageUrl: "https://example.com/list/page/1"
        )
        XCTAssertNil(next)
    }

    func testResolveNextPageReturnsNilWhenRuleMisses() {
        let html = "<div class=\"content\">正文，没有翻页链接</div>"
        let next = RssService.shared.resolveNextPageUrl(
            pageBody: html,
            source: source(ruleNextPage: "a.next@href"),
            currentPageUrl: "https://example.com/list/page/1"
        )
        XCTAssertNil(next)
    }

    // MARK: - 已读状态与阅读历史

    private func article(_ link: String) -> RssArticle {
        RssArticle(origin: "https://example.com", sort: "测试源", title: "标题 \(link)", link: link)
    }

    func testMarkArticleReadPersistsStateAndHistory() {
        let a = article("/p/1")
        let b = article("/p/2")
        RssStore.markArticleRead(a, to: defaults)
        RssStore.markArticleRead(b, to: defaults)

        let state = RssStore.loadReadState(from: defaults)
        XCTAssertEqual(state.count, 2)
        XCTAssertNotNil(state[RssStore.articleKey(origin: a.origin, link: a.link)])

        let history = RssStore.loadReadHistory(from: defaults)
        XCTAssertEqual(history.count, 2)
        // 最新的在最前
        XCTAssertEqual(history.first?.link, "/p/2")
        XCTAssertEqual(history.last?.link, "/p/1")

        // isRead 命中持久化 state
        XCTAssertTrue(a.isRead(in: state))
        XCTAssertFalse(article("/p/3").isRead(in: state))
    }

    func testMarkArticleReadIsIdempotent() {
        let a = article("/p/1")
        RssStore.markArticleRead(a, to: defaults)
        let stateAfterFirst = RssStore.loadReadState(from: defaults)
        RssStore.markArticleRead(a, to: defaults)

        XCTAssertEqual(RssStore.loadReadState(from: defaults).count, 1)
        XCTAssertEqual(RssStore.loadReadHistory(from: defaults).count, 1)
        XCTAssertEqual(
            RssStore.loadReadState(from: defaults)[RssStore.articleKey(origin: a.origin, link: a.link)],
            stateAfterFirst[RssStore.articleKey(origin: a.origin, link: a.link)]
        )
    }

    func testReadStateCapping() {
        // 超过 2000 条时裁剪最旧的，防止 store 无限增长。
        var state: [String: Int64] = [:]
        for i in 0..<2_100 {
            state["origin\u{1}/p/\(i)"] = Int64(i)
        }
        RssStore.saveReadState(state, to: defaults)
        let loaded = RssStore.loadReadState(from: defaults)
        XCTAssertEqual(loaded.count, 2_000)
        // 最旧的 (i=0..99) 被淘汰
        XCTAssertNil(loaded["origin\u{1}/p/0"])
        XCTAssertNotNil(loaded["origin\u{1}/p/2099"])
    }

    // MARK: - RssSource 字段完备性（Part 1.1）

    func testRssSourceDefaultsAndAndroidParityFields() {
        let s = source(ruleNextPage: "a.next@href")
        XCTAssertTrue(s.enabled)
        XCTAssertTrue(s.enableJs)
        XCTAssertTrue(s.loadWithBaseUrl)
        XCTAssertEqual(s.articleStyle, 0)
        XCTAssertNil(s.loginUrl)
        XCTAssertNil(s.loginUi)
        XCTAssertNil(s.variable)
    }
}
