import Foundation

/// Canonical iOS SdkCore facade.
///
/// App feature modules import this type only — never UIPasteboard /
/// URLSession / UserDefaults vendor details.
public enum SdkCore {
    private static let gate = ResolveGate()
    private static let store = LockedStore()

    /// Configure early in process lifetime (`App.init` / `@main`).
    ///
    /// Defaults: real pasteboard, stub App Clip, URLSession client,
    /// UserDefaults store, Continuations incoming link.
    public static func configure(
        clientId: String,
        publicKeyId: String,
        options: SdkOptions,
        pasteboard: PasteboardClient? = nil,
        appClip: AppClipBridge? = nil,
        resolveClient: ResolveClient? = nil,
        expandClient: ExpandClient? = nil,
        shareClient: ShareClient? = nil,
        eventsClient: EventsClient? = nil,
        store keyValueStore: KeyValueStore? = nil,
        incomingLink: IncomingLink? = nil
    ) {
        precondition(!clientId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "clientId required")
        precondition(!publicKeyId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "publicKeyId required")

        let config = Config(
            clientId: clientId,
            publicKeyId: publicKeyId,
            options: options,
            pasteboard: pasteboard ?? UIPasteboardPasteboard(),
            appClip: appClip ?? StubAppClipBridge(),
            resolveClient: resolveClient ?? URLSessionResolveClient(),
            expandClient: expandClient ?? URLSessionExpandClient(),
            shareClient: shareClient ?? URLSessionShareClient(),
            eventsClient: eventsClient ?? URLSessionEventsClient(),
            store: keyValueStore ?? UserDefaultsKeyValueStore(),
            incomingLink: incomingLink ?? ContinuationsIncomingLink()
        )
        Self.store.configure(config)
    }

    /// Expand a short URL to an in-app path (`POST /v1/links/expand`).
    public static func resolveShortLink(_ url: String) async -> ExpandResult? {
        guard let config = store.config() else { return nil }
        let outcome = await config.expandClient.expand(
            ExpandRequest(
                apiBaseUrl: TaqlynAPI.origin,
                clientId: config.clientId,
                publicKeyId: config.publicKeyId,
                url: url,
                env: config.options.env
            )
        )
        switch outcome {
        case .ok(let result): return result
        case .notFound, .softFailure: return nil
        }
    }

    /// Map an incoming URL using hosts + short-code heuristic and resolveMode cascade.
    public static func resolveIncomingUrl(_ url: String) async -> ResolvedNavTarget? {
        guard let config = store.config() else { return pathMapOnly(url) }
        guard shouldExpand(url, hosts: config.options.hosts) else {
            return pathMapOnly(url)
        }
        let fallback = (config.options.fallbackPath?.isEmpty == false)
            ? (config.options.fallbackPath ?? "/")
            : "/"
        let clientMode = config.options.resolveMode ?? .awaitMode
        if clientMode == .optimistic {
            return ResolvedNavTarget(href: fallback, pendingExpand: true)
        }
        let timeoutMs = max(100, config.options.timeoutMs)
        let result = await withTimeout(ms: timeoutMs) {
            await resolveShortLink(url)
        }
        if let result {
            return ResolvedNavTarget(href: hrefFromExpand(result), linkId: result.linkId)
        }
        return ResolvedNavTarget(href: fallback)
    }

    /// Mint a unified short link for in-app sharing (public key id only).
    public static func createShareLink(
        destinationPath: String? = nil,
        destinationWeb: String? = nil,
        params: [String: String]? = nil,
        ogTitle: String? = nil,
        ogDescription: String? = nil,
        ogImage: String? = nil
    ) async throws -> ShareLink {
        guard let config = store.config() else {
            throw ShareLinkError.notConfigured
        }
        return try await config.shareClient.create(
            ShareLinkRequest(
                apiBaseUrl: TaqlynAPI.origin,
                clientId: config.clientId,
                publicKeyId: config.publicKeyId,
                destinationPath: destinationPath,
                destinationWeb: destinationWeb,
                params: params,
                env: config.options.env,
                ogTitle: ogTitle,
                ogDescription: ogDescription,
                ogImage: ogImage
            )
        )
    }

    /// Resolve deferred link once after install (App Clip → clipboard cascade).
    ///
    /// - Returns nil if already resolved locally, no token, no match, or soft-fail.
    /// - On success queues the link until `setReadyForNavigation(true)` for observers.
    /// - Soft-fails network errors (never throws to crash launch); does not set local flag.
    /// - Empty / denied pasteboard soft-skips without crashing; if cascade yields no token,
    ///   sets the resolved flag and returns nil (use `resolveClaim` for authenticated claim).
    @discardableResult
    public static func resolveDeferred() async -> DeferredLink? {
        guard let config = store.config() else { return nil }
        if config.options.linkProcessingMode == .webOnly { return nil }
        return await gate.run {
            await resolveDeferredBody(config: config)
        }
    }

    /// Authenticated claim resolve — same flag / ready-gate path as `resolveDeferred`,
    /// but sends only the `claim` field to `POST /v1/resolve`.
    @discardableResult
    public static func resolveClaim(_ token: String) async -> DeferredLink? {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let config = store.config() else { return nil }
        if config.options.linkProcessingMode == .webOnly { return nil }
        return await gate.run {
            await resolveWithField(
                config: config,
                clipboard: nil,
                claim: trimmed,
                appClip: nil
            )
        }
    }

    /// iOS-only custom listener (UL + clipboard / App Clip / claim). Prefer this in UIKit hosts.
    /// SwiftUI can keep using `observeLinks()` or this listener — both share the ready-gate.
    @discardableResult
    public static func addLinkListener(_ listener: TaqlynLinkListener) -> UUID {
        SdkCoreListeners.add(listener)
    }

    public static func removeLinkListener(_ id: UUID) {
        SdkCoreListeners.remove(id)
    }

    /// Stream of warm Universal Links and deferred links (deferred gated by ready flag).
    /// Warm links are **not** gated by ready (same as Android).
    public static func observeLinks() -> AsyncStream<DeferredLink> {
        AsyncStream { continuation in
            let id = store.registerDeferred(continuation)
            let config = store.config()
            let mode = config?.options.linkProcessingMode ?? .all

            if store.isReady(), mode != .webOnly, let pending = store.pending() {
                continuation.yield(pending)
            }

            let warmTask: Task<Void, Never>?
            if let config, mode != .deferredOnly {
                warmTask = Task {
                    for await url in config.incomingLink.observe() {
                        if Task.isCancelled { break }
                        continuation.yield(urlToDeferred(url))
                    }
                }
            } else {
                warmTask = nil
            }

            continuation.onTermination = { _ in
                warmTask?.cancel()
                store.unregisterDeferred(id)
            }
        }
    }

    /// Report that the SDK opened/consumed a link (fire-and-forget).
    public static func trackOpen(_ linkId: String) {
        guard let config = store.config() else { return }
        let id = linkId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return }
        Task {
            await config.eventsClient.trackOpen(
                OpenEventRequest(
                    apiBaseUrl: TaqlynAPI.origin,
                    clientId: config.clientId,
                    publicKeyId: config.publicKeyId,
                    linkId: id,
                    anonymousId: store.anonymousUserId(),
                    env: config.options.env
                )
            )
        }
    }

    /// Custom SDK analytics event (fire-and-forget).
    public static func logEvent(_ name: String, data: [String: String]? = nil) {
        guard let config = store.config() else { return }
        let eventName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !eventName.isEmpty else { return }
        Task {
            await config.eventsClient.logEvent(
                SdkEventRequest(
                    apiBaseUrl: TaqlynAPI.origin,
                    clientId: config.clientId,
                    publicKeyId: config.publicKeyId,
                    name: eventName,
                    data: data,
                    env: config.options.env
                )
            )
        }
    }

    /// Clear pending deferred link when `linkId` matches.
    public static func consume(_ linkId: String) {
        store.consume(linkId)
        trackOpen(linkId)
    }

    /// When true, deliver any pending deferred link to `observeLinks` once.
    public static func setReadyForNavigation(_ ready: Bool) {
        store.setReady(ready)
    }

    /// Forward Universal Link / custom URL into the IncomingLink adapter.
    public static func onOpenURL(_ url: URL) {
        store.config()?.incomingLink.onOpenURL(url)
    }

    // MARK: - Test hooks

    public static func resetForTests() {
        SdkCoreListeners.reset()
        store.reset()
    }

    public static func pendingForTests() -> DeferredLink? {
        store.pending()
    }

    // MARK: - Private resolve

    private static func resolveDeferredBody(config: Config) async -> DeferredLink? {
        if config.store.getBoolean(SdkStoreKeys.deferredResolved, default: false) {
            return nil
        }

        let appClipToken = SoftSkip.read { config.appClip.readInvocation() }
        if let token = appClipToken, !token.isEmpty {
            return await resolveWithField(
                config: config,
                clipboard: nil,
                claim: nil,
                appClip: token,
                skipResolvedFlagCheck: true
            )
        }

        let pasteToken = SoftSkip.read { config.pasteboard.readToken() }
        if let token = pasteToken, !token.isEmpty {
            return await resolveWithField(
                config: config,
                clipboard: token,
                claim: nil,
                appClip: nil,
                skipResolvedFlagCheck: true
            )
        }

        config.store.putBoolean(SdkStoreKeys.deferredResolved, true)
        return nil
    }

    private static func resolveWithField(
        config: Config,
        clipboard: String?,
        claim: String?,
        appClip: String?,
        skipResolvedFlagCheck: Bool = false
    ) async -> DeferredLink? {
        if !skipResolvedFlagCheck,
           config.store.getBoolean(SdkStoreKeys.deferredResolved, default: false) {
            return nil
        }

        let outcome = await config.resolveClient.resolve(
            ResolveRequest(
                apiBaseUrl: TaqlynAPI.origin,
                clientId: config.clientId,
                publicKeyId: config.publicKeyId,
                clipboard: clipboard,
                claim: claim,
                appClip: appClip,
                referrer: nil,
                env: config.options.env
            )
        )

        switch outcome {
        case .softFailure:
            return nil
        case .noMatch:
            config.store.putBoolean(SdkStoreKeys.deferredResolved, true)
            return nil
        case .matched(let link):
            config.store.putBoolean(SdkStoreKeys.deferredResolved, true)
            store.onMatched(link)
            return link
        }
    }

    private static func urlToDeferred(_ url: URL) -> DeferredLink {
        var params: [String: String] = [:]
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let items = components.queryItems {
            for item in items {
                if let value = item.value {
                    params[item.name] = value
                }
            }
        }
        let linkId = params["linkId"] ?? params["link_id"] ?? url.absoluteString
        return DeferredLink(
            url: url.absoluteString,
            path: url.path.isEmpty ? "/" : url.path,
            params: params,
            linkId: linkId,
            matchType: .none,
            isDeferred: false,
            campaign: nil
        )
    }
}

// MARK: - Supporting types

private struct Config: @unchecked Sendable {
    let clientId: String
    let publicKeyId: String
    let options: SdkOptions
    let pasteboard: PasteboardClient
    let appClip: AppClipBridge
    let resolveClient: ResolveClient
    let expandClient: ExpandClient
    let shareClient: ShareClient
    let eventsClient: EventsClient
    let store: KeyValueStore
    let incomingLink: IncomingLink
}

private func shouldExpand(_ url: String, hosts: [String]) -> Bool {
    guard let components = URLComponents(string: url), let host = components.host?.lowercased() else {
        return false
    }
    let hostOk: Bool
    if hosts.isEmpty {
        hostOk = true
    } else {
        hostOk = hosts.contains { prefix in
            var p = prefix.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            p = p.replacingOccurrences(of: "https://", with: "")
            p = p.replacingOccurrences(of: "http://", with: "")
            while p.hasSuffix("/") { p.removeLast() }
            return host == p || host.hasSuffix(".\(p)") || url.hasPrefix(prefix)
        }
    }
    guard hostOk else { return false }
    let path = (components.path as NSString).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    guard !path.isEmpty, !path.contains("/") else { return false }
    return path.range(of: #"^[A-Za-z0-9_-]{4,32}$"#, options: .regularExpression) != nil
}

private func pathMapOnly(_ url: String) -> ResolvedNavTarget? {
    guard let components = URLComponents(string: url) else { return nil }
    var path = components.path
    if path.isEmpty { path = "/" }
    if let query = components.percentEncodedQuery, !query.isEmpty {
        return ResolvedNavTarget(href: "\(path)?\(query)")
    }
    return ResolvedNavTarget(href: path)
}

private func hrefFromExpand(_ result: ExpandResult) -> String {
    var path = result.destinationPath
    if !path.hasPrefix("/") { path = "/\(path)" }
    if result.params.isEmpty { return path }
    let qs = result.params
        .map { key, value in
            let k = key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? key
            let v = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
            return "\(k)=\(v)"
        }
        .joined(separator: "&")
    return "\(path)?\(qs)"
}

private func withTimeout<T: Sendable>(ms: Int, body: @escaping @Sendable () async -> T?) async -> T? {
    await withTaskGroup(of: T?.self) { group in
        group.addTask { await body() }
        group.addTask {
            try? await Task.sleep(nanoseconds: UInt64(ms) * 1_000_000)
            return nil
        }
        let first = await group.next() ?? nil
        group.cancelAll()
        return first ?? nil
    }
}

private actor ResolveGate {
    func run<T: Sendable>(_ body: @Sendable () async -> T) async -> T {
        await body()
    }
}

/// Thread-safe SdkCore mutable state (`@unchecked Sendable` + NSLock).
private final class LockedStore: @unchecked Sendable {
    private let lock = NSLock()
    private var configured: Config?
    private var readyForNavigation = false
    private var pendingDeferred: DeferredLink?
    private var deferredReplay: DeferredLink?
    private var deferredContinuations: [UUID: AsyncStream<DeferredLink>.Continuation] = [:]
    private var anonymousId: String?

    func anonymousUserId() -> String {
        lock.lock()
        defer { lock.unlock() }
        if let anonymousId, !anonymousId.isEmpty {
            return anonymousId
        }
        let id = UUID().uuidString
        anonymousId = id
        return id
    }

    func configure(_ config: Config) {
        lock.lock()
        configured = config
        readyForNavigation = false
        pendingDeferred = nil
        deferredReplay = nil
        lock.unlock()
    }

    func reset() {
        lock.lock()
        configured = nil
        readyForNavigation = false
        pendingDeferred = nil
        deferredReplay = nil
        deferredContinuations.removeAll()
        lock.unlock()
    }

    func config() -> Config? {
        lock.lock()
        defer { lock.unlock() }
        return configured
    }

    func pending() -> DeferredLink? {
        lock.lock()
        defer { lock.unlock() }
        return pendingDeferred
    }

    func isReady() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return readyForNavigation
    }

    func consume(_ linkId: String) {
        lock.lock()
        if let pending = pendingDeferred, pending.linkId == linkId {
            pendingDeferred = nil
            if deferredReplay?.linkId == linkId {
                deferredReplay = nil
            }
        }
        lock.unlock()
    }

    func setReady(_ ready: Bool) {
        lock.lock()
        readyForNavigation = ready
        guard ready, let pending = pendingDeferred else {
            lock.unlock()
            return
        }
        deferredReplay = pending
        let targets = Array(deferredContinuations.values)
        lock.unlock()
        for continuation in targets {
            continuation.yield(pending)
        }
    }

    func registerDeferred(_ continuation: AsyncStream<DeferredLink>.Continuation) -> UUID {
        lock.lock()
        let id = UUID()
        deferredContinuations[id] = continuation
        lock.unlock()
        return id
    }

    func unregisterDeferred(_ id: UUID) {
        lock.lock()
        deferredContinuations.removeValue(forKey: id)
        lock.unlock()
    }

    func onMatched(_ link: DeferredLink) {
        lock.lock()
        pendingDeferred = link
        let ready = readyForNavigation
        if ready {
            deferredReplay = link
        }
        let targets = ready ? Array(deferredContinuations.values) : []
        lock.unlock()
        if ready {
            for continuation in targets {
                continuation.yield(link)
            }
        }
    }
}
