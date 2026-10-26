import Foundation
import CQuickJS

public enum QuickJSRuntimeError: Error, Equatable {
    case invalidLimits
    case allocation
    case sourceLimit
    case outputLimit
    case timeout
    case cancelled
    case script(String)
}

/// One-shot, thread-safe cancellation signal. Create a new signal for each evaluation.
public final class ScriptCancellation: @unchecked Sendable {
    fileprivate let handle: OpaquePointer

    public init() throws {
        guard let handle = lqjs_cancellation_create() else { throw QuickJSRuntimeError.allocation }
        self.handle = handle
    }

    public func cancel() { lqjs_cancellation_cancel(handle) }
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
    private let lock = NSLock()

    public init(limits: Limits = Limits()) throws {
        guard limits.memoryBytes > 0, limits.stackBytes > 0,
              limits.sourceBytes > 0, limits.outputBytes > 0 else { throw QuickJSRuntimeError.invalidLimits }
        guard let handle = lqjs_create(limits.memoryBytes, limits.stackBytes) else { throw QuickJSRuntimeError.allocation }
        self.handle = handle
        self.limits = limits
    }

    deinit { lqjs_destroy(handle) }

    /// Returns JSON text, or nil for undefined / values without a JSON representation.
    /// The execution budget starts after acquiring the runtime lock; callers should not
    /// submit UI work here. Pending Promise jobs and modules are deliberately not executed.
    public func evaluate(_ script: String, timeout: TimeInterval = 0.25,
                         cancellation: ScriptCancellation? = nil) throws -> String? {
        guard timeout.isFinite, timeout > 0, timeout <= 60 else { throw QuickJSRuntimeError.invalidLimits }
        guard script.utf8.count <= limits.sourceBytes else { throw QuickJSRuntimeError.sourceLimit }
        lock.lock()
        defer { lock.unlock() }
        let result = withExtendedLifetime(cancellation) {
            script.withCString { buffer in
                lqjs_evaluate(handle, buffer, script.utf8.count, UInt64(timeout * 1_000_000_000),
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
}
