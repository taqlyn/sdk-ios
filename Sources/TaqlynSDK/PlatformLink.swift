import Foundation

/// iOS-only custom listener for Universal Links + clipboard / App Clip / claim deferred.
///
/// Install Referrer matches are Android-only and are never delivered here.
/// Feature code should not import `UIPasteboard` — clipboard stays inside `PasteboardClient`.
public protocol TaqlynLinkListener: AnyObject {
    func taqlynDidReceiveLink(_ link: DeferredLink)
}

/// Warm Universal Links, or deferred matches that iOS can produce.
public func isIosPlatformLink(_ link: DeferredLink) -> Bool {
    if !link.isDeferred { return true }
    switch link.matchType {
    case .clipboard, .appClip, .claim:
        return true
    case .installReferrer, .none:
        return false
    }
}

enum SdkCoreListeners {
    private static let lock = NSLock()
    private static var tasks: [UUID: Task<Void, Never>] = [:]

    static func add(_ listener: TaqlynLinkListener) -> UUID {
        let id = UUID()
        let task = Task { [weak listener] in
            for await link in SdkCore.observeLinks() {
                if Task.isCancelled { break }
                guard isIosPlatformLink(link) else { continue }
                listener?.taqlynDidReceiveLink(link)
            }
        }
        lock.lock()
        tasks[id] = task
        lock.unlock()
        return id
    }

    static func remove(_ id: UUID) {
        lock.lock()
        let task = tasks.removeValue(forKey: id)
        lock.unlock()
        task?.cancel()
    }

    static func reset() {
        lock.lock()
        let all = Array(tasks.values)
        tasks.removeAll()
        lock.unlock()
        all.forEach { $0.cancel() }
    }
}
