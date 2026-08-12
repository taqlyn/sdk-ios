import Foundation

/// Optional App Clip → full-app handoff (App Group / invocation).
/// Phase 05 ships a stub that always returns nil.
public protocol AppClipBridge: AnyObject {
    /// Returns an invocation token when available; nil soft-skips to clipboard/claim.
    func readInvocation() -> String?
}

/// Stub App Clip bridge — always nil until product opts into App Clip handoff.
public final class StubAppClipBridge: AppClipBridge, @unchecked Sendable {
    public init() {}

    public func readInvocation() -> String? { nil }
}

/// Fixed invocation for tests.
public final class FixedAppClipBridge: AppClipBridge, @unchecked Sendable {
    private let token: String?

    public init(token: String?) {
        self.token = token
    }

    public func readInvocation() -> String? {
        guard let token, !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return token
    }
}
