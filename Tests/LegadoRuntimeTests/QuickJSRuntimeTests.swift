import XCTest
import LegadoRuntime

final class QuickJSRuntimeTests: XCTestCase {
    func testJsonBoundaryAndFreshContextIsolation() throws {
        let first = try QuickJSRuntime()
        XCTAssertEqual(try first.evaluate("var shared = 7; ({value: shared, text: '正文'})"), #"{"value":7,"text":"正文"}"#)
        XCTAssertNil(try first.evaluate("undefined"))
        XCTAssertEqual(try first.evaluate("null"), "null")
        let second = try QuickJSRuntime()
        XCTAssertEqual(try second.evaluate("typeof shared"), #""undefined""#)
        XCTAssertEqual(try first.evaluate("shared"), "7")
    }

    func testRepeatedLoopInterruptionAndRecovery() throws {
        let runtime = try QuickJSRuntime()
        let loops = ["while (true) {}", "for (;;) {}", "(function(){for (;;) {}})()"]
        for index in 0..<50 {
            XCTAssertThrowsError(try runtime.evaluate(loops[index % loops.count], timeout: 0.005)) {
                XCTAssertEqual($0 as? QuickJSRuntimeError, .timeout)
            }
            XCTAssertEqual(try runtime.evaluate("1 + 1"), "2")
        }
    }

    func testCancellationBeforeExecutionAndDuringLoop() throws {
        let runtime = try QuickJSRuntime()
        let cancelled = try ScriptCancellation()
        cancelled.cancel()
        XCTAssertThrowsError(try runtime.evaluate("var shouldNotRun = true", cancellation: cancelled)) {
            XCTAssertEqual($0 as? QuickJSRuntimeError, .cancelled)
        }
        XCTAssertEqual(try runtime.evaluate("typeof shouldNotRun"), #""undefined""#)
        let active = try ScriptCancellation()
        let done = expectation(description: "Running loop interrupted by another thread")
        DispatchQueue.global().async {
            do {
                _ = try runtime.evaluate("while (true) {}", timeout: 2, cancellation: active)
                XCTFail("Expected cancellation")
            } catch {
                XCTAssertEqual(error as? QuickJSRuntimeError, .cancelled)
            }
            done.fulfill()
        }
        // Cancelling either before dispatch or during execution must prevent a result.
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.025) { active.cancel() }
        wait(for: [done], timeout: 3)
        XCTAssertEqual(try runtime.evaluate("3 + 4"), "7")
    }

    func testRecursionAndAllocationFailuresDoNotPoisonRuntime() throws {
        let runtime = try QuickJSRuntime()
        XCTAssertThrowsError(try runtime.evaluate("(function recurse(){return recurse()})()"))
        XCTAssertEqual(try runtime.evaluate("2 + 2"), "4")
        XCTAssertThrowsError(try runtime.evaluate("new ArrayBuffer(64 * 1024 * 1024)"))
        XCTAssertThrowsError(try runtime.evaluate("Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0)"))
        XCTAssertEqual(try runtime.evaluate("5 + 5"), "10")
    }

    func testSerializationAndErrorFormattingAreInsideExecutionBudget() throws {
        let runtime = try QuickJSRuntime()
        XCTAssertThrowsError(try runtime.evaluate("({toJSON(){while(true){}}})", timeout: 0.005)) {
            XCTAssertEqual($0 as? QuickJSRuntimeError, .timeout)
        }
        XCTAssertThrowsError(try runtime.evaluate("throw {toString(){while(true){}}}", timeout: 0.005)) {
            XCTAssertEqual($0 as? QuickJSRuntimeError, .timeout)
        }
        XCTAssertEqual(try runtime.evaluate("6 + 6"), "12")
    }

    func testInputOutputLimitsAndSyntaxErrors() throws {
        let runtime = try QuickJSRuntime(limits: .init(sourceBytes: 64, outputBytes: 16))
        XCTAssertThrowsError(try runtime.evaluate(String(repeating: "文", count: 22))) {
            XCTAssertEqual($0 as? QuickJSRuntimeError, .sourceLimit)
        }
        XCTAssertThrowsError(try runtime.evaluate("'x'.repeat(32)")) {
            XCTAssertEqual($0 as? QuickJSRuntimeError, .outputLimit)
        }
        XCTAssertThrowsError(try runtime.evaluate("function {"))
        XCTAssertEqual(try runtime.evaluate("1"), "1")
        for timeout in [0, -1, Double.infinity, Double.nan, 61] {
            XCTAssertThrowsError(try runtime.evaluate("1", timeout: timeout)) {
                XCTAssertEqual($0 as? QuickJSRuntimeError, .invalidLimits)
            }
        }
        XCTAssertThrowsError(try QuickJSRuntime(limits: .init(memoryBytes: -1)))
    }

    func testRuntimeAndCancellationOwnershipIsReleased() throws {
        weak var releasedRuntime: QuickJSRuntime?
        weak var releasedCancellation: ScriptCancellation?
        for _ in 0..<50 {
            try autoreleasepool {
                let runtime = try QuickJSRuntime()
                let cancellation = try ScriptCancellation()
                releasedRuntime = runtime
                releasedCancellation = cancellation
                XCTAssertEqual(try runtime.evaluate("JSON.stringify({ready:true})", cancellation: cancellation), #""{\"ready\":true}""#)
            }
            XCTAssertNil(releasedRuntime)
            XCTAssertNil(releasedCancellation)
        }
    }
}
