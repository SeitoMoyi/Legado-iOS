import XCTest
@testable import LegadoCore

/// P0-6: read-aloud text segmentation. These offsets are the same unit as
/// `Book.durChapterPos` and `Bookmark.chapterPos`, so the round-trip invariant below is a
/// cross-feature contract, not an implementation detail.
final class ReadAloudTextTests: XCTestCase {

    private let chapter = """
    第一章 开始
    第一段内容。
    第二段内容，更长一些，用来验证偏移。

    ***
    第三段内容。
    """

    func testParagraphsSplitOnNewlineAndDropBlankLines() {
        let paragraphs = ReadAloudText.paragraphs(in: chapter)
        XCTAssertEqual(paragraphs,
                       ["第一章 开始", "第一段内容。", "第二段内容，更长一些，用来验证偏移。", "***", "第三段内容。"])
    }

    func testWhitespaceOnlyLinesAreDropped() {
        XCTAssertEqual(ReadAloudText.paragraphs(in: "a\n   \n\nb"), ["a", "b"])
    }

    func testOffsetRoundTripsBackToTheSameParagraph() {
        let paragraphs = ReadAloudText.paragraphs(in: chapter)
        for index in paragraphs.indices {
            let position = ReadAloudText.offset(of: paragraphs, at: index)
            XCTAssertEqual(ReadAloudText.paragraphIndex(containing: position, in: paragraphs), index,
                           "paragraph \(index) must be found from its own offset")
        }
    }

    func testOffsetsCountSeparators() {
        let paragraphs = ["abc", "de", "f"]
        XCTAssertEqual(ReadAloudText.offset(of: paragraphs, at: 0), 0)
        XCTAssertEqual(ReadAloudText.offset(of: paragraphs, at: 1), 4, "3 + newline")
        XCTAssertEqual(ReadAloudText.offset(of: paragraphs, at: 2), 7, "3 + 1 + 2 + 1")
    }

    func testMidParagraphPositionResolvesToItsParagraph() {
        let paragraphs = ["abcdef", "ghijkl"]
        XCTAssertEqual(ReadAloudText.paragraphIndex(containing: 3, in: paragraphs), 0)
        XCTAssertEqual(ReadAloudText.paragraphIndex(containing: 8, in: paragraphs), 1)
    }

    func testPositionBeyondTextClampsToLastParagraph() {
        let paragraphs = ["a", "b"]
        XCTAssertEqual(ReadAloudText.paragraphIndex(containing: 9_999, in: paragraphs), 1)
        XCTAssertEqual(ReadAloudText.paragraphIndex(containing: 0, in: paragraphs), 0)
        XCTAssertEqual(ReadAloudText.paragraphIndex(containing: 5, in: []), 0)
    }

    func testSpeakabilityMatchesAndroidPunctuationRule() {
        XCTAssertFalse(ReadAloudText.isSpeakable("***"))
        XCTAssertFalse(ReadAloudText.isSpeakable("——"))
        XCTAssertFalse(ReadAloudText.isSpeakable("。。。"))
        XCTAssertFalse(ReadAloudText.isSpeakable(""))
        XCTAssertTrue(ReadAloudText.isSpeakable("正文"))
        // A line mixing punctuation with real characters is still worth speaking.
        XCTAssertTrue(ReadAloudText.isSpeakable("「你好」"))
    }

    func testNextSpeakableSkipsDecorativeSeparators() {
        let paragraphs = ["正文一", "***", "————", "正文二"]
        XCTAssertEqual(ReadAloudText.nextSpeakableIndex(paragraphs, from: 1, forward: true), 3)
        XCTAssertEqual(ReadAloudText.nextSpeakableIndex(paragraphs, from: 2, forward: false), 0)
    }

    func testNextSpeakableReturnsNilWhenNothingIsLeft() {
        let paragraphs = ["***", "——"]
        XCTAssertNil(ReadAloudText.nextSpeakableIndex(paragraphs, from: 0, forward: true))
        XCTAssertNil(ReadAloudText.nextSpeakableIndex(paragraphs, from: 1, forward: false))
        XCTAssertNil(ReadAloudText.nextSpeakableIndex([], from: 0, forward: true))
    }

    func testNextSpeakableDoesNotLoopForeverOnMixedList() {
        let paragraphs = ["***", "正文"]
        // Starting on the separator and walking backwards must terminate by wrapping into nil.
        XCTAssertNil(ReadAloudText.nextSpeakableIndex(paragraphs, from: 0, forward: false))
        XCTAssertEqual(ReadAloudText.nextSpeakableIndex(paragraphs, from: 0, forward: true), 1)
    }

    // MARK: - Starting speech from the current page

    /// The reader resolves the page anchor to a paragraph through exactly this pair of calls,
    /// so the anchor has to land on the paragraph the eye is on — not the chapter head.
    func testPageAnchorResolvesToItsOwnParagraph() {
        let content = "　　第一段内容。\n　　第二段内容。\n　　第三段内容。\n　　第四段内容。"
        let paragraphs = ReadAloudText.paragraphs(in: content)
        let anchor = "　　第三段内容。".trimmingCharacters(in: .whitespaces)

        guard let index = paragraphs.firstIndex(of: anchor) else {
            return XCTFail("anchor paragraph must be findable after trimming")
        }
        XCTAssertEqual(index, 2)
        let position = ReadAloudText.offset(of: paragraphs, at: index)
        XCTAssertEqual(ReadAloudText.paragraphIndex(containing: position, in: paragraphs), 2)
    }

    /// `ContentProcessor` leaves `[image:…]` inline; speaking it would read the URL aloud.
    func testImagePlaceholderIsNeverSpoken() {
        XCTAssertFalse(ReadAloudText.isSpeakable("[image:https://a.test/1.png]"))
        let paragraphs = ReadAloudText.paragraphs(in: "正文一\n[image:https://a.test/1.png]\n正文二")
        XCTAssertEqual(paragraphs.count, 3)
        XCTAssertEqual(ReadAloudText.nextSpeakableIndex(paragraphs, from: 1, forward: true), 2)
        XCTAssertEqual(ReadAloudText.nextSpeakableIndex(paragraphs, from: 1, forward: false), 0)
    }
}
