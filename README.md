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
| `Tests/TaqlynSDKNavIntegrationTests/` | Map → navigate → double-nav integration (enabled only when `../nav-swiftui` exists in the platform monorepo) |

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

`SdkOptions` accepts optional `linkProcessingMode` (`.all` | `.webOnly` | `.deferredOnly`) and `env`. The control-plane origin is `https://api.taqlyn.com`.

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
pod install --repo-update
```

Open the generated `.xcworkspace` in Xcode (never open the `.xcodeproj` directly).

## Usage

```swift
@main
struct MyApp: App {
  init() {
    SdkCore.configure(
      clientId: "app_test_…",
      publicKeyId: "pk_test_…",
      options: SdkOptions()
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

## CI/CD & SPM Distribution

Published via `.github/workflows/publish.yml`:
- **Swift Package Manager (SPM):** Xcode and `swift package` resolve directly from Git release tags (`v*`). **Zero secrets required.**
- **CocoaPods Trunk (Optional):** Automatically validates podspec and pushes to CocoaPods Trunk when `COCOAPODS_TRUNK_TOKEN` is present in GitHub Secrets.

## CocoaPods Publishing & Trunk Submission Guide

`TaqlynSDK` is officially published to CocoaPods Trunk ([cocoapods.org/pods/TaqlynSDK](https://cocoapods.org/pods/TaqlynSDK)) using `TaqlynSDK.podspec`.

### 1. Specification & Privacy Manifest
- **Platform:** `iOS 16.0+`, Swift `5.9+`.
- **Git tag matching:** The podspec sets `:git => 'https://github.com/taqlyn/sdk-ios.git', :tag => "v#{s.version}"`. Release tags in Git MUST have the `v` prefix matching `s.version` (e.g. `v0.1.0`).
- **Apple Privacy Manifest:** Bundled via `s.resource_bundles = { 'TaqlynSDK_Privacy' => ['Sources/TaqlynSDK/PrivacyInfo.xcprivacy'] }` to ensure CocoaPods compiles `PrivacyInfo.xcprivacy` for Apple Required Reason API compliance (`UserDefaults` CA92.1).

### 2. Pre-Submission Linting & Validation
Run linting from `packages/sdk-ios`:

```bash
# Fast JSON AST validation (checks syntax without Xcode build)
pod ipc spec TaqlynSDK.podspec > /dev/null

# Local workspace validation (validates against local files)
pod lib lint TaqlynSDK.podspec --allow-warnings

# Remote tag validation (validates that Git tag exists on GitHub and builds in a sandbox)
pod spec lint TaqlynSDK.podspec --allow-warnings
```

### 3. Git Release Tagging
Ensure changes are committed and pushed with the semantic version tag before submitting:

```bash
git tag v0.1.0
git push origin v0.1.0
```

### 4. CocoaPods Trunk Account Registration
CocoaPods uses passwordless email session authentication:

```bash
# Register maintainer email on Trunk (first-time only)
pod trunk register dev@taqlyn.com "Taqlyn Platform Team" --description="Taqlyn Release Machine"

# Verify the confirmation link sent to your inbox, then confirm session:
pod trunk me
```

### 5. Publishing to CocoaPods Trunk
Once `pod spec lint` passes and the tag is live on GitHub:

```bash
pod trunk push TaqlynSDK.podspec --allow-warnings
```

### 6. Automated CI/CD Publishing
This repository automates CocoaPods publishing via `.github/workflows/publish.yml`:
1. Retrieve your trunk token:
   ```bash
   pod trunk print-token
   ```
2. In GitHub, add repository secret `COCOAPODS_TRUNK_TOKEN`.
3. Whenever a release tag (`v*`) is pushed, GitHub Actions runs `swift test`, validates the privacy manifest, and runs `pod trunk push TaqlynSDK.podspec --allow-warnings`.

### 7. Managing Owners & Collaborators
To grant other maintainers or CI bots push access:

```bash
# Add collaborator
pod trunk add-owner TaqlynSDK teammate@taqlyn.com

# List current pod owners and metrics
pod trunk info TaqlynSDK
```

### 8. Troubleshooting & Common Pitfalls
- **`[!] The tag does not exist`:** The Git release tag (`v0.1.0`) was not pushed to GitHub or was pushed under a different naming convention. Push `git push origin v0.1.0`.
- **`[!] Missing Privacy Manifest`:** Ensure `Sources/TaqlynSDK/PrivacyInfo.xcprivacy` is present and declared under `s.resource_bundles`.
- **`[!] Pod not found immediately after push`:** CocoaPods uses a CDN. It can take 5–15 minutes to propagate. Run `pod install --repo-update`.

## Branch

Develop on `integrate/phase-05-ios-sdk` (not `main`).
