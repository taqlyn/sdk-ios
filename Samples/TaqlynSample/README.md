# Taqlyn Sample (SwiftUI)

Proof harness for `packages/sdk-ios`. Imports **TaqlynSDK + TaqlynNavSwiftUI** — never OS clipboard or URLSession types directly.

Uses `NavigationStack` + `DeepLinkNavigator`: on `SdkCore.observeLinks`, maps `TaqlynSDK.DeferredLink` → `TaqlynNavSwiftUI.DeferredLink`, navigates (path rebuild), then `SdkCore.consume`.

## Public demo API

The SDK talks to `https://api.taqlyn.com`. Seed credentials:

```bash
# repo root
make up-tunnel
eval "$(./scripts/demo-seed.sh | sed -n '/^export /p')"
```

Environment overrides:

| Variable | Meaning |
|----------|---------|
| `TAQLYN_CLIENT_ID` | Sandbox `app_test_*` |
| `TAQLYN_PUBLIC_KEY_ID` | `pk_test_*` |

## Associated Domains

Add an Associated Domains entitlement to the host app:

```
applinks:go.rutvik.qzz.io
```

Host a valid AASA at `https://go.rutvik.qzz.io/.well-known/apple-app-site-association`. Forward opens with:

```swift
.onOpenURL { SdkCore.onOpenURL($0) }
```

## Run notes

This folder is a lightweight source sketch. Wire it into an Xcode app target that depends on the local `TaqlynSDK` and `TaqlynNavSwiftUI` Swift packages (`File → Add Package Dependencies…` → Add Local → `packages/sdk-ios` and `packages/nav-swiftui`), copy `TaqlynSampleApp.swift` / `ContentView.swift` into the target, then set the scheme environment variables above.

Scheme → Run → Arguments → Environment Variables:

- `TAQLYN_CLIENT_ID` / `TAQLYN_PUBLIC_KEY_ID` from `demo-seed.sh`

See [docs/guides/public-demo.md](../../../../docs/guides/public-demo.md).
