import XCTest
@testable import InAppDebugKit

final class InAppDebugKitTests: XCTestCase {

    override func tearDown() {
        InAppDebug.configuration = .init(isEnabled: { false })
        super.tearDown()
    }

    // MARK: - Screen names
    func testScreenNameFromPlainHostingController() {
        XCTAssertEqual(DebugScreenTracker.screenName(from: "UIHostingController<HomeView>"), "HomeView")
    }

    func testScreenNameUnwrapsModifiersAndSheets() {
        let raw = "AnyViewStorage<ModifiedContent<SheetContent<ModifiedContent<ModifiedContent<EarnView, _Pref>, _Pref>>, _Env>>"
        XCTAssertEqual(DebugScreenTracker.screenName(from: raw), "EarnView")
        XCTAssertEqual(
            DebugScreenTracker.screenName(from: "UIHostingController<ModifiedContent<ProfileView, _EnvironmentKeyWritingModifier<Int>>>"),
            "ProfileView"
        )
    }

    func testScreenNameWithoutGenericsIsUnchanged() {
        XCTAssertEqual(DebugScreenTracker.screenName(from: "LoginViewController"), "LoginViewController")
    }

    // MARK: - Socket event names
    func testSocketEventNameFromSentPayload() {
        XCTAssertEqual(DebugFormatter.socketEventName(from: #"{"type":"room_create","data":{}}"#), "room_create")
    }

    func testSocketEventNameFromNestedEvent() {
        XCTAssertEqual(DebugFormatter.socketEventName(from: #"{"event":{"name":"updated_game","type":"on"}}"#), "updated_game")
    }

    func testSocketEventNameForNonJSON() {
        XCTAssertNil(DebugFormatter.socketEventName(from: "ping"))
    }

    // MARK: - Bodies
    func testPrettyJSON() {
        let pretty = DebugFormatter.prettyJSON(Data(#"{"b":1,"a":[1,2]}"#.utf8))
        XCTAssertNotNil(pretty)
        XCTAssertTrue(pretty!.contains("\n"))
        XCTAssertTrue(pretty!.range(of: "\"a\"")!.lowerBound < pretty!.range(of: "\"b\"")!.lowerBound, "keys are sorted")
    }

    func testBinaryBodyIsSummarised() {
        let text = DebugFormatter.bodyString(Data(repeating: 0, count: 2048), contentType: "image/png")
        XCTAssertEqual(text?.hasPrefix("<image/png"), true)
    }

    func testEmptyBodyIsNil() {
        XCTAssertNil(DebugFormatter.bodyString(Data(), contentType: "application/json"))
        XCTAssertNil(DebugFormatter.bodyString(nil, contentType: nil))
    }

    // MARK: - cURL
    func testCurlEscapesQuotesAndIncludesBody() {
        var request = URLRequest(url: URL(string: "https://api.example.com/v1/items")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let curl = DebugFormatter.curl(for: request, body: Data(#"{"name":"it's"}"#.utf8))
        XCTAssertTrue(curl.hasPrefix("curl -X POST"))
        XCTAssertTrue(curl.contains("-H 'Content-Type: application/json'"))
        XCTAssertTrue(curl.contains(#"it'\''s"#), "single quotes are shell-escaped")
        XCTAssertTrue(curl.hasSuffix("'https://api.example.com/v1/items'"))
    }

    // MARK: - Redaction
    func testRedactedHeadersAreCaseInsensitive() {
        InAppDebug.configuration = .init(isEnabled: { true }, redactedHeaders: ["authorization"])
        let result = DebugFormatter.redacted(["Authorization": "Bearer secret", "Accept": "*/*"])
        XCTAssertEqual(result["Authorization"], "••••")
        XCTAssertEqual(result["Accept"], "*/*")
    }

    func testCurlUsesRedactedHeaders() {
        InAppDebug.configuration = .init(isEnabled: { true }, redactedHeaders: ["Authorization"])
        var request = URLRequest(url: URL(string: "https://example.com")!)
        request.setValue("Bearer secret", forHTTPHeaderField: "Authorization")
        let curl = DebugFormatter.curl(for: request, body: nil,
                                       headers: DebugFormatter.redacted(request.allHTTPHeaderFields ?? [:]))
        XCTAssertFalse(curl.contains("secret"))
    }

    // MARK: - Host matching
    func testHostMatching() {
        let hosts = ["example.com"]
        XCTAssertTrue(DebugNetworkCapture.isCapturedHost("example.com", in: hosts))
        XCTAssertTrue(DebugNetworkCapture.isCapturedHost("api.EXAMPLE.com", in: hosts))
        XCTAssertFalse(DebugNetworkCapture.isCapturedHost("notexample.com", in: hosts))
        XCTAssertFalse(DebugNetworkCapture.isCapturedHost("firebase.googleapis.com", in: hosts))
        XCTAssertTrue(DebugNetworkCapture.isCapturedHost("anything.io", in: []), "empty list captures all hosts")
    }

    // MARK: - Crash storage
    func testCrashStorageRoundTrip() {
        DebugCrashStorage.deleteAll()
        let crash = DebugCrashEvent(
            id: UUID(), time: Date(), kind: "Signal SIGTRAP", reason: "test", className: "Foo.bar",
            stackTrace: "0 frame", lastScreen: "HomeView", lastApiCalls: ["200 GET /x"], appVersion: "1.0 (1)"
        )
        DebugCrashStorage.save(crash)
        let loaded = DebugCrashStorage.loadAll()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.id, crash.id)
        XCTAssertEqual(loaded.first?.lastScreen, "HomeView")
        DebugCrashStorage.deleteAll()
        XCTAssertTrue(DebugCrashStorage.loadAll().isEmpty)
    }
}
