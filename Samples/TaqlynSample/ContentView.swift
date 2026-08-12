import SwiftUI
import TaqlynSDK
import TaqlynNavSwiftUI

enum SampleRoute: Hashable {
    case home
    case product(String)
    case path(String)
}

/// Feature proof harness — imports `TaqlynSDK` + `TaqlynNavSwiftUI` only (never OS clipboard kits).
struct ContentView: View {
    @State private var path: [SampleRoute] = []
    @State private var status = "Starting…"
    @State private var lastPath = "—"

    private let navigator = DeepLinkNavigator<SampleRoute> { link in
        if link.path.hasPrefix("/product/") {
            let id = String(link.path.dropFirst("/product/".count))
            guard !id.isEmpty else { return nil }
            return [.product(id)]
        }
        if link.path == "/" || link.path == "/home" {
            return [.home]
        }
        return [.path(link.path)]
    }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Taqlyn Sample")
                    .font(.title2.bold())
                Text(status)
                    .font(.body)
                Text("Last path: \(lastPath)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text("Stack: \(pathDescription)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding()
            .navigationDestination(for: SampleRoute.self) { route in
                switch route {
                case .home:
                    Text("Home")
                case .product(let id):
                    Text("Product \(id)")
                        .font(.title)
                case .path(let value):
                    Text(value)
                        .font(.title3)
                }
            }
        }
        .task {
            // Observe warm + deferred deliveries → map → navigate (rebuild) → consume.
            Task { @MainActor in
                for await link in SdkCore.observeLinks() {
                    lastPath = link.path
                    let navLink = Self.toNavLink(link)
                    let navigated = navigator.navigate(navLink, path: &path)
                    status = """
                    Delivered link:
                      path=\(link.path)
                      linkId=\(link.linkId)
                      deferred=\(link.isDeferred)
                      matchType=\(link.matchType.rawValue)
                      navigated=\(navigated)
                    """
                    // Clear SdkCore pending; navigator also dedupes by linkId (double-nav blocked).
                    SdkCore.consume(link.linkId)
                }
            }

            // Short splash delay, then resolve + ready gate (mirrors Android sample).
            status = "Splash…"
            try? await Task.sleep(nanoseconds: 300_000_000)
            status = "Resolving deferred…"
            let deferred = await SdkCore.resolveDeferred()
            if let deferred {
                status = "Deferred pending (not ready): \(deferred.path) id=\(deferred.linkId)"
            } else {
                status = "No deferred link (empty clipboard / already resolved / soft-fail)"
            }
            SdkCore.setReadyForNavigation(true)
        }
    }

    private var pathDescription: String {
        if path.isEmpty { return "(root)" }
        return path.map { route in
            switch route {
            case .home: return "home"
            case .product(let id): return "product(\(id))"
            case .path(let value): return value
            }
        }.joined(separator: " → ")
    }

    /// Copy TaqlynSDK.DeferredLink fields into TaqlynNavSwiftUI.DeferredLink at the app boundary.
    private static func toNavLink(_ link: TaqlynSDK.DeferredLink) -> TaqlynNavSwiftUI.DeferredLink {
        TaqlynNavSwiftUI.DeferredLink(
            url: link.url,
            path: link.path,
            params: link.params,
            linkId: link.linkId,
            matchType: TaqlynNavSwiftUI.MatchType(rawValue: link.matchType.rawValue) ?? .none,
            isDeferred: link.isDeferred,
            campaign: link.campaign.map { TaqlynNavSwiftUI.Campaign($0.values) }
        )
    }
}

#if DEBUG
#Preview {
    ContentView()
}
#endif
