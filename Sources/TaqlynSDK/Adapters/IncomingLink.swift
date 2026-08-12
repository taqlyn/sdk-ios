import Foundation

/// Warm Universal Links / onOpenURL stream.
/// Feature code observes via `SdkCore.observeLinks`, not this type.
public protocol IncomingLink: AnyObject {
    /// Emits verified / cold-start Universal Link URLs.
    func observe() -> AsyncStream<URL>

    /// Forward an opened URL (call from SwiftUI `.onOpenURL` or scene delegate).
    func onOpenURL(_ url: URL)
}

/// Default in-process Universal Links adapter using AsyncStream continuations.
public final class ContinuationsIncomingLink: IncomingLink, @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [UUID: AsyncStream<URL>.Continuation] = [:]
    private var lastURL: URL?

    public init() {}

    public func observe() -> AsyncStream<URL> {
        AsyncStream { continuation in
            let id = UUID()
            lock.lock()
            continuations[id] = continuation
            let replay = lastURL
            lock.unlock()

            if let replay {
                continuation.yield(replay)
            }

            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                self.lock.lock()
                self.continuations.removeValue(forKey: id)
                self.lock.unlock()
            }
        }
    }

    public func onOpenURL(_ url: URL) {
        lock.lock()
        lastURL = url
        let targets = Array(continuations.values)
        lock.unlock()
        for continuation in targets {
            continuation.yield(url)
        }
    }
}
