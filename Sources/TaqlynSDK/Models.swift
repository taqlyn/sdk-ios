import Foundation

/// Canonical resolve payload — mirrors packages/sdk-contract DeferredLink.
public struct DeferredLink: Sendable, Equatable, Hashable {
    public var url: String
    public var path: String
    public var params: [String: String]
    public var linkId: String
    public var matchType: MatchType
    public var isDeferred: Bool
    public var campaign: Campaign?

    public init(
        url: String,
        path: String,
        params: [String: String] = [:],
        linkId: String,
        matchType: MatchType,
        isDeferred: Bool,
        campaign: Campaign? = nil
    ) {
        self.url = url
        self.path = path
        self.params = params
        self.linkId = linkId
        self.matchType = matchType
        self.isDeferred = isDeferred
        self.campaign = campaign
    }
}

/// How the deferred / warm link was matched.
public enum MatchType: String, Sendable, Equatable {
    case installReferrer = "install_referrer"
    case clipboard
    case appClip = "app_clip"
    case claim
    case none

    public static func fromWire(_ value: String?) -> MatchType {
        guard let value else { return .none }
        return MatchType(rawValue: value) ?? .none
    }

    public var wireValue: String { rawValue }
}

/// Optional UTM / campaign attribution.
public struct Campaign: Sendable, Equatable, Hashable {
    public var values: [String: String]

    public init(_ values: [String: String] = [:]) {
        self.values = values
    }

    public var utmSource: String? { values["utm_source"] }
    public var utmCampaign: String? { values["utm_campaign"] }
}

/// How SdkCore should process incoming / deferred links.
public enum LinkProcessingMode: Sendable, Equatable {
    case all
    case webOnly
    case deferredOnly
}

/// Hosted control-plane origin. Not overridable from app code.
enum TaqlynAPI {
    static let origin = "https://api.taqlyn.com"
}

/// Configure options for `SdkCore.configure`.
///
/// The control-plane origin is baked into the SDK (`https://api.taqlyn.com`).
public struct SdkOptions: Sendable {
    public var linkProcessingMode: LinkProcessingMode
    public var env: String?

    public init(
        linkProcessingMode: LinkProcessingMode = .all,
        env: String? = nil
    ) {
        self.linkProcessingMode = linkProcessingMode
        self.env = env
    }
}

/// Unified short link minted from the mobile SDK (public key id only).
public struct ShareLink: Sendable, Equatable {
    public var id: String
    public var code: String
    public var shortUrl: String
    public var host: String
    public var env: String

    public init(id: String, code: String, shortUrl: String, host: String, env: String) {
        self.id = id
        self.code = code
        self.shortUrl = shortUrl
        self.host = host
        self.env = env
    }
}

public enum ShareLinkError: Error, Sendable, Equatable {
    case notConfigured
    case invalidInput(String)
    case httpStatus(Int)
    case decode
}
