import Foundation

#if canImport(UIKit)
import UIKit
#endif

/// Clipboard token reader for deferred resolve cascade (`Pasteboard.readToken` adapter).
/// Named `PasteboardClient` to avoid clashing with macOS `ApplicationServices.Pasteboard`.
public protocol PasteboardClient: AnyObject {
    /// Returns a non-empty clipboard token, or nil on deny / empty / error (soft-skip).
    func readToken() -> String?
}

/// Production UIPasteboard adapter.
/// Soft-skips on nil, empty, or any throw — never crashes launch.
public final class UIPasteboardPasteboard: PasteboardClient, @unchecked Sendable {
    public init() {}

    public func readToken() -> String? {
        #if canImport(UIKit) && os(iOS)
        return SoftSkip.read {
            let value = UIPasteboard.general.string
            guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }
            return value
        }
        #else
        // macOS / non-iOS hosts: no UIPasteboard — soft-skip.
        return nil
        #endif
    }
}

/// Fixed-token pasteboard for tests and claim injection demos.
public final class FixedPasteboard: PasteboardClient, @unchecked Sendable {
    private let token: String?

    public init(token: String?) {
        self.token = token
    }

    public func readToken() -> String? {
        guard let token, !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return token
    }
}

enum SoftSkip {
    static func read(_ body: () throws -> String?) -> String? {
        do {
            return try body()
        } catch {
            return nil
        }
    }
}
