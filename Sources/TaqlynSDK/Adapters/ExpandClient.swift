import Foundation

public struct ExpandRequest: Sendable {
    public var apiBaseUrl: String
    public var clientId: String
    public var publicKeyId: String
    public var url: String
    public var env: String?

    public init(
        apiBaseUrl: String,
        clientId: String,
        publicKeyId: String,
        url: String,
        env: String? = nil
    ) {
        self.apiBaseUrl = apiBaseUrl
        self.clientId = clientId
        self.publicKeyId = publicKeyId
        self.url = url
        self.env = env
    }
}

public enum ExpandOutcome: Sendable {
    case ok(ExpandResult)
    case notFound
    case softFailure
}

public protocol ExpandClient: AnyObject {
    func expand(_ request: ExpandRequest) async -> ExpandOutcome
}

public final class URLSessionExpandClient: ExpandClient, @unchecked Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func expand(_ request: ExpandRequest) async -> ExpandOutcome {
        do {
            let base = request.apiBaseUrl.hasSuffix("/")
                ? String(request.apiBaseUrl.dropLast())
                : request.apiBaseUrl
            guard let endpoint = URL(string: "\(base)/v1/links/expand") else {
                return .softFailure
            }
            var body: [String: Any] = [
                "clientId": request.clientId,
                "publicKeyId": request.publicKeyId,
                "url": request.url,
            ]
            if let env = request.env, !env.isEmpty {
                body["env"] = env
            }
            let data = try JSONSerialization.data(withJSONObject: body)
            var urlRequest = URLRequest(url: endpoint)
            urlRequest.httpMethod = "POST"
            urlRequest.timeoutInterval = 15
            urlRequest.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
            urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
            urlRequest.httpBody = data

            let (responseData, response) = try await session.data(for: urlRequest)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            switch status {
            case 200 ... 299:
                guard let root = try JSONSerialization.jsonObject(with: responseData) as? [String: Any],
                      let parsed = Self.parse(root)
                else { return .notFound }
                return .ok(parsed)
            case 404:
                return .notFound
            default:
                return .softFailure
            }
        } catch {
            return .softFailure
        }
    }

    static func parse(_ json: [String: Any]) -> ExpandResult? {
        guard let linkId = json["linkId"] as? String, !linkId.isEmpty else { return nil }
        var params: [String: String] = [:]
        if let raw = json["params"] as? [String: Any] {
            for (k, v) in raw {
                params[k] = String(describing: v)
            }
        }
        return ExpandResult(
            linkId: linkId,
            code: json["code"] as? String ?? "",
            host: json["host"] as? String ?? "",
            destinationPath: json["destinationPath"] as? String ?? "/",
            params: params,
            url: json["url"] as? String ?? "",
            linkResolveMode: ResolveMode.fromWire(json["linkResolveMode"] as? String),
            appResolveMode: ResolveMode.fromWire(json["appResolveMode"] as? String),
            appExpandTimeoutMs: json["appExpandTimeoutMs"] as? Int
        )
    }
}

public final class ClosureExpandClient: ExpandClient, @unchecked Sendable {
    private let handler: (ExpandRequest) async -> ExpandOutcome

    public init(_ handler: @escaping (ExpandRequest) async -> ExpandOutcome) {
        self.handler = handler
    }

    public func expand(_ request: ExpandRequest) async -> ExpandOutcome {
        await handler(request)
    }
}
