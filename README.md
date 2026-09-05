# Taqlyn iOS SDK (`sdk-ios`)

**Full guide:** [iOS cookbook](../../apps/docs/content/platforms/ios.md) on the docs site.

Swift SdkCore + thin adapters for Universal Links, pasteboard, resolve HTTP, and local prefs.

**Branch:** `integrate/phase-05-ios-sdk` (not `main`).

## Modules

| Path | Role |
|------|------|
| `Sources/TaqlynSDK/` | Swift package library — public `SdkCore` + adapters |
| `Samples/TaqlynSample/` | SwiftUI proof harness (imports **TaqlynSDK + TaqlynNavSwiftUI**) |
| `Tests/TaqlynSDKTests/` | Unit + sample source-guard tests |
| `Tests/TaqlynSDKNavIntegrationTests/` | Map → navigate → double-nav integration (depends on `../nav-swiftui`) |

## Public API

```swift
SdkCore.configure(clientId, publicKeyId, options, …)
SdkCore.createShareLink(destinationPath:)  // ShareLink — in-app sharing
SdkCore.resolveDeferred()           // DeferredLink?
SdkCore.resolveClaim(_ token)       // DeferredLink? — authenticated claim path
SdkCore.addLinkListener(_:)         // iOS-only TaqlynLinkListener (UL + clipboard)
SdkCore.observeLinks()              // AsyncStream<DeferredLink>
SdkCore.consume(linkId)
SdkCore.setReadyForNavigation(ready)
SdkCore.onOpenURL(url)              // forward Universal Links / custom URLs
```

`SdkOptions.apiBaseUrl` defaults to `SdkOptions.defaultAPIBaseURL` (`https://api.taqlyn.com`); pass it only to self-host. Optional `linkProcessingMode` (`.all` | `.webOnly` | `.deferredOnly`) and `env`.

`DeferredLink` mirrors `packages/sdk-contract`: `url`, `path`, `params`, `linkId`, `matchType`, `isDeferred`, `campaign`.

## Wrappers (feature code must not import vendors)

| Adapter | Interface | Hides |
|---------|-----------|--------|
| `Adapters/IncomingLink.swift` | `IncomingLink.observe()` / `onOpenURL` | Universal Links / `onOpenURL` |
| `Adapters/Pasteboard.swift` | `PasteboardClient.readToken()` | `UIPasteboard` |
| `Adapters/AppClipBridge.swift` | `AppClipBridge.readInvocation()` | App Clip / App Group (stub) |
| `Adapters/ResolveClient.swift` | `ResolveClient.resolve()` | `URLSession` `POST /v1/resolve` |
| `Adapters/KeyValueStore.swift` | `KeyValueStore` | `UserDefaults` |

Sample / app feature modules import `TaqlynSDK` (`SdkCore`) and optionally `TaqlynNavSwiftUI` — never OS clipboard kits.

## Installation

### Swift Package Manager (Recommended)

In Xcode: **File → Add Package Dependencies...**, enter `https://github.com/taqlyn/sdk-ios.git`, and select `TaqlynSDK`.

Or add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/taqlyn/sdk-ios.git", from: "0.1.0"),
]
```

### CocoaPods

Add `TaqlynSDK` to your `Podfile` (`iOS 16.0+` with `use_frameworks!`):

```ruby
platform :ios, '16.0'
use_frameworks!

target 'MyApp' do
  pod 'TaqlynSDK', '~> 0.1.0'
  # Optional SwiftUI navigation helper:
  # pod 'TaqlynNavSwiftUI', '~> 0.1.0'
end
```

Then run:

```bash
pod install
```

Open the generated `.xcworkspace` in Xcode.

## Usage

```swift
@main
struct MyApp: App {
  init() {
    SdkCore.configure(
      clientId: "app_test_…",
      publicKeyId: "pk_test_…",
      options: SdkOptions() // or apiBaseUrl: "https://api.self-host.example"
    )
  }

  var body: some Scene {
    WindowGroup {
      RootView()
        .onOpenURL { SdkCore.onOpenURL($0) }
        .task {
          // After splash / auth:
          _ = await SdkCore.resolveDeferred()
          SdkCore.setReadyForNavigation(true)
        }
    }
  }
}

// Navigate once (with TaqlynNavSwiftUI DeepLinkNavigator):
Task {
  for await link in SdkCore.observeLinks() {
    let navLink = TaqlynNavSwiftUI.DeferredLink(
      url: link.url,
      path: link.path,
      params: link.params,
      linkId: link.linkId,
      matchType: TaqlynNavSwiftUI.MatchType(rawValue: link.matchType.rawValue) ?? .none,
      isDeferred: link.isDeferred,
      campaign: link.campaign.map { TaqlynNavSwiftUI.Campaign($0.values) }
    )
    _ = navigator.navigate(navLink, path: &path) // rebuilds NavigationStack path
    SdkCore.consume(link.linkId)
  }
}
```

### Deferred cascade (iOS)

`resolveDeferred()` tries, soft-skipping each step on deny/empty/error (never crashes):

1. **App Clip** invocation (`AppClipBridge.readInvocation`) — Phase 05 ships a stub returning `nil`
2. **Clipboard** token (`PasteboardClient.readToken`)
3. If neither yields a token → set local resolved-once flag and return `nil`

Authenticated claim is **not** auto-called. After sign-in (or when product has a claim token), call:

```swift
_ = await SdkCore.resolveClaim(token)
```

Same resolved-once flag and ready-gate as `resolveDeferred`. Alternatively inject a `Pasteboard` fake that returns the claim token, or a custom `ResolveClient`.

### Resolve request body

```json
{
  "clientId": "…",
  "publicKeyId": "…",
  "clipboard": "…",
  "claim": "…",
  "appClip": "…",
  "env": "sandbox"
}
```

Only non-empty active fields are sent (empty `referrer` is omitted). Response is parsed as `{ "deferredLink": { … } | null }`.

## PrivacyInfo.xcprivacy

Shipped as a package resource (`Sources/TaqlynSDK/PrivacyInfo.xcprivacy`):

- `NSPrivacyTracking` = **false** (deferred routing is not ATT tracking)
- `NSPrivacyAccessedAPICategoryUserDefaults` reason **CA92.1** (resolved-once flag via `UserDefaults`)
- Pasteboard: `UIPasteboardPasteboard` may read clipboard for opt-in deferred tokens. Pasteboard is **not** a Required Reason API category today — document paste prompts in the host app’s privacy policy; declare honestly if Apple expands the catalog.
- **No fingerprinting as iOS primary** — cascade is App Clip → clipboard → claim → null (see monorepo `docs/guides/privacy.md`)
- No ATT / IDFA by default

See `docs/research/compliance/privacy-and-store-policy.md` and `docs/guides/privacy.md` in the monorepo.

## Unit tests

From this directory:

```bash
swift test
```

Coverage includes:

- resolve-once + local flag → second call `nil`
- soft failure does **not** set flag
- empty / denied pasteboard soft-skip → `nil` + flag (no crash)
- ready-gate holds pending until `setReadyForNavigation(true)`
- warm UL via `onOpenURL` delivers on `observeLinks`
- `resolveClaim` works
- sample sources do not reference `UIPasteboard` (may import TaqlynSDK + TaqlynNavSwiftUI)
- nav integration: map SdkCore `DeferredLink` → nav `DeferredLink`, navigate once, second same `linkId` blocked

## Real-device Universal Link / clipboard proof

**Simulators can exercise UL and pasteboard, but App Store first-open is best on a real device.**

1. Host AASA for your go-domain; enable Associated Domains (`applinks:…`) on the sample.
2. Open a Universal Link while the app is installed → confirm `observeLinks` delivers path/params (`isDeferred=false`).
3. For deferred: place a clipboard token (product opt-in), fresh-install / first launch, confirm `resolveDeferred()` once; second launch returns `nil`.
4. Deny paste when prompted → confirm soft-skip (no crash); use `resolveClaim` for authenticated recovery.
5. Confirm sample/feature code has zero `UIPasteboard` imports (`SampleSourceGuardTests`).

## Branch

Develop on `integrate/phase-05-ios-sdk` (not `main`).
