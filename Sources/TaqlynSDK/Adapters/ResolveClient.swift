import Foundation

/// HTTP client for Match.resolve — hides URLSession from feature code.
public protocol ResolveClient: AnyObject {
    /// POST /v1/resolve.
    /// Soft-failures (network / 5xx) return `.softFailure` so the local
    /// resolved-once flag is left unset for retry.
    func resolve(_ request: ResolveRequest) async -> ResolveOutcome
}

public struct ResolveRequest: Sendable, Equatable {
    public var apiBaseUrl: String
    public var clientId: String
    public var publicKeyId: String
    public var clipboard: String?
    public var claim: String?
    public var appClip: String?
    public var referrer: String?
    public var env: String?

    public init(
        apiBaseUrl: String,
        clientId: String,
        publicKeyId: String,
        clipboard: String? = nil,
        claim: String? = nil,
        appClip: String? = nil,
        referrer: String? = nil,
        env: String? = nil
    ) {
        self.apiBaseUrl = apiBaseUrl
        self.clientId = clientId
        self.publicKeyId = publicKeyId
        self.clipboard = clipboard
        self.claim = claim
        self.appClip = appClip
        self.referrer = referrer
        self.env = env
    }
}

public enum ResolveOutcome: Sendable, Equatable {
    case matched(DeferredLink)
    /// Completed call with no deferred payload (`deferredLink: null`).
    case noMatch
    /// Transient failure — caller should not set resolved-once.
    case softFailure
}

/// Production ResolveClient using URLSession.
public final class URLSessionResolveClient: ResolveClient, @unchecked Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func resolve(_ request: ResolveRequest) async -> ResolveOutcome {
        do {
            let base = request.apiBaseUrl.hasSuffix("/")
                ? String(request.apiBaseUrl.dropLast())
                : request.apiBaseUrl
            guard let url = URL(string: "\(base)/v1/resolve") else {
                return .softFailure
            }

            var body: [String: Any] = [
                "clientId": request.clientId,
                "publicKeyId": request.publicKeyId,
            ]
            if let clipboard = request.clipboard, !clipboard.isEmpty {
                body["clipboard"] = clipboard
            }
            if let claim = request.claim, !claim.isEmpty {
                body["claim"] = claim
            }
            if let appClip = request.appClip, !appClip.isEmpty {
                body["appClip"] = appClip
            }
            if let referrer = request.referrer, !referrer.isEmpty {
                body["referrer"] = referrer
            }
            if let env = request.env, !env.isEmpty {
                body["env"] = env
            }

            let data = try JSONSerialization.data(withJSONObject: body)
            var urlRequest = URLRequest(url: url)
            urlRequest.httpMethod = "POST"
            urlRequest.timeoutInterval = 15
            urlRequest.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
            urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
            urlRequest.httpBody = data

            let (responseData, response) = try await session.data(for: urlRequest)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0

            switch status {
            case 200 ... 299:
                if responseData.isEmpty {
                    return .noMatch
                }
                guard let root = try JSONSerialization.jsonObject(with: responseData) as? [String: Any] else {
                    return .softFailure
                }
                // API shape: { "deferredLink": { ... } | null }
                if root.keys.contains("deferredLink") {
                    if root["deferredLink"] is NSNull || root["deferredLink"] == nil {
                        return .noMatch
                    }
                    guard let nested = root["deferredLink"] as? [String: Any] else {
                        return .noMatch
                    }
                    if let link = Self.parseDeferredLink(nested) {
                        return .matched(link)
                    }
                    return .noMatch
                }
                // Fallback: top-level DeferredLink (legacy / unwrapped).
                if let link = Self.parseDeferredLink(root) {
                    return .matched(link)
                }
                return .noMatch
            case 204, 404, 410:
                return .noMatch
            default:
                return .softFailure
            }
        } catch {
            return .softFailure
        }
    }

    public static func parseDeferredLink(_ json: [String: Any]) -> DeferredLink? {
        guard let linkId = json["linkId"] as? String, !linkId.isEmpty else {
            return nil
        }
        let url = json["url"] as? String ?? ""
        let path = json["path"] as? String ?? ""
        var params: [String: String] = [:]
        if let paramsObj = json["params"] as? [String: Any] {
            for (k, v) in paramsObj {
                params[k] = String(describing: v)
            }
        }
        var campaign: Campaign?
        if let campaignObj = json["campaign"] as? [String: Any] {
            var map: [String: String] = [:]
            for (k, v) in campaignObj {
                if v is NSNull { continue }
                map[k] = String(describing: v)
            }
            campaign = Campaign(map)
        }
        let matchRaw = json["matchType"] as? String
        let isDeferred = (json["isDeferred"] as? Bool) ?? true
        return DeferredLink(
            url: url,
            path: path,
            params: params,
            linkId: linkId,
            matchType: MatchType.fromWire(matchRaw),
            isDeferred: isDeferred,
            campaign: campaign
        )
    }
}

/// Closure-backed client for tests.
public final class ClosureResolveClient: ResolveClient, @unchecked Sendable {
    private let handler: (ResolveRequest) async -> ResolveOutcome

    public init(_ handler: @escaping (ResolveRequest) async -> ResolveOutcome) {
        self.handler = handler
    }

    public func resolve(_ request: ResolveRequest) async -> ResolveOutcome {
        await handler(request)
    }
}
