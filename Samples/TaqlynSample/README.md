# Taqlyn Sample (SwiftUI)

Proof harness for `packages/sdk-ios`. Imports **TaqlynSDK / SdkCore only** — never OS clipboard or URLSession types directly.

## Associated Domains

Add an Associated Domains entitlement to the host app:

```
applinks:your-go-host.example.com
```

Host a valid AASA at `https://your-go-host.example.com/.well-known/apple-app-site-association`. Forward opens with:

```swift
.onOpenURL { SdkCore.onOpenURL($0) }
```

## Run notes

This folder is a lightweight source sketch. Wire it into an Xcode app target that depends on the local `TaqlynSDK` Swift package, or open `Package.swift` and add a sample executable target later.

Environment overrides (optional):

- `TAQLYN_CLIENT_ID`
- `TAQLYN_PUBLIC_KEY_ID`
- `TAQLYN_API_BASE_URL`
