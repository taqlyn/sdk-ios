import SwiftUI
import TaqlynSDK

/// Proof harness — configures SdkCore early. Feature UI may import TaqlynSDK + TaqlynNavSwiftUI (not OS kits).
@main
struct TaqlynSampleApp: App {
    init() {
        SdkCore.configure(
            clientId: ProcessInfo.processInfo.environment["TAQLYN_CLIENT_ID"] ?? "app_test_demo",
            publicKeyId: ProcessInfo.processInfo.environment["TAQLYN_PUBLIC_KEY_ID"] ?? "pk_test_demo",
            options: SdkOptions(
                linkProcessingMode: .all,
                env: "sandbox"
            )
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    SdkCore.onOpenURL(url)
                }
        }
    }
}
