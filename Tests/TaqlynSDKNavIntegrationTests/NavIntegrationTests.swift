import Foundation
import TaqlynNavSwiftUI
import TaqlynSDK
import XCTest

private enum IntegrationRoute: Hashable {
    case product(String)
}

/// Compiles the map → navigate → consume pattern across TaqlynSDK + TaqlynNavSwiftUI.
///
/// Full resolve/ready-gate needs `SdkCore.configure`; this target proves the boundary
/// mapping and navigator double-nav semantics. After a real delivery, call
/// `SdkCore.consume(link.linkId)` (clears pending; navigator also dedupes by linkId).
final class NavIntegrationTests: XCTestCase {
    func testMapSdkDeferredLink_navigate_secondSameLinkIdBlocked() {
        let sdkLink = TaqlynSDK.DeferredLink(
            url: "https://go.example.test/product/123",
            path: "/product/123",
            params: ["sku": "123"],
            linkId: "lnk_nav_integration",
            matchType: .clipboard,
            isDeferred: true,
            campaign: TaqlynSDK.Campaign(["utm_source": "invite"])
        )

        let navLink = TaqlynNavSwiftUI.DeferredLink(
            url: sdkLink.url,
            path: sdkLink.path,
            params: sdkLink.params,
            linkId: sdkLink.linkId,
            matchType: TaqlynNavSwiftUI.MatchType(rawValue: sdkLink.matchType.rawValue) ?? .none,
            isDeferred: sdkLink.isDeferred,
            campaign: sdkLink.campaign.map { TaqlynNavSwiftUI.Campaign($0.values) }
        )

        XCTAssertEqual(navLink.linkId, sdkLink.linkId)
        XCTAssertEqual(navLink.path, sdkLink.path)
        XCTAssertEqual(navLink.matchType, .clipboard)
        XCTAssertEqual(navLink.campaign?.utmSource, "invite")

        let navigator = DeepLinkNavigator<IntegrationRoute> { link in
            guard link.path.hasPrefix("/product/") else { return nil }
            let id = String(link.path.dropFirst("/product/".count))
            guard !id.isEmpty else { return nil }
            return [.product(id)]
        }

        var path: [IntegrationRoute] = []
        XCTAssertTrue(navigator.navigate(navLink, path: &path))
        XCTAssertEqual(path, [.product("123")])

        // Same linkId after first navigate → blocked (mirrors post-consume re-observe).
        let before = path
        XCTAssertFalse(navigator.navigate(navLink, path: &path))
        XCTAssertEqual(path, before)

        // App-side after successful navigate: SdkCore.consume(sdkLink.linkId)
        // (requires configure; omitted here — consume clears pending; navigator dedupes linkId).
    }
}
