import AppKit
import WebKit
import XCTest
@testable import Search

@MainActor
final class PopupPermissionTests: XCTestCase {
    private var browser: Browser!

    override class func setUp() {
        setenv("SEARCH_PROBE", "popup-permission-\(getpid())", 1)
        super.setUp()
    }

    override func setUp() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        browser = Browser(record: WindowRecord())
        browser.closeAll()
        browser.prefs.popupSites = []
        browser.prefs.blockedPopupSites = []
    }

    override func tearDown() {
        browser.closeAll()
        browser.prefs.popupSites = []
        browser.prefs.blockedPopupSites = []
        browser = nil
    }

    private func page(shy: Bool = false) async throws -> Tab {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        let tab = Tab(shy: shy, bench: true, configuration: config)
        browser.prepare(tab)
        browser.insert(tab, at: browser.tabs.count)
        browser.activeID = tab.id
        tab.web.loadHTMLString("<!doctype html><body>popup fixture</body>", baseURL: URL(string: "http://127.0.0.1:9/fixture"))
        try await until { !tab.web.isLoading && tab.committed != nil }
        return tab
    }

    private func request(_ tab: Tab) async throws {
        _ = try await tab.web.evaluateJavaScript("setTimeout(() => { window.result = window.open('about:blank', '_blank'); window.finished = true; }, 100); true")
        try await until { self.browser.pendingPopup != nil }
    }

    private func answer(_ allow: Bool, keep: Bool = true) throws {
        let question = try XCTUnwrap(browser.askingPopup)
        question.shown = Date(timeIntervalSinceNow: -1)
        browser.answerPopup(allow: allow, keep: keep)
    }

    private func until(_ condition: () -> Bool) async throws {
        for _ in 0..<300 {
            if condition() { return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("WebKit did not reach the expected popup state")
        throw NSError(domain: "PopupPermissionTests", code: 1)
    }

    func testAllowResumesOriginalBlankWindowAndKeepsOpener() async throws {
        let source = try await page()
        try await request(source)
        XCTAssertEqual(browser.tabs.count, 1, "no hidden popup is created before consent")
        XCTAssertEqual(browser.askingPopup?.host, "127.0.0.1")
        try answer(true)
        try await until { self.browser.tabs.count == 2 }
        let result = try await source.web.evaluateJavaScript("!!window.result && window.result.opener === window")
        XCTAssertEqual(result as? Bool, true)
        XCTAssertEqual(browser.prefs.popupSites, ["127.0.0.1"])
        XCTAssertNil(browser.pendingPopup)
        XCTAssertNil(browser.askingPopup)
    }

    func testDenialReturnsNullAndRemembersChoice() async throws {
        let source = try await page()
        try await request(source)
        try answer(false)
        try await until { self.browser.pendingPopup == nil }
        let refused = try await source.web.evaluateJavaScript("window.result === null")
        XCTAssertEqual(refused as? Bool, true)
        XCTAssertEqual(browser.tabs.count, 1)
        XCTAssertEqual(browser.prefs.blockedPopupSites, ["127.0.0.1"])
        _ = try await source.web.evaluateJavaScript("window.open('about:blank') === null")
        XCTAssertNil(browser.askingPopup)
        XCTAssertEqual(browser.tabs.count, 1)
    }

    func testAllowThisTimeOpensOnlyThePendingWindowAndAsksAgain() async throws {
        let source = try await page()
        try await request(source)
        try answer(true, keep: false)
        XCTAssertEqual(browser.tabs.count, 2)
        XCTAssertTrue(browser.prefs.popupSites.isEmpty)
        XCTAssertTrue(browser.prefs.blockedPopupSites.isEmpty)
        XCTAssertTrue(source.popupSites.isEmpty)
        browser.activeID = source.id
        try await request(source)
        XCTAssertNotNil(browser.askingPopup)
        XCTAssertEqual(browser.tabs.count, 2)
        try answer(false)
    }

    func testClickDoesNotBypassSitePermissionAndAccidentalAnswerIsIgnored() async throws {
        let source = try await page()
        source.popupGesture.record(origin: "http://127.0.0.1:9", kind: "input")
        try await request(source)
        browser.answerPopup(allow: true)
        XCTAssertNotNil(browser.askingPopup)
        XCTAssertEqual(browser.tabs.count, 1)
        try answer(false)
        XCTAssertEqual(browser.tabs.count, 1)
    }

    func testPrivateChoiceStaysInTheRequestingTab() async throws {
        browser.prefs.popupSites = ["127.0.0.1"]
        let source = try await page(shy: true)
        // A private tab does not inherit the ordinary browsing allow list.
        try await request(source)
        try answer(false)
        XCTAssertEqual(source.blockedPopupSites, ["127.0.0.1"])
        XCTAssertEqual(browser.prefs.popupSites, ["127.0.0.1"])
        XCTAssertTrue(browser.prefs.blockedPopupSites.isEmpty)
        let other = try await page(shy: true)
        XCTAssertTrue(other.popupSites.isEmpty)
        XCTAssertTrue(other.blockedPopupSites.isEmpty)
    }

    func testSwitchingClosingAndNavigationCancelWithoutRememberingAChoice() async throws {
        for action in ["switch", "close", "navigate", "discard"] {
            let source = try await page()
            try await request(source)
            switch action {
            case "switch": browser.activeID = nil
            case "close": browser.close(source)
            case "navigate": source.go(to: URL(string: "about:blank")!)
            default: source.close()
            }
            try await until { self.browser.pendingPopup == nil }
            XCTAssertNil(browser.askingPopup, action)
            XCTAssertTrue(browser.prefs.popupSites.isEmpty, action)
            XCTAssertTrue(browser.prefs.blockedPopupSites.isEmpty, action)
            browser.closeAll()
        }
    }

    func testReturnAndEscapeCancelInsteadOfAllowing() async throws {
        for code: UInt16 in [36, 76, 53] {
            let source = try await page()
            try await request(source)
            let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                timestamp: 0, windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "",
                isARepeat: false, keyCode: code))
            XCTAssertTrue(browser.popupKey(event))
            XCTAssertNil(browser.pendingPopup)
            XCTAssertEqual(browser.tabs.count, 1)
            XCTAssertTrue(browser.prefs.popupSites.isEmpty)
            browser.closeAll()
        }
    }

    func testBackgroundQuestionWaitsForItsOwnTab() async throws {
        let source = try await page()
        let other = try await page()
        try await request(source)
        XCTAssertNil(browser.askingPopup)
        XCTAssertEqual(browser.activeID, other.id)
        browser.activeID = source.id
        try await until { self.browser.askingPopup != nil }
        try answer(false)
    }

    func testChoicesPersistAndAlwaysAllowOverridesDenial() async throws {
        let source = try await page()
        try await request(source)
        try answer(false)
        let saved = Preferences()
        XCTAssertEqual(saved.blockedPopupSites, ["127.0.0.1"])
        browser.allowPopups(from: source)
        XCTAssertTrue(browser.prefs.blockedPopupSites.isEmpty)
        XCTAssertEqual(Preferences().popupSites, ["127.0.0.1"])
    }

    func testQuestionAnswersExactlyOnceEvenWhenReleased() async throws {
        let source = try await page()
        var replies: [Bool] = []
        var question: PopupQuestion? = PopupQuestion(site: "127.0.0.1", host: "127.0.0.1", tab: source, view: source.web) { replies.append($0) }
        question?.answer(false)
        question?.answer(true)
        question = nil
        XCTAssertEqual(replies, [false])
        question = PopupQuestion(site: "127.0.0.1", host: "127.0.0.1", tab: source, view: source.web) { replies.append($0) }
        question = nil
        XCTAssertEqual(replies, [false, false])
    }
}
