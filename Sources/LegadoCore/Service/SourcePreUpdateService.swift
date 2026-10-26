import Foundation

/// Runs Android's explicit preUpdateJs hook off the UI executor. Native bridge calls may
/// synchronously wait here while their existing async network services run on another task.
/// This bounds native waits and cancels queued work; it cannot interrupt a pure JS loop.
public final class SourcePreUpdateService {
    private static let workers: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "Legado.preUpdateJs"
        queue.maxConcurrentOperationCount = 2
        queue.qualityOfService = .utility
        return queue
    }()
    private static let bridgeBudget: TimeInterval = 30

    public init() {}

    public func run(book: Book, source: BookSource) async throws -> Book {
        try Task.checkCancellation()
        guard let rule = source.ruleToc?.preUpdateJs,
              !rule.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return book }
        let completion = Completion<Book>()
        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                completion.install(continuation)
                Self.workers.addOperation {
                    guard !completion.isCancelled else { return }
                    do {
                        let deadline = ProcessInfo.processInfo.systemUptime + Self.bridgeBudget
                        let engine = JSEngine(bookSource: source, book: book, baseUrl: book.bookUrl)
                        try engine.checkReady()
                        engine.installPreUpdateActions(refresh: { current in
                            try Self.waitForNative(completion: completion, deadline: deadline) {
                                try await BookContentService.shared.fetchBookInfo(book: current, source: source)
                            }
                        }, reGet: { current in
                            try Self.waitForNative(completion: completion, deadline: deadline) {
                                let candidates = try await BookSearchService.shared.search(source: source, key: current.name)
                                try Task.checkCancellation()
                                guard let match = candidates.first(where: {
                                    $0.name.trimmingCharacters(in: .whitespacesAndNewlines) == current.name.trimmingCharacters(in: .whitespacesAndNewlines)
                                        && $0.author.trimmingCharacters(in: .whitespacesAndNewlines) == current.author.trimmingCharacters(in: .whitespacesAndNewlines)
                                }) else { throw SourceRuntimeError.bridge("reGetBook 未找到书名与作者相同的书籍") }
                                var relocated = current
                                relocated.bookUrl = match.bookUrl
                                relocated.tocUrl = ""
                                return try await BookContentService.shared.fetchBookInfo(book: relocated, source: source)
                            }
                        })
                        guard !completion.isCancelled else { return }
                        _ = try engine.evalChecked(script: JSEngine.extractJSScript(from: rule) ?? rule, stage: "preUpdateJs")
                        let updated = engine.bookSnapshot() ?? book
                        guard !updated.bookUrl.isEmpty else { throw SourceRuntimeError.bridge("preUpdateJs 返回的书籍网址为空") }
                        completion.finish(.success(updated))
                    } catch { completion.finish(.failure(error)) }
                }
            }
        }, onCancel: { completion.cancel() })
    }

    private static func waitForNative<Value>(completion: Completion<Book>, deadline: TimeInterval,
                                             operation: @escaping () async throws -> Value) throws -> Value {
        guard !completion.isCancelled else { throw CancellationError() }
        guard ProcessInfo.processInfo.systemUptime < deadline else { throw URLError(.timedOut) }
        let box = NativeResult<Value>()
        let task = Task.detached {
            do { box.store(.success(try await operation())) }
            catch { box.store(.failure(error)) }
        }
        while box.ready.wait(timeout: .now() + 0.05) == .timedOut {
            if completion.isCancelled { task.cancel(); throw CancellationError() }
            if ProcessInfo.processInfo.systemUptime >= deadline { task.cancel(); throw URLError(.timedOut) }
        }
        guard !completion.isCancelled else { task.cancel(); throw CancellationError() }
        return try box.take().get()
    }

    private final class NativeResult<Value> {
        let ready = DispatchSemaphore(value: 0)
        private let lock = NSLock()
        private var result: Result<Value, Error>?
        func store(_ value: Result<Value, Error>) {
            lock.lock(); result = value; lock.unlock()
            ready.signal()
        }
        func take() -> Result<Value, Error> {
            lock.lock(); defer { lock.unlock() }
            return result!
        }
    }

    private final class Completion<Value> {
        private let lock = NSLock()
        private var cancelled = false
        private var result: Result<Value, Error>?
        private var continuation: CheckedContinuation<Value, Error>?
        var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
        func install(_ continuation: CheckedContinuation<Value, Error>) {
            lock.lock()
            if let result = result { lock.unlock(); continuation.resume(with: result) }
            else { self.continuation = continuation; lock.unlock() }
        }
        func finish(_ value: Result<Value, Error>) {
            lock.lock()
            guard result == nil else { lock.unlock(); return }
            result = value
            let waiting = continuation
            continuation = nil
            lock.unlock()
            waiting?.resume(with: value)
        }
        func cancel() {
            lock.lock()
            cancelled = true
            guard result == nil else { lock.unlock(); return }
            let value: Result<Value, Error> = .failure(CancellationError())
            result = value
            let waiting = continuation
            continuation = nil
            lock.unlock()
            waiting?.resume(with: value)
        }
    }
}
