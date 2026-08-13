import Foundation
@testable import TaqlynSDK
import XCTest

final class SdkCoreTests: XCTestCase {
    private var store: InMemoryKeyValueStore!
    private var incoming: ContinuationsIncomingLink!

    override func setUp() {
        super.setUp()
        store = InMemoryKeyValueStore()
        incoming = ContinuationsIncomingLink()
        SdkCore.resetForTests()
    }

    override func tearDown() {
        SdkCore.resetForTests()
        super.tearDown()
    }

    func testResolveDeferred_onceThenNull_setsLocalFlag() async {
        let link = sampleLink("lnk_1", matchType: .clipboard)
        configureWith(
            pasteboard: FixedPasteboard(token: "tok_1"),
            resolve: { _ in ResolveOutcome.matched(link) }
        )

        let first = await SdkCore.resolveDeferred()
        let second = await SdkCore.resolveDeferred()

        XCTAssertEqual(first, link)
        XCTAssertNil(second)
        XCTAssertTrue(store.getBoolean(SdkStoreKeys.deferredResolved, default: false))
    }

    func testResolveDeferred_softFailure_doesNotSetFlag() async {
        configureWith(
            pasteboard: FixedPasteboard(token: "tok_soft"),
            resolve: { _ in ResolveOutcome.softFailure }
        )

        let result = await SdkCore.resolveDeferred()
        XCTAssertNil(result)
        XCTAssertFalse(store.getBoolean(SdkStoreKeys.deferredResolved, default: false))
    }

    func testPasteboardEmpty_softSkip_setsFlagAndReturnsNull() async {
        configureWith(
            pasteboard: FixedPasteboard(token: nil),
            resolve: { _ in
                XCTFail("should not resolve when pasteboard empty")
                return ResolveOutcome.softFailure
            }
        )

        let result = await SdkCore.resolveDeferred()
        XCTAssertNil(result)
        XCTAssertTrue(store.getBoolean(SdkStoreKeys.deferredResolved, default: false))
    }

    func testReadyGate_holdsPendingUntilSetReadyForNavigation() async {
        let link = sampleLink("lnk_ready", matchType: .clipboard)
        configureWith(
            pasteboard: FixedPasteboard(token: "tok_ready"),
            resolve: { _ in ResolveOutcome.matched(link) }
        )

        let resolved = await SdkCore.resolveDeferred()
        XCTAssertEqual(resolved, link)
        XCTAssertEqual(SdkCore.pendingForTests(), link)

        let delivered = expectation(description: "deferred delivered")
        let box = DeliveryBox()
        let task = Task {
            for await item in SdkCore.observeLinks() {
                if item.linkId == "lnk_ready" {
                    box.mark()
                    delivered.fulfill()
                    break
                }
            }
        }

        // Allow collector to subscribe; should not deliver yet.
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertFalse(box.wasDelivered, "ready gate must hold pending until setReadyForNavigation")

        SdkCore.setReadyForNavigation(true)
        await fulfillment(of: [delivered], timeout: 2.0)
        task.cancel()

        SdkCore.consume("lnk_ready")
        XCTAssertNil(SdkCore.pendingForTests())
    }

    func testWarmUL_deliversViaObserveLinks() async {
        configureWith(
            pasteboard: FixedPasteboard(token: nil),
            resolve: { _ in
                XCTFail("warm path must not call resolve")
                return ResolveOutcome.softFailure
            }
        )

        let expectation = expectation(description: "warm link")
        var received: DeferredLink?
        let task = Task {
            for await link in SdkCore.observeLinks() {
                if link.linkId == "lnk_warm" {
                    received = link
                    expectation.fulfill()
                    break
                }
            }
        }

        try? await Task.sleep(nanoseconds: 50_000_000)
        guard let url = URL(string: "https://go.example.com/offer?sku=42&linkId=lnk_warm") else {
            XCTFail("bad url")
            return
        }
        SdkCore.onOpenURL(url)

        await fulfillment(of: [expectation], timeout: 2.0)
        task.cancel()

        XCTAssertEqual(received?.path, "/offer")
        XCTAssertEqual(received?.params["sku"], "42")
        XCTAssertEqual(received?.isDeferred, false)
        XCTAssertEqual(received?.matchType, MatchType.none)
    }

    func testResolveClaim_works() async {
        let link = sampleLink("lnk_claim", matchType: .claim)
        var seen: ResolveRequest?
        configureWith(
            pasteboard: FixedPasteboard(token: nil),
            resolve: { req in
                seen = req
                return ResolveOutcome.matched(link)
            }
        )

        store.remove(SdkStoreKeys.deferredResolved)

        let result = await SdkCore.resolveClaim("claim_tok_1")
        XCTAssertEqual(result, link)
        XCTAssertEqual(seen?.claim, "claim_tok_1")
        XCTAssertNil(seen?.clipboard)
        XCTAssertNil(seen?.appClip)
        XCTAssertTrue(store.getBoolean(SdkStoreKeys.deferredResolved, default: false))

        let second = await SdkCore.resolveClaim("claim_tok_2")
        XCTAssertNil(second)
    }

    func testAppClipToken_preferredOverPasteboard() async {
        let link = sampleLink("lnk_clip", matchType: .appClip)
        var seen: ResolveRequest?
        configureWith(
            pasteboard: FixedPasteboard(token: "paste_tok"),
            appClip: FixedAppClipBridge(token: "appclip_tok"),
            resolve: { req in
                seen = req
                return ResolveOutcome.matched(link)
            }
        )

        let result = await SdkCore.resolveDeferred()
        XCTAssertEqual(result, link)
        XCTAssertEqual(seen?.appClip, "appclip_tok")
        XCTAssertNil(seen?.clipboard)
    }

    func testIosLinkListener_clipboardDeferredAndSkipsReferrer() async {
        XCTAssertTrue(
            isIosPlatformLink(sampleLink("c", matchType: .clipboard))
        )
        XCTAssertFalse(
            isIosPlatformLink(sampleLink("r", matchType: .installReferrer))
        )

        let link = sampleLink("lnk_listener", matchType: .clipboard)
        configureWith(
            pasteboard: FixedPasteboard(token: "tok_listener"),
            resolve: { _ in ResolveOutcome.matched(link) }
        )

        let box = ListenerBox()
        let id = SdkCore.addLinkListener(box)
        defer { SdkCore.removeLinkListener(id) }

        _ = await SdkCore.resolveDeferred()
        SdkCore.setReadyForNavigation(true)

        let delivered = expectation(description: "ios listener")
        box.onReceive = { delivered.fulfill() }
        // If already delivered synchronously, fulfill immediately.
        if box.last?.linkId == "lnk_listener" {
            delivered.fulfill()
        }
        await fulfillment(of: [delivered], timeout: 2.0)
        XCTAssertEqual(box.last?.matchType, .clipboard)
        XCTAssertEqual(box.last?.isDeferred, true)
    }

    func testParseNestedDeferredLink() {
        let json: [String: Any] = [
            "linkId": "lnk_nested",
            "url": "https://app.example.com/x",
            "path": "/x",
            "params": ["a": "1"],
            "matchType": "clipboard",
            "isDeferred": true,
        ]
        let link = URLSessionResolveClient.parseDeferredLink(json)
        XCTAssertEqual(link?.linkId, "lnk_nested")
        XCTAssertEqual(link?.matchType, .clipboard)
    }

    // MARK: - Helpers

    private func configureWith(
        pasteboard: PasteboardClient,
        appClip: AppClipBridge = StubAppClipBridge(),
        resolve: @escaping (ResolveRequest) async -> ResolveOutcome
    ) {
        SdkCore.configure(
            clientId: "app_test_demo",
            publicKeyId: "pk_test_demo",
            options: SdkOptions(apiBaseUrl: "https://api.example.test"),
            pasteboard: pasteboard,
            appClip: appClip,
            resolveClient: ClosureResolveClient(resolve),
            store: store,
            incomingLink: incoming
        )
    }

    private func sampleLink(_ id: String, matchType: MatchType) -> DeferredLink {
        DeferredLink(
            url: "https://app.example.com/offer?id=1",
            path: "/offer",
            params: ["id": "1"],
            linkId: id,
            matchType: matchType,
            isDeferred: true,
            campaign: Campaign(["utm_source": "invite"])
        )
    }
}

private final class ListenerBox: TaqlynLinkListener, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var last: DeferredLink?
    var onReceive: (() -> Void)?

    func taqlynDidReceiveLink(_ link: DeferredLink) {
        lock.lock()
        last = link
        let cb = onReceive
        lock.unlock()
        cb?()
    }
}

private final class DeliveryBox: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false

    func mark() {
        lock.lock()
        flag = true
        lock.unlock()
    }

    var wasDelivered: Bool {
        lock.lock()
        defer { lock.unlock() }
        return flag
    }
}
