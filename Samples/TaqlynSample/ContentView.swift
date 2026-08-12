import SwiftUI
import TaqlynSDK

/// Feature proof harness — imports `TaqlynSDK` / `SdkCore` only (never OS clipboard types).
struct ContentView: View {
    @State private var status = "Starting…"
    @State private var lastPath = "—"

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Taqlyn Sample")
                .font(.title2.bold())
            Text(status)
                .font(.body)
            Text("Last path: \(lastPath)")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding()
        .task {
            // Observe warm + deferred deliveries.
            Task {
                for await link in SdkCore.observeLinks() {
                    lastPath = link.path
                    status = """
                    Delivered link:
                      path=\(link.path)
                      linkId=\(link.linkId)
                      deferred=\(link.isDeferred)
                      matchType=\(link.matchType.rawValue)
                    """
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
}

#if DEBUG
#Preview {
    ContentView()
}
#endif
