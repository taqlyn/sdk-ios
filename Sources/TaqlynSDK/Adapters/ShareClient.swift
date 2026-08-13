import Foundation

/// HTTP client for in-app share create — hides URLSession from feature code.
public protocol ShareClient: AnyObject {
    func create(_ request: ShareLinkRequest) async throws -> ShareLink
}

public struct ShareLinkRequest: Sendable, Equatable {
    public var apiBaseUrl: String
    public var clientId: String
    public var publicKeyId: String
    public var destinationPath: String?
    public var destinationWeb: String?
    public var params: [String: String]?
    public var env: String?
    public var ogTitle: String?
    public var ogDescription: String?
    public var ogImage: String?

    public init(
        apiBaseUrl: String,
        clientId: String,
        publicKeyId: String,
        destinationPath: String? = nil,
        destinationWeb: String? = nil,
        params: [String: String]? = nil,
        env: String? = nil,
        ogTitle: String? = nil,
        ogDescription: String? = nil,
        ogImage: String? = nil
    ) {
        self.apiBaseUrl = apiBaseUrl
        self.clientId = clientId
        self.publicKeyId = publicKeyId
        self.destinationPath = destinationPath
        self.destinationWeb = destinationWeb
        self.params = params
        self.env = env
        self.ogTitle = ogTitle
        self.ogDescription = ogDescription
        self.ogImage = ogImage
    }
}

/// Production ShareClient using URLSession.
public final class URLSessionShareClient: ShareClient, @unchecked Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func create(_ request: ShareLinkRequest) async throws -> ShareLink {
        let path = request.destinationPath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let web = request.destinationWeb?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if path.isEmpty && web.isEmpty {
            throw ShareLinkError.invalidInput("destinationPath or destinationWeb required")
        }

        let base = request.apiBaseUrl.hasSuffix("/")
            ? String(request.apiBaseUrl.dropLast())
            : request.apiBaseUrl
        guard let url = URL(string: "\(base)/v1/sdk/short-links") else {
            throw ShareLinkError.invalidInput("apiBaseUrl")
        }

        var body: [String: Any] = [
            "clientId": request.clientId,
            "publicKeyId": request.publicKeyId,
        ]
        if !path.isEmpty { body["destinationPath"] = path }
        if !web.isEmpty { body["destinationWeb"] = web }
        if let env = request.env, !env.isEmpty { body["env"] = env }
        if let ogTitle = request.ogTitle { body["ogTitle"] = ogTitle }
        if let ogDescription = request.ogDescription { body["ogDescription"] = ogDescription }
        if let ogImage = request.ogImage { body["ogImage"] = ogImage }
        if let params = request.params, !params.isEmpty { body["params"] = params }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = 15
        urlRequest.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        urlRequest.setValue(request.clientId, forHTTPHeaderField: "X-Taqlyn-Client-Id")
        urlRequest.setValue(request.publicKeyId, forHTTPHeaderField: "X-Taqlyn-Public-Key-Id")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: urlRequest)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200 ... 299).contains(status) else {
            throw ShareLinkError.httpStatus(status)
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ShareLinkError.decode
        }
        guard let id = json["id"] as? String, let code = json["code"] as? String else {
            throw ShareLinkError.decode
        }
        return ShareLink(
            id: id,
            code: code,
            shortUrl: json["shortUrl"] as? String ?? "",
            host: json["host"] as? String ?? "",
            env: json["env"] as? String ?? ""
        )
    }
}

/// Closure-backed client for tests.
public final class ClosureShareClient: ShareClient, @unchecked Sendable {
    private let handler: (ShareLinkRequest) async throws -> ShareLink

    public init(_ handler: @escaping (ShareLinkRequest) async throws -> ShareLink) {
        self.handler = handler
    }

    public func create(_ request: ShareLinkRequest) async throws -> ShareLink {
        try await handler(request)
    }
}
