import XCTest
@testable import LegadoCore

/// `LocalWebServer`'s upload path: a browser posts `multipart/form-data`, and the book that
/// reaches `onBookUploaded` must be exactly the bytes the user picked.
///
/// Both assertions here failed before the parser existed: the raw body (framing included) was
/// handed to the importer, so TXT and EPUB uploads could never open.
final class LocalWebServerTests: XCTestCase {

    private func multipart(boundary: String, filename: String, payload: Data) -> Data {
        var body = Data()
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".utf8))
        body.append(Data("Content-Type: text/plain\r\n\r\n".utf8))
        body.append(payload)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        return body
    }

    func testExtractsPayloadWithoutFraming() {
        let payload = Data("第一章 启程\n正文内容。\n".utf8)
        let body = multipart(boundary: "----WebKitFormBoundaryABC123", filename: "book.txt", payload: payload)

        let parts = LocalWebServer.parseMultipart(body: body, boundary: "----WebKitFormBoundaryABC123")

        XCTAssertEqual(parts.count, 1)
        XCTAssertEqual(parts.first?.filename, "book.txt")
        XCTAssertEqual(parts.first?.data, payload, "the saved file must be the book, not the multipart envelope")
    }

    /// A body larger than one TCP segment is the case that used to truncate at 64 KB.
    func testExtractsLargePayloadIntact() {
        let line = "第一章 标题\n正文内容正文内容正文内容\n"
        let payload = Data(String(repeating: line, count: 8_000).utf8)
        XCTAssertGreaterThan(payload.count, 200_000)

        let body = multipart(boundary: "b0undary", filename: "big.txt", payload: payload)
        let parts = LocalWebServer.parseMultipart(body: body, boundary: "b0undary")

        XCTAssertEqual(parts.first?.data.count, payload.count)
        XCTAssertEqual(parts.first?.data, payload)
    }

    func testPayloadContainingCRLFAndDashesSurvives() {
        // Text files routinely contain `\r\n`; only the exact boundary sequence may end a part.
        let payload = Data("line one\r\nline two\r\n--not-the-boundary\r\nend".utf8)
        let body = multipart(boundary: "XYZ", filename: "crlf.txt", payload: payload)

        let parts = LocalWebServer.parseMultipart(body: body, boundary: "XYZ")

        XCTAssertEqual(parts.first?.data, payload)
    }

    func testMissingBoundaryYieldsNoParts() {
        let body = multipart(boundary: "ABC", filename: "a.txt", payload: Data("x".utf8))
        XCTAssertTrue(LocalWebServer.parseMultipart(body: body, boundary: "OTHER").isEmpty)
    }
}
