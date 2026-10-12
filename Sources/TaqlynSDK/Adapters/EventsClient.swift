import Foundation

public struct OpenEventRequest: Sendable {
    public var apiBaseUrl: String
    public var clientId: String
    public var publicKeyId: String
    public var linkId: String
    public var anonymousId: String
    public var env: String?

    public init(
        apiBaseUrl: String,
        clientId: String,
        publicKeyId: String,
        linkId: String,
        anonymousId: String,
        env: String? = nil
    ) {
        self.apiBaseUrl = apiBaseUrl
        self.clientId = clientId
        self.publicKeyId = publicKeyId
        self.linkId = linkId
        self.anonymousId = anonymousId
        self.env = env
    }
}

public struct SdkEventRequest: Sendable {
    public var apiBaseUrl: String
    public var clientId: String
    public var publicKeyId: String
    public var name: String
    public var data: [String: String]?
    public var env: String?

    public init(
        apiBaseUrl: String,
        clientId: String,
        publicKeyId: String,
        name: String,
        data: [String: String]? = nil,
        env: String? = nil
    ) {
        self.apiBaseUrl = apiBaseUrl
        self.clientId = clientId
        self.publicKeyId = publicKeyId
        self.name = name
        self.data = data
        self.env = env
    }
}

public protocol EventsClient: AnyObject {
    func trackOpen(_ request: OpenEventRequest) async
    func logEvent(_ request: SdkEventRequest) async
}

public final class URLSessionEventsClient: EventsClient, @unchecked Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func trackOpen(_ request: OpenEventRequest) async {
        var body: [String: Any] = [
            "clientId": request.clientId,
            "publicKeyId": request.publicKeyId,
            "linkId": request.linkId,
            "anonymousId": request.anonymousId,
        ]
        if let env = request.env, !env.isEmpty {
            body["env"] = env
        }
        await post(path: "/v1/events/open", request: request, body: body)
    }

    public func logEvent(_ request: SdkEventRequest) async {
        var body: [String: Any] = [
            "clientId": request.clientId,
            "publicKeyId": request.publicKeyId,
            "name": request.name,
        ]
        if let data = request.data, !data.isEmpty {
            body["data"] = data
        }
        if let env = request.env, !env.isEmpty {
            body["env"] = env
        }
        await post(path: "/v1/events/sdk", request: request, body: body)
    }

    private func post(path: String, request: OpenEventRequest, body: [String: Any]) async {
        let base = request.apiBaseUrl.hasSuffix("/")
            ? String(request.apiBaseUrl.dropLast())
            : request.apiBaseUrl
        guard let endpoint = URL(string: "\(base)\(path)") else { return }
        do {
            let data = try JSONSerialization.data(withJSONObject: body)
            var urlRequest = URLRequest(url: endpoint)
            urlRequest.httpMethod = "POST"
            urlRequest.timeoutInterval = 15
            urlRequest.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
            urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
            urlRequest.setValue(request.clientId, forHTTPHeaderField: "X-Taqlyn-Client-Id")
            urlRequest.setValue(request.publicKeyId, forHTTPHeaderField: "X-Taqlyn-Public-Key-Id")
            urlRequest.httpBody = data
            _ = try await session.data(for: urlRequest)
        } catch {
            /* fire-and-forget */
        }
    }

    private func post(path: String, request: SdkEventRequest, body: [String: Any]) async {
        let base = request.apiBaseUrl.hasSuffix("/")
            ? String(request.apiBaseUrl.dropLast())
            : request.apiBaseUrl
        guard let endpoint = URL(string: "\(base)\(path)") else { return }
        do {
            let data = try JSONSerialization.data(withJSONObject: body)
            var urlRequest = URLRequest(url: endpoint)
            urlRequest.httpMethod = "POST"
            urlRequest.timeoutInterval = 15
            urlRequest.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
            urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
            urlRequest.setValue(request.clientId, forHTTPHeaderField: "X-Taqlyn-Client-Id")
            urlRequest.setValue(request.publicKeyId, forHTTPHeaderField: "X-Taqlyn-Public-Key-Id")
            urlRequest.httpBody = data
            _ = try await session.data(for: urlRequest)
        } catch {
            /* fire-and-forget */
        }
    }
}
