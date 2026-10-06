import XCTest
import SwiftUI
import AppKit
@testable import Search

final class JevTests: XCTestCase {
    func testLocalToolsAndIncompleteTimer() {
        XCTAssertEqual(HomeTool.local("I need a timer")?.kind, .timer)
        XCTAssertNil(HomeTool.local("I need a timer")?.value)
        XCTAssertEqual(HomeTool.local("timer 5 minutes")?.value, 300)
        XCTAssertEqual(HomeTool.local("25 min focus")?.value, 1500)
        XCTAssertEqual(HomeTool.local("stopwatch")?.kind, .stopwatch)
        XCTAssertNil(HomeTool.local("how do I build a timer in Swift"))
        XCTAssertNil(HomeTool.local("best calculator apps"))
        XCTAssertNil(HomeTool.local("timer app reviews"))
    }

    func testDurationsAndBounds() {
        XCTAssertEqual(HomeTool.duration("timer one hour 15 minutes"), 4500)
        XCTAssertEqual(HomeTool.duration("half an hour"), 1800)
        XCTAssertEqual(HomeTool.duration("pomodoro"), 1500)
        XCTAssertNil(HomeTool.duration("timer -5 minutes"))
        XCTAssertNil(HomeTool.duration("timer 0 minutes"))
        XCTAssertNil(HomeTool.duration("timer 999999 hours"))
    }

    func testArithmeticPrecedencePercentagesAndInvalidInput() {
        XCTAssertEqual(HomeTool.calculate("18% of 3450"), 621)
        XCTAssertEqual(HomeTool.calculate("(12 + 8) / 2"), 10)
        XCTAssertEqual(HomeTool.calculate("2 + 3 * 4"), 14)
        XCTAssertEqual(HomeTool.calculate("-2 * (-3 + 1)"), 4)
        for text in ["1/0", "1+", "1 2", "2..3", "2**3", "(1+2", "foo()", String(repeating: "(", count: 300)] {
            XCTAssertNil(HomeTool.calculate(text), text)
        }
    }

    func testConversionsUseCompatibleDimensions() throws {
        XCTAssertEqual(try XCTUnwrap(HomeTool.conversion("5 miles in km")).value, 8.04672, accuracy: 0.00001)
        XCTAssertEqual(try XCTUnwrap(HomeTool.conversion("72f to c")).value, 22.22222, accuracy: 0.00001)
        XCTAssertEqual(try XCTUnwrap(HomeTool.conversion("-40 c to f")).value, -40, accuracy: 0.00001)
        XCTAssertNil(HomeTool.conversion("5 kg in km"))
        XCTAssertNil(HomeTool.conversion("5 miles in unknown"))
    }

    func testSplittingValidatesPeopleAndRoundsExplicitly() {
        XCTAssertEqual(HomeTool.parse(.split, text: "split $84 between 3").value, 28)
        XCTAssertEqual(HomeTool.parse(.split, text: "split $10 between 3").value, 3.34)
        XCTAssertNil(HomeTool.parse(.split, text: "split $84 between 0").value)
        XCTAssertNil(HomeTool.parse(.split, text: "split $84 between 2.5").value)
    }

    func testTypingPolicy() {
        func allowed(_ text: String = "please time my tea", enabled: Bool = true, blank: Bool = true,
                     privateTab: Bool = false, over: Bool = false, reserved: Bool = false) -> Bool {
            HomeTools.permits(text: text, enabled: enabled, blank: blank, privateTab: privateTab, over: over, reserved: reserved)
        }
        XCTAssertTrue(allowed())
        XCTAssertFalse(allowed(enabled: false))
        XCTAssertFalse(allowed(blank: false))
        XCTAssertFalse(allowed(privateTab: true))
        XCTAssertFalse(allowed(over: true))
        XCTAssertFalse(allowed(reserved: true))
        for text in ["", "a", "example.com", "https://example.com/private", "me@example.com", "/Users/test/Documents", "~/private", String(repeating: "x", count: 1001)] {
            XCTAssertFalse(allowed(text), text)
        }
    }

    func testJevRequestUsesTypedAPIAndNoPageContext() throws {
        let request = try AIClient.jevRequest(text: "please time my tea", key: "fake-test-key")
        XCTAssertEqual(request.url?.absoluteString, "https://api.typesafe.ai/v1/systemone")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fake-test-key")
        XCTAssertEqual(request.timeoutInterval, 2.5)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual(body["model"] as? String, "jev-latest")
        XCTAssertEqual(body["state"] as? [String: String], ["text": "please time my tea"])
        XCTAssertNil(body["messages"])
        XCTAssertFalse(AIClient.allowed(URL(string: "http://api.typesafe.ai/v1/systemone")!, for: .jev))
        XCTAssertFalse(AIClient.allowed(URL(string: "https://example.com/v1/systemone")!, for: .jev))
        XCTAssertThrowsError(try AIClient.request(.jev, model: "jev-latest", system: "", messages: [], key: "fake"))
    }

    func testHTTPResponseDecodingAndRejection() async throws {
        let client = AIClient()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [JevProtocol.self]
        client.session = URLSession(configuration: configuration, delegate: client, delegateQueue: nil)
        defer { client.session.invalidateAndCancel() }
        JevProtocol.body = try JSONSerialization.data(withJSONObject: [
            "answers": ["tool": ["type": "choice", "choice": "timer", "confidence": 1,
                                     "probabilities": Self.answer(.timer).probabilities]]
        ])
        JevProtocol.status = 200
        let answer = try await client.jev(text: "please time my tea", key: "fake-test-key")
        XCTAssertEqual(answer.usable, .timer)
        for (status, body) in [(401, Data("invalid key".utf8)), (200, Data("not json".utf8)), (200, Data(repeating: 32, count: 65537))] {
            JevProtocol.status = status
            JevProtocol.body = body
            do {
                _ = try await client.jev(text: "please time my tea", key: "fake-test-key")
                XCTFail("Invalid response should fail")
            } catch { }
        }
        var redirected: URLRequest? = URLRequest(url: URL(string: "https://example.com")!)
        client.urlSession(client.session, task: client.session.dataTask(with: URL(string: "https://api.typesafe.ai")!),
                          willPerformHTTPRedirection: HTTPURLResponse(url: URL(string: "https://api.typesafe.ai")!, statusCode: 302, httpVersion: nil, headerFields: nil)!,
                          newRequest: redirected!) { redirected = $0 }
        XCTAssertNil(redirected)
    }

    func testConfidenceAndMalformedAnswers() throws {
        XCTAssertEqual(Self.answer(.timer).usable, .timer)
        XCTAssertNil(Self.answer(.none).usable)
        for retired in [HomeToolKind.split, .event, .habit, .goal, .poll] { XCTAssertNil(Self.answer(retired).usable) }
        let weak = JevAnswer(type: "choice", choice: .timer, confidence: 0.2, probabilities: Self.answer(.timer).probabilities)
        XCTAssertNil(weak.usable)
        XCTAssertNil(JevAnswer(type: "choice", choice: .timer, confidence: 1, probabilities: ["timer": 1]).usable)
        XCTAssertNil(JevAnswer(type: "choice", choice: .timer, confidence: .nan, probabilities: Self.answer(.timer).probabilities).usable)
        XCTAssertThrowsError(try JSONDecoder().decode(JevAnswer.self, from: Data(#"{"type":"choice","choice":"execute_code","confidence":1,"probabilities":{}}"#.utf8)))
    }

    @MainActor
    func testLocalAndDisabledRequestsNeverCallJev() async {
        let tools = HomeTools()
        var calls = 0
        let classify: (String, String) async throws -> JevAnswer = { _, _ in calls += 1; return Self.answer(.timer) }
        await tools.update(text: "timer 5 minutes", eligible: true, key: "fake", classify: classify)
        XCTAssertEqual(tools.suggestion?.value, 300)
        XCTAssertEqual(tools.source, "On this Mac")
        await tools.update(text: "please time my tea", eligible: false, key: "fake", classify: classify)
        XCTAssertNil(tools.suggestion)
        await tools.update(text: "please time my tea", eligible: true, key: nil, classify: classify)
        XCTAssertEqual(calls, 0)
    }

    @MainActor
    func testLateAnswerCannotReplaceNewTyping() async throws {
        let tools = HomeTools()
        let sent = expectation(description: "request sent after debounce")
        var reply: CheckedContinuation<JevAnswer, Error>?
        let old = Task {
            await tools.update(text: "please time my tea", eligible: true, key: "fake", classify: { _, _ in
                try await withCheckedThrowingContinuation { reply = $0; sent.fulfill() }
            })
        }
        await fulfillment(of: [sent], timeout: 3)
        await tools.update(text: "18% of 3450", eligible: true, key: nil)
        reply?.resume(returning: Self.answer(.timer))
        await old.value
        XCTAssertEqual(tools.suggestion?.kind, .calculate)
        XCTAssertEqual(tools.suggestion?.value, 621)
    }

    @MainActor
    func testCancellationAndKeyRevocationDiscardReplies() async throws {
        let tools = HomeTools()
        let sent = expectation(description: "request sent")
        var reply: CheckedContinuation<JevAnswer, Error>?
        let old = Task {
            await tools.update(text: "please time my tea", eligible: true, key: "fake", classify: { _, _ in
                try await withCheckedThrowingContinuation { reply = $0; sent.fulfill() }
            })
        }
        await fulfillment(of: [sent], timeout: 3)
        old.cancel()
        tools.invalidate()
        reply?.resume(returning: Self.answer(.timer))
        await old.value
        XCTAssertNil(tools.suggestion)
    }

    @MainActor
    func testCacheAndServiceFailure() async {
        let tools = HomeTools()
        var calls = 0
        let classify: (String, String) async throws -> JevAnswer = { _, _ in calls += 1; return Self.answer(.timer) }
        await tools.update(text: "please time my tea", eligible: true, key: "fake", classify: classify)
        await tools.update(text: "please time my tea", eligible: true, key: "fake", classify: classify)
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(tools.source, "Jev")
        tools.invalidate()
        await tools.update(text: "please time my tea", eligible: true, key: "fake", classify: { _, _ in throw URLError(.timedOut) })
        XCTAssertNil(tools.suggestion)
        XCTAssertNotNil(tools.notice)
        await tools.update(text: "timer 5 minutes", eligible: true, key: "fake", classify: classify)
        XCTAssertEqual(tools.suggestion?.value, 300)
        XCTAssertNil(tools.notice)
    }

    func testTimerContinuesWithoutAViewAndPauses() {
        let start = Date(timeIntervalSince1970: 1000)
        var timer = ToolClock(stopwatch: false, duration: 60, started: start)
        XCTAssertEqual(timer.shown(at: start.addingTimeInterval(20)), 40)
        timer.toggle(at: start.addingTimeInterval(20))
        XCTAssertEqual(timer.shown(at: start.addingTimeInterval(100)), 40)
        timer.toggle(at: start.addingTimeInterval(100))
        XCTAssertEqual(timer.shown(at: start.addingTimeInterval(110)), 30)
        XCTAssertTrue(timer.finished(at: start.addingTimeInterval(150)))
        XCTAssertEqual(timer.shown(at: start.addingTimeInterval(150)), 0)
    }

    @MainActor
    func testNativeCardsRender() async throws {
        guard Store.testing else { throw XCTSkip("Run with SEARCH_PROBE=jev-tests to isolate browser state") }
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let browser = Browser()
        let prefs = browser.prefs
        let previous = prefs.jevTools
        let previousQuick = prefs.quickTools
        defer { prefs.jevTools = previous; prefs.quickTools = previousQuick }
        prefs.jevTools = true
        prefs.quickTools = true
        let notes = [QuickCard(kind: .note, input: "note Pick up flowers on the way home"),
                     QuickCard(kind: .note, input: "note A quiet morning, a good book, and coffee.")]
        for note in notes { try QuickCards.shared.save(note) }
        defer { for note in notes { try? QuickCards.shared.delete(note.id) } }
        browser.newTab()
        let folder = URL(fileURLWithPath: "/private/tmp/search-jev-previews", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let examples: [(String, String)] = [("timer", "timer 5 minutes"), ("calculate", "18% of 3450"), ("convert", "5 miles in km"), ("split", "split $84 between 3"),
            ("todo", "buy milk, eggs and bread"), ("note", "note A quiet morning"), ("goal", "goal read 12 books, 4 done"), ("color", "#ff6b35"), ("event", "event Dinner tomorrow at 8pm"), ("reminder", "remind me to call tomorrow"), ("habit", "habit meditate every day"), ("expense", "spent 450 on train"), ("travel", "trip London tomorrow"), ("poll", "poll tea or coffee"), ("contact", "contact Ada ada@example.com"), ("link", "bookmark https://example.com"), ("countdown", "countdown December 25, 2027"), ("timezone", "time in tokyo"), ("random", "roll 2d6"), ("home-notes", "")]
        for (name, text) in examples where HomeToolKind(rawValue: name)?.supported != false {
            browser.typed = text
            await browser.homeTools.update(text: text, eligible: true, key: nil)
            for scheme in [ColorScheme.light, .dark] {
                let view = HomeToolsPanel(browser: browser, prefs: prefs, tools: browser.homeTools, over: false)
                    .frame(width: 560).padding(24).background(Palette.wash).environment(\.colorScheme, scheme)
                // ImageRenderer omits AppKit-backed fields and scroll contents.
                // Host in an offscreen window to exercise the actual native controls.
                let host = NSHostingView(rootView: view)
                let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 608, height: 460), styleMask: .borderless, backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.contentView = host
                host.frame = NSRect(x: 0, y: 0, width: 608, height: 460)
                window.appearance = NSAppearance(named: scheme == .light ? .aqua : .darkAqua)
                host.layoutSubtreeIfNeeded()
                try await Task.sleep(for: .milliseconds(350))
                host.displayIfNeeded()
                let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: bitmap)
                let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                window.close()
                try png.write(to: folder.appendingPathComponent("\(name)-\(scheme == .light ? "light" : "dark").png"))
            }
        }
    }

    func testShapeShiftCatalogAndEditableValues() throws {
        let expected: Set<String> = ["reminder", "todo", "timer", "color", "expense", "convert", "calculate", "travel", "contact", "link", "countdown", "timezone", "random", "note"]
        XCTAssertEqual(Set(HomeToolKind.supported.filter { $0 != .none && $0 != .stopwatch && $0 != .email && $0 != .inbox }.map(\.rawValue)), expected)
        let request = try AIClient.jevRequest(text: "help me plan a trip", key: "fake")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        let questions = try XCTUnwrap(body["questions"] as? [String: [String: Any]])
        let criteria = try XCTUnwrap(questions["tool"]?["criteria"] as? [String: String])
        XCTAssertEqual(Set(criteria.keys), Set(HomeToolKind.allCases.map(\.rawValue)))
        for kind in HomeToolKind.supported where kind != .none {
            XCTAssertEqual(HomeTool.local(kind.title)?.kind, kind)
        }
        XCTAssertEqual(QuickCard(kind: .todo, input: "buy milk, eggs and bread").items, ["milk", "eggs", "bread"])
        XCTAssertEqual(QuickCard(kind: .color, input: "#ff6b35").hex, "#FF6B35")
        let goal = QuickCard(kind: .goal, input: "read 12 books, 4 done")
        XCTAssertEqual(goal.target, 12)
        XCTAssertEqual(goal.current, 4)
        let expense = QuickCard(kind: .expense, input: "spent £450 on train")
        XCTAssertEqual(expense.amount, "450")
        XCTAssertEqual(expense.currency, "GBP")
        XCTAssertEqual(expense.title, "train")
        XCTAssertNil(QuickCard(kind: .link, input: "javascript:alert(1)").validURL)
        XCTAssertEqual(QuickCard(kind: .link, input: "bookmark https://example.com").validURL?.host, "example.com")
        XCTAssertEqual(QuickCard(kind: .contact, input: "contact Ada ada@example.com").text, "ada@example.com")
        XCTAssertNotNil(QuickCard(kind: .countdown, input: "countdown December 25, 2027").date)
        XCTAssertNil(QuickCard(kind: .countdown, input: "countdown").date)
        let zone = QuickCard(kind: .timezone, input: "3pm pst in ist")
        XCTAssertEqual(zone.fromZone, "America/Los_Angeles")
        XCTAssertEqual(zone.zone, "Asia/Kolkata")
        XCTAssertFalse(zone.live)
        XCTAssertNotNil(zone.date)
        for text in ["roll 0d6", "roll 99d6", "roll 2d1", "pick tea"] { XCTAssertNil(QuickCard.roll(text), text) }
        for _ in 0..<20 {
            XCTAssertTrue(["Heads", "Tails"].contains(QuickCard.roll("flip a coin") ?? ""))
            XCTAssertTrue(["tea", "coffee"].contains(QuickCard.roll("pick tea or coffee") ?? ""))
            let roll = Int(QuickCard.roll("1d6") ?? "") ?? 0
            XCTAssertTrue((1...6).contains(roll))
        }
    }

    @MainActor
    func testSavedCardsRoundTripAndExplicitPrivateLocalRouting() async throws {
        let suite = "Search-Jev-Cards-Tests-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let saved = QuickCards(defaults: defaults)
        var card = QuickCard(kind: .todo, input: "buy milk, eggs")
        card.checked = [1]
        try saved.save(card)
        XCTAssertEqual(QuickCards(defaults: defaults).cards, [card])
        card.items.append("bread")
        try saved.save(card)
        XCTAssertEqual(saved.cards.count, 1)
        XCTAssertEqual(QuickCards(defaults: defaults).cards, [card])
        try saved.delete(card.id)
        XCTAssertTrue(QuickCards(defaults: defaults).cards.isEmpty)
        let tools = HomeTools()
        for text in ["contact Ada ada@example.com", "bookmark https://example.com"] {
            XCTAssertTrue(HomeTools.permits(text: text, enabled: true, blank: true, privateTab: false, over: false, reserved: false))
            XCTAssertFalse(HomeTools.permits(text: text, enabled: true, blank: true, privateTab: true, over: false, reserved: false))
            await tools.update(text: text, eligible: true, key: "fake", classify: { _, _ in
                XCTFail("Explicit contact/bookmark must not leave this Mac")
                return Self.answer(.none)
            })
            XCTAssertNotNil(tools.suggestion)
        }
    }

    func testOpenRouterUsesItsOwnHostAndTypedAPI() throws {
        let request = try AIClient.jevRequest(text: "please time my tea", key: "sk-or-fake-test-key", provider: .jevOpenRouter)
        XCTAssertEqual(request.url?.absoluteString, "https://openrouter.ai/api/v1/systemone")
        XCTAssertThrowsError(try AIClient.jevRequest(text: "tea", key: "sk-or-fake-test-key", provider: .jev))
        XCTAssertThrowsError(try AIClient.jevRequest(text: "tea", key: "fake", provider: .openRouter))
        XCTAssertThrowsError(try AIClient.request(.jevOpenRouter, model: "jev-latest", system: "", messages: [], key: "fake"))
    }

    func testLiveOpenRouterClassification() async throws {
        guard let key = ProcessInfo.processInfo.environment["SEARCH_JEV_LIVE_KEY"], !key.isEmpty else {
            throw XCTSkip("Live Jev test requires an explicitly supplied ephemeral key")
        }
        let samples: [(String, HomeToolKind)] = [
            ("please time my tea for three minutes", .timer),
            ("make a shopping list with milk, eggs and bread", .todo),
            ("save a note: the garden looks beautiful today", .note),
            ("track my goal to read 12 books this year, 4 done", .none),
            ("log that I paid 12 dollars for lunch", .expense),
            ("let me choose a color for my wall", .color),
            ("what time is it in Tokyo right now", .timezone),
            ("randomly choose between tea and coffee", .random),
            ("record a dinner with Sam tomorrow at eight", .none),
            ("remind me to call my dentist tomorrow", .reminder),
            ("best timer apps for mac reviews", .none),
            ("how do I build a calculator in Swift", .none),
            ("split a $84 bill between 3 people", .none),
            ("track a habit of meditating every morning", .none),
            ("make a poll with tea and coffee as options", .none)
        ]
        var passed = 0
        for (index, sample) in samples.enumerated() {
            let start = Date()
            do {
                let answer = try await AIClient.shared.jev(text: sample.0, key: key, provider: .jevOpenRouter)
                let shown = answer.usable ?? .none
                if shown == sample.1 { passed += 1 }
                print("JEV_LIVE sample=\(index + 1) expected=\(sample.1.rawValue) shown=\(shown.rawValue) confidence=\(answer.confidence) seconds=\(Date().timeIntervalSince(start))")
                XCTAssertEqual(shown, sample.1, "Synthetic sample \(index + 1)")
            } catch {
                print("JEV_LIVE sample=\(index + 1) request_failed")
                XCTFail("Live request failed for synthetic sample \(index + 1)")
            }
        }
        print("JEV_LIVE passed=\(passed) total=\(samples.count)")
    }

    private static func answer(_ kind: HomeToolKind) -> JevAnswer {
        JevAnswer(type: "choice", choice: kind, confidence: 1,
                  probabilities: Dictionary(uniqueKeysWithValues: HomeToolKind.allCases.map { ($0.rawValue, $0 == kind ? 1 : 0) }))
    }
}

/// All requests in the HTTP test terminate here; no real provider receives a key.
private final class JevProtocol: URLProtocol {
    static var body = Data()
    static var status = 200
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { }
}
