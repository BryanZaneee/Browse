import XCTest
import SwiftUI
import AppKit
@testable import Search

final class HomeToolsIntegrationTests: XCTestCase {
    func testCurrencyPhrasingAndInvalidInputs() throws {
        for text in ["100 USD to EUR", "convert $100 into euros", "How much is 100 US dollars in euros?", "Could you convert USD 100 to EUR please?"] {
            let conversion = try XCTUnwrap(CurrencyConversion.parse(text), text)
            XCTAssertEqual(conversion.amount, 100, text)
            XCTAssertEqual(conversion.base, "USD", text)
            XCTAssertEqual(conversion.quote, "EUR", text)
            XCTAssertEqual(HomeTool.local(text)?.kind, .convert, text)
        }
        XCTAssertEqual(CurrencyConversion.parse("1,234.56 GBP to JPY")?.amount, Decimal(string: "1234.56"))
        XCTAssertEqual(CurrencyConversion.parse("25 euros to Canadian dollars")?.quote, "CAD")
        XCTAssertEqual(CurrencyConversion.parse("-25 USD to EUR")?.amount, -25)
        for text in ["1,00 USD to EUR", "100 XYZ to EUR", "100 BTC to USD", "¥100 to USD", "NaN USD to EUR", "1e99 USD to EUR", "100 USD to EUR tomorrow", "USD to EUR", "1000000000001 USD to EUR", "100 USD to EUR https://example.com"] {
            XCTAssertNil(CurrencyConversion.parse(text), text)
        }
        XCTAssertNil(CurrencyConversion.parse("5 pounds to kg"))
        XCTAssertNotNil(HomeTool.conversion("5 pounds to kg"))
    }

    func testConversationalPhrasingWithoutStealingResearch() throws {
        let examples: [(String, HomeToolKind)] = [
            ("Could you set a 5-minute timer please?", .timer),
            ("I need a timer for five minutes", .timer),
            ("what is 18% of 3450?", .calculate),
            ("please convert 5 miles into kilometers", .convert),
            ("how many kilometers are in 5 miles", .convert),
            ("make a shopping list with milk, eggs and bread", .todo),
            ("save a note: Call Sam", .note)
        ]
        for (text, kind) in examples { XCTAssertEqual(HomeTool.local(text)?.kind, kind, text) }
        XCTAssertEqual(HomeTool.local(examples[0].0)?.value, 300)
        XCTAssertEqual(HomeTool.local(examples[2].0)?.value, 621)
        XCTAssertEqual(QuickCard(kind: .todo, input: examples[5].0).items, ["milk", "eggs", "bread"])
        for text in ["best timer apps", "timer app reviews", "how do I build a calculator", "currency exchange news", "EUR USD forecast", "buy an iphone online", "flight to Paris"] {
            XCTAssertNil(HomeTool.local(text), text)
        }
    }

    func testRatesValidateDatePairAndDecimalRounding() throws {
        let input = try XCTUnwrap(CurrencyConversion.parse("100 USD to EUR"))
        let rate = Self.rate()
        XCTAssertTrue(rate.valid(for: input))
        XCTAssertEqual(input.tool(rate: rate)?.value, 89)
        XCTAssertTrue(input.tool(rate: rate)?.detail.contains("89.00") == true)
        XCTAssertNil(input.tool(rate: CurrencyRate(date: rate.date, base: "EUR", quote: "USD", rate: 1)))
        for bad in [CurrencyRate(date: "1999-01-01", base: "USD", quote: "EUR", rate: 1),
                    CurrencyRate(date: "2099-01-01", base: "USD", quote: "EUR", rate: 1),
                    CurrencyRate(date: rate.date, base: "USD", quote: "EUR", rate: 0),
                    CurrencyRate(date: rate.date, base: "USD", quote: "EUR", rate: -1)] {
            XCTAssertFalse(bad.valid(for: input))
        }
        let request = try AIClient.currencyRequest(for: input)
        XCTAssertEqual(request.url?.absoluteString, "https://api.frankfurter.dev/v2/rate/usd/eur")
        XCTAssertNil(request.httpBody)
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertFalse(request.url?.absoluteString.contains("100") == true)
    }

    @MainActor
    func testCurrencyFailureSameCurrencyAndStaleReply() async throws {
        let tools = HomeTools()
        await tools.update(text: "100 USD to USD", eligible: true, key: nil, exchange: { _ in
            XCTFail("Same currency must not request a rate"); return Self.rate()
        })
        XCTAssertEqual(tools.suggestion?.value, 100)
        await tools.update(text: "100 USD to EUR", eligible: true, key: nil, exchange: { _ in throw URLError(.notConnectedToInternet) })
        XCTAssertNil(tools.suggestion?.value)
        XCTAssertNotNil(tools.notice)
        XCTAssertFalse(tools.updating)
        let sent = expectation(description: "exchange sent")
        var reply: CheckedContinuation<CurrencyRate, Error>?
        let old = Task {
            await tools.update(text: "100 USD to EUR", eligible: true, key: nil, exchange: { _ in
                try await withCheckedThrowingContinuation { reply = $0; sent.fulfill() }
            })
        }
        await fulfillment(of: [sent], timeout: 2)
        await tools.update(text: "timer 5 minutes", eligible: true, key: nil)
        reply?.resume(returning: Self.rate())
        await old.value
        XCTAssertEqual(tools.suggestion?.kind, .timer)
        XCTAssertNil(tools.notice)
    }

    @MainActor
    func testTypingKeepsPreviewUntilReplacementAndClearsPrivateInput() async throws {
        let tools = HomeTools()
        await tools.update(text: "timer 5 minutes", eligible: true, key: nil)
        let waiting = Task { await tools.update(text: "timer 5 mi", eligible: true, key: nil) }
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(tools.suggestion?.kind, .timer)
        XCTAssertTrue(tools.updating)
        XCTAssertNotEqual(tools.resultText, "timer 5 mi")
        waiting.cancel()
        await tools.update(text: "timer 5 minutes", eligible: false, key: nil)
        await waiting.value
        XCTAssertNil(tools.suggestion)
        XCTAssertFalse(tools.updating)
    }

    /// Exercises NSTextView insertion → AddressField delegate → Browser.typed →
    /// mounted SwiftUI .task → local/HTTP result. Never invokes HomeTools.update directly.
    @MainActor
    func testActualSearchFieldRoutesTypingAndPreservesFocus() async throws {
        guard Store.testing else { throw XCTSkip("Use an isolated SEARCH_PROBE world") }
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let browser = Browser()
        let priorQuick = browser.prefs.quickTools
        browser.prefs.quickTools = true
        let priorEnabled = browser.prefs.jevTools
        let priorProvider = browser.prefs.jevViaOpenRouter
        browser.prefs.jevTools = false
        let liveKey = ProcessInfo.processInfo.environment["SEARCH_JEV_LIVE_KEY"]
        browser.prefs.jevViaOpenRouter = liveKey != nil
        browser.prefs.jevTools = liveKey != nil
        AIKeys.forget(.jev)
        AIKeys.forget(.jevOpenRouter)
        if let liveKey { _ = AIKeys.save(liveKey, for: .jevOpenRouter) }
        defer { AIKeys.forget(.jevOpenRouter) }
        defer { browser.prefs.quickTools = priorQuick; browser.prefs.jevTools = priorEnabled; browser.prefs.jevViaOpenRouter = priorProvider }
        browser.newTab()
        let client = AIClient.shared
        let priorSession = client.session
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CurrencyProtocol.self]
        client.session = URLSession(configuration: configuration, delegate: client, delegateQueue: nil)
        CurrencyProtocol.reply = try JSONEncoder().encode(RatePayload(Self.rate()))
        defer { client.session.invalidateAndCancel(); client.session = priorSession }
        let host = NSHostingView(rootView: Omnibox(browser: browser, over: false).frame(width: 640, height: 680).background(Palette.wash))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 680), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        func find(_ view: NSView) -> NSTextField? {
            if let field = view as? NSTextField, field.identifier?.rawValue == "SearchAddressField" { return field }
            return view.subviews.lazy.compactMap(find).first
        }
        let field = try XCTUnwrap(find(host))
        window.makeFirstResponder(field)
        let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
        for character in "timer 5 minutes" {
            editor.insertText(String(character), replacementRange: editor.selectedRange())
            try await Task.sleep(for: .milliseconds(16))
            if browser.typed.hasPrefix("timer") {
                XCTAssertEqual(browser.homeTools.suggestion?.kind, .timer, "Preview should survive intermediate keystrokes")
            }
        }
        XCTAssertEqual(browser.typed, "timer 5 minutes")
        editor.deleteBackward(nil)
        XCTAssertEqual(browser.typed, "timer 5 minute")
        var samples: [(String, HomeToolKind)] = [("set a timer for 5 minutes", HomeToolKind.timer), ("100 USD to EUR", .convert),
                             ("convert 5 miles to kilometers", .convert),
                             ("make a shopping list with milk, eggs and bread", .todo), ("save a note: Call Sam", .note), ("send an email to alex@example.com that says See you at 5", .email), ("email", .inbox)]
        if liveKey != nil {
            samples.append(("please time my tea for three minutes", .timer))
            samples.append(("For dinner I need to pick up tomatoes, pasta and basil", .todo))
            samples.append(("Help me write to Alex by email saying I will be there at five", .email))
        }
        for (text, kind) in samples {
            editor.insertText(text, replacementRange: NSRange(location: 0, length: (editor.string as NSString).length))
            XCTAssertEqual(browser.typed, text)
            for _ in 0..<180 {
                if browser.homeTools.resultText == text && !browser.homeTools.updating { break }
                try await Task.sleep(for: .milliseconds(25))
            }
            XCTAssertEqual(browser.homeTools.suggestion?.kind, kind, text)
            XCTAssertEqual(browser.homeTools.resultText, text)
            try await Task.sleep(for: .milliseconds(50))
            XCTAssertTrue(browser.homeTools.showingCard, "Tool cards must hide the search suggestions")
            XCTAssertTrue(window.firstResponder === editor, "Cards must not take focus from typing")
            if text == "100 USD to EUR" { XCTAssertEqual(browser.homeTools.suggestion?.value, 89) }
            if text.hasPrefix("For dinner") { XCTAssertEqual(QuickCard(kind: .todo, input: browser.homeTools.suggestion!.detail).items, ["tomatoes", "pasta", "basil"]) }
            if text == "100 USD to EUR" || kind == .todo || kind == .note || kind == .email || kind == .inbox {
                try await Task.sleep(for: .milliseconds(350))
                host.layoutSubtreeIfNeeded()
                let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: bitmap)
                let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                try png.write(to: URL(fileURLWithPath: "/private/tmp/searchbar-\(kind.rawValue).png"))
            }
        }
        for text in ["https://example.com", "someone@example.com", "", "best timer apps"] {
            editor.insertText(text, replacementRange: NSRange(location: 0, length: (editor.string as NSString).length))
            try await Task.sleep(for: .milliseconds(350))
            XCTAssertNil(browser.homeTools.suggestion, text)
            XCTAssertFalse(browser.homeTools.showingCard, "Ordinary search suggestions must return")
        }
        // Return searches the exact input, even if a hidden suggestion was selected.
        let engine = browser.prefs.engine, custom = browser.prefs.customEngine
        defer { browser.prefs.engine = engine; browser.prefs.customEngine = custom }
        let phrase = "timer 5 minutes"
        editor.insertText(phrase, replacementRange: NSRange(location: 0, length: (editor.string as NSString).length))
        try await Task.sleep(for: .milliseconds(350))
        XCTAssertTrue(browser.homeTools.showingCard)
        browser.prefs.engine = .google
        let google = try XCTUnwrap(browser.searchURL(for: phrase))
        XCTAssertEqual(google.host, "www.google.com")
        XCTAssertEqual(URLComponents(url: google, resolvingAgainstBaseURL: false)?.queryItems?.first?.value, phrase)
        // Drive navigation against loopback, without sending a real Google search.
        browser.prefs.engine = .custom
        browser.prefs.customEngine = "http://127.0.0.1:9/search?q=%s"
        let expected = browser.searchURL(for: phrase)
        browser.picked = browser.offers.isEmpty ? nil : 0
        let picked = browser.picked
        _ = field.delegate?.control?(field, textView: editor, doCommandBy: #selector(NSResponder.moveDown(_:)))
        XCTAssertEqual(browser.picked, picked, "Arrow keys must not choose invisible suggestions")
        let handled = field.delegate?.control?(field, textView: editor, doCommandBy: #selector(NSResponder.insertNewline(_:)))
        XCTAssertEqual(handled, true)
        XCTAssertEqual(browser.active?.address, expected)
        XCTAssertEqual(browser.typed, "")

    }

    func testLiveCurrencyService() async throws {
        guard ProcessInfo.processInfo.environment["SEARCH_CURRENCY_LIVE"] == "1" else { throw XCTSkip("Opt-in live currency check") }
        for phrase in ["100 USD to EUR", "25 GBP to JPY", "100 CAD to INR"] {
            let conversion = try XCTUnwrap(CurrencyConversion.parse(phrase))
            let rate = try await AIClient.shared.currencyRate(for: conversion)
            XCTAssertTrue(rate.valid(for: conversion))
            XCTAssertNotNil(conversion.tool(rate: rate))
            print("CURRENCY_LIVE pair=\(rate.base)/\(rate.quote) date=\(rate.date) passed")
        }
    }

    private static func rate() -> CurrencyRate {
        let format = DateFormatter(); format.dateFormat = "yyyy-MM-dd"; format.timeZone = TimeZone(secondsFromGMT: 0)
        return CurrencyRate(date: format.string(from: Date()), base: "USD", quote: "EUR", rate: Decimal(string: "0.89")!)
    }
    private struct RatePayload: Encodable {
        let date: String, base: String, quote: String
        let rate: Decimal
        init(_ value: CurrencyRate) { date = value.date; base = value.base; quote = value.quote; rate = value.rate }
    }
}

private final class CurrencyProtocol: URLProtocol {
    static var reply = Data()
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "api.frankfurter.dev" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard request.url?.host == "api.frankfurter.dev", request.value(forHTTPHeaderField: "Authorization") == nil else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL)); return
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.reply)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
