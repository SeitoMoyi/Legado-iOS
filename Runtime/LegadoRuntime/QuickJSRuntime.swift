import Foundation
import CQuickJS

public enum QuickJSRuntimeError: LocalizedError, Equatable {
    case invalidLimits
    case allocation
    case sourceLimit
    case outputLimit
    case timeout
    case cancelled
    case script(String)

    public var errorDescription: String? {
        switch self {
        case .invalidLimits: return "脚本执行限制无效"
        case .allocation: return "脚本运行时内存不足"
        case .sourceLimit: return "脚本或输入数据超过大小限制"
        case .outputLimit: return "脚本输出超过大小限制"
        case .timeout: return "脚本执行超时"
        case .cancelled: return "脚本执行已取消"
        case .script(let message): return message
        }
    }
}

/// One-shot, thread-safe cancellation signal. Create a new signal for each evaluation.
public final class ScriptCancellation: @unchecked Sendable {
    fileprivate let handle: OpaquePointer

    public init() throws {
        guard let handle = lqjs_cancellation_create() else { throw QuickJSRuntimeError.allocation }
        self.handle = handle
    }

    public func cancel() { lqjs_cancellation_cancel(handle) }
    public var isCancelled: Bool { lqjs_cancellation_is_cancelled(handle) != 0 }
    deinit { lqjs_cancellation_destroy(handle) }
}

/// A serialized, owned runtime for the v0.3.1 adapter investigation. It currently exposes
/// synchronous global evaluation with JSON results, without Legado's host bridges.
public final class QuickJSRuntime: @unchecked Sendable {
    public struct Limits: Sendable {
        public var memoryBytes: Int
        public var stackBytes: Int
        public var sourceBytes: Int
        public var outputBytes: Int

        public init(memoryBytes: Int = 16 * 1024 * 1024, stackBytes: Int = 256 * 1024,
                    sourceBytes: Int = 1024 * 1024, outputBytes: Int = 1024 * 1024) {
            self.memoryBytes = memoryBytes
            self.stackBytes = stackBytes
            self.sourceBytes = sourceBytes
            self.outputBytes = outputBytes
        }
    }

    private let handle: OpaquePointer
    private let limits: Limits
    private let lock = NSRecursiveLock()
    private struct Evaluation {
        let deadline: TimeInterval
        let cancellation: ScriptCancellation?
        let shouldCancel: () -> Bool
    }
    private var evaluations: [Evaluation] = []
    private var storedHostCall: ((String, [Any]) throws -> Any?)?

    public var hostCall: ((String, [Any]) throws -> Any?)? {
        get { lock.lock(); defer { lock.unlock() }; return storedHostCall }
        set { lock.lock(); storedHostCall = newValue; lock.unlock() }
    }

    public var remainingTime: TimeInterval {
        lock.lock(); defer { lock.unlock() }
        return max(0, (evaluations.last?.deadline ?? ProcessInfo.processInfo.systemUptime) - ProcessInfo.processInfo.systemUptime)
    }

    public var shouldStop: Bool {
        lock.lock(); defer { lock.unlock() }
        guard let evaluation = evaluations.last else { return false }
        return evaluation.cancellation?.isCancelled == true || evaluation.shouldCancel()
            || ProcessInfo.processInfo.systemUptime >= evaluation.deadline
    }

    public init(limits: Limits = Limits()) throws {
        guard limits.memoryBytes > 0, limits.stackBytes > 0,
              limits.sourceBytes > 0, limits.outputBytes > 0 else { throw QuickJSRuntimeError.invalidLimits }
        guard let handle = lqjs_create(limits.memoryBytes, limits.stackBytes) else { throw QuickJSRuntimeError.allocation }
        self.handle = handle
        self.limits = limits
        lqjs_set_host(handle, Self.callHost, Self.checkCancellation, Unmanaged.passUnretained(self).toOpaque())
    }

    deinit { lqjs_destroy(handle) }

    /// Returns JSON text, or nil for undefined / values without a JSON representation.
    /// The execution budget starts after acquiring the runtime lock; callers should not
    /// submit UI work here. Pending Promise jobs and modules are deliberately not executed.
    public func evaluate(_ script: String, timeout: TimeInterval = 0.25,
                         cancellation: ScriptCancellation? = nil,
                         shouldCancel: @escaping () -> Bool = { false }) throws -> String? {
        guard timeout.isFinite, timeout > 0, timeout <= 60 else { throw QuickJSRuntimeError.invalidLimits }
        guard script.utf8.count <= limits.sourceBytes else { throw QuickJSRuntimeError.sourceLimit }
        lock.lock()
        defer { lock.unlock() }
        guard evaluations.count < 16 else { throw QuickJSRuntimeError.script("Host evaluation nesting limit exceeded") }
        let now = ProcessInfo.processInfo.systemUptime
        let deadline = min(now + timeout, evaluations.last?.deadline ?? (now + timeout))
        guard deadline > now else { throw QuickJSRuntimeError.timeout }
        let parent = evaluations.last
        evaluations.append(Evaluation(deadline: deadline, cancellation: cancellation, shouldCancel: {
            shouldCancel() || parent?.cancellation?.isCancelled == true || parent?.shouldCancel() == true
        }))
        defer { evaluations.removeLast() }
        let result = withExtendedLifetime(cancellation) {
            script.withCString { buffer in
                lqjs_evaluate(handle, buffer, script.utf8.count, UInt64((deadline - now) * 1_000_000_000),
                              limits.outputBytes, cancellation?.handle)
            }
        }
        defer { lqjs_result_destroy(result) }
        switch result.status {
        case LQJS_OK: return result.json.map { String(cString: $0) }
        case LQJS_TIMEOUT: throw QuickJSRuntimeError.timeout
        case LQJS_CANCELLED: throw QuickJSRuntimeError.cancelled
        case LQJS_OUTPUT_LIMIT: throw QuickJSRuntimeError.outputLimit
        case LQJS_ALLOCATION_ERROR: throw QuickJSRuntimeError.allocation
        default: throw QuickJSRuntimeError.script(result.error.map { String(cString: $0) } ?? "JavaScript evaluation failed")
        }
    }

    public func setGlobal(_ name: String, value: Any) throws {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed, .sortedKeys])
        guard data.count <= limits.outputBytes else { throw QuickJSRuntimeError.sourceLimit }
        lock.lock(); defer { lock.unlock() }
        let json = String(decoding: data, as: UTF8.self)
        let result = name.withCString { name in json.withCString { lqjs_set_global(handle, name, $0, data.count) } }
        defer { lqjs_result_destroy(result) }
        guard result.status == LQJS_OK else { throw QuickJSRuntimeError.script("Unable to install script binding") }
    }

    private static let checkCancellation: LQJSShouldCancel = { opaque in
        guard let opaque = opaque else { return 0 }
        let runtime = Unmanaged<QuickJSRuntime>.fromOpaque(opaque).takeUnretainedValue()
        guard let evaluation = runtime.evaluations.last else { return 0 }
        return evaluation.cancellation?.isCancelled == true || evaluation.shouldCancel() ? 1 : 0
    }

    private static let callHost: LQJSHostCall = { opaque, action, arguments in
        guard let opaque = opaque, let action = action, let arguments = arguments else { return nil }
        let runtime = Unmanaged<QuickJSRuntime>.fromOpaque(opaque).takeUnretainedValue()
        let envelope: [String: Any]
        do {
            guard !runtime.shouldStop else { throw QuickJSRuntimeError.cancelled }
            let data = Data(String(cString: arguments).utf8)
            guard let args = try JSONSerialization.jsonObject(with: data) as? [Any],
                  let handler = runtime.storedHostCall else { throw QuickJSRuntimeError.script("Missing host bridge") }
            envelope = ["value": try handler(String(cString: action), args) ?? NSNull()]
        } catch { envelope = ["error": error.localizedDescription] }
        guard let data = try? JSONSerialization.data(withJSONObject: envelope), data.count <= runtime.limits.outputBytes else {
            return strdup("{\"error\":\"Host response exceeds size limit or is not JSON\"}")
        }
        return strdup(String(decoding: data, as: UTF8.self))
    }
}
