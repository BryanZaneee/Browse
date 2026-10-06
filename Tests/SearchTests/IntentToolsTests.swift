import XCTest
@testable import Search

final class IntentToolsTests: XCTestCase {
    func testSemanticContentCopiesOnlyValidatedSourceSpan() throws {
        let text = "For dinner I need tomatoes, pasta and crème fraîche please"
        let spans = JevContent(text: text)
        func choice(_ key: String, confidence: Double = 1) -> JevContent.Selection {
            JevContent.Selection(type: "choice", choice: key, confidence: confidence,
                                 probabilities: Dictionary(uniqueKeysWithValues: spans.keys.map { ($0, $0 == key ? 1 : 0) }))
        }
        let content = try XCTUnwrap(spans.selected(start: choice("w4"), end: choice("w8")))
        XCTAssertEqual(content, "tomatoes, pasta and crème fraîche")
        XCTAssertEqual(QuickCard(kind: .todo, input: content).items, ["tomatoes", "pasta", "crème fraîche"])
        XCTAssertNil(spans.selected(start: choice("w8"), end: choice("w4")))
        XCTAssertNil(spans.selected(start: choice("w4", confidence: 0.1), end: choice("w8")))
        XCTAssertNil(spans.selected(start: choice("w999"), end: choice("w8")))
        XCTAssertEqual(spans.selected(start: choice("none"), end: choice("none")), "")
        XCTAssertTrue(JevContent(text: String(repeating: "word ", count: 81)).words.isEmpty)
    }

    func testDetailRequestBoundsAndRecipientValidation() throws {
        let request = try AIClient.jevRequest(text: String(repeating: "word ", count: 81), key: "fake")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any])
        XCTAssertEqual(Set((json["questions"] as! [String: Any]).keys), ["tool"])
        let spans = JevContent(text: "Let Alex Smith know by email that I will be late")
        let key = try XCTUnwrap(spans.recipients.first(where: { $0.value == "Alex Smith" })?.key)
        let keys = Set(spans.recipients.keys).union(["none"])
        let selection = JevContent.Selection(type: "choice", choice: key, confidence: 1,
            probabilities: Dictionary(uniqueKeysWithValues: keys.map { ($0, $0 == key ? 1 : 0) }))
        XCTAssertEqual(spans.recipient(selection), "Alex Smith")
        let draft = EmailDraft(input: "Let Alex Smith know by email that I will be late", selectedBody: "I will be late", selectedRecipient: spans.recipient(selection))
        XCTAssertEqual(draft.recipient, "Alex Smith")
        XCTAssertEqual(draft.body, "I will be late")
        XCTAssertNil(draft.mailURL)
    }

    func testComposerPreservesMessageAndEscapesMailHeaders() throws {
        let draft = EmailDraft(input: "Could you send an email to alex+work@example.com that says See you at 5 & bring tea?")
        XCTAssertEqual(draft.recipient, "alex+work@example.com")
        XCTAssertEqual(draft.body, "See you at 5 & bring tea?")
        let parts = try XCTUnwrap(URLComponents(url: XCTUnwrap(draft.mailURL), resolvingAgainstBaseURL: false))
        XCTAssertEqual(parts.scheme, "mailto")
        XCTAssertEqual(parts.path, "alex+work@example.com")
        XCTAssertEqual(parts.queryItems?.map(\.name), ["subject", "body"])
        XCTAssertEqual(parts.queryItems?.last?.value, draft.body)
        var injection = draft
        injection.body = "Hello &bcc=other@example.com\nNext line"
        XCTAssertEqual(URLComponents(url: injection.mailURL!, resolvingAgainstBaseURL: false)?.queryItems?.count, 2)
        injection.recipient = "alex@example.com?bcc=other@example.com"
        XCTAssertNil(injection.mailURL)
        injection = draft; injection.subject = "Hi\r\nBcc: other@example.com"
        XCTAssertNil(injection.mailURL)
        XCTAssertNil(EmailDraft(input: "email Alex that says Hi").mailURL)
        XCTAssertEqual(EmailDraft(input: "write an email to sam@example.com with subject Lunch saying Meet at noon").subject, "Lunch")
        XCTAssertEqual(EmailDraft(input: "send an email to x that says").recipient, "x")
    }

    @MainActor
    func testSemanticRoutingPopulatesChecklistAndEmailWithoutExecuting() async {
        let tools = HomeTools()
        var answer = JevAnswer(type: "choice", choice: .todo, confidence: 1,
                               probabilities: Dictionary(uniqueKeysWithValues: HomeToolKind.allCases.map { ($0.rawValue, $0 == .todo ? 1 : 0) }))
        answer.content = "milk, eggs and bread"
        await tools.update(text: "For tomorrow I need to pick up milk, eggs and bread", eligible: true, key: "fake", classify: { _, _ in answer })
        XCTAssertEqual(tools.suggestion?.kind, .todo)
        XCTAssertEqual(QuickCard(kind: .todo, input: tools.suggestion!.detail).items, ["milk", "eggs", "bread"])
        let email = "Send an email to sam@example.com that says Hello"
        XCTAssertTrue(HomeTools.permits(text: email, enabled: true, blank: true, privateTab: false, over: false, reserved: false))
        XCTAssertFalse(HomeTools.permits(text: email, enabled: true, blank: true, privateTab: true, over: false, reserved: false))
        await tools.update(text: email, eligible: true, key: "fake", classify: { _, _ in XCTFail("Explicit draft must stay local"); return answer })
        XCTAssertEqual(tools.suggestion?.kind, .email)
        XCTAssertEqual(EmailDraft(input: tools.suggestion!.detail).body, "Hello")
        XCTAssertEqual(HomeTool.local("email")?.kind, .inbox)
        for query in ["email marketing courses", "how to send an email", "best email apps"] { XCTAssertNil(HomeTool.local(query)) }
    }

    @MainActor
    func testRetiredComponentsAreUnavailableWithoutLosingSavedNotes() throws {
        let retired: [HomeToolKind] = [.split, .event, .habit, .goal, .poll]
        XCTAssertEqual(HomeToolKind.supported.filter { $0 != .none }.count, 17)
        for kind in retired {
            XCTAssertFalse(kind.supported)
            XCTAssertNil(HomeTool.local(kind.example))
        }
        let suite = "Search-Retired-Tools-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let cards = QuickCards(defaults: defaults)
        try cards.save(QuickCard(kind: .goal, input: "Old saved goal"))
        try cards.save(QuickCard(kind: .note, input: "Keep this note"))
        let restored = QuickCards(defaults: defaults).cards
        XCTAssertEqual(restored.count, 2)
        XCTAssertEqual(restored.filter { $0.kind.supported }.map(\.text), ["Keep this note"])
    }

    func testLiveNaturalDetails() async throws {
        guard let key = ProcessInfo.processInfo.environment["SEARCH_JEV_LIVE_KEY"], !key.isEmpty else { throw XCTSkip("Opt-in live Jev check") }
        let samples: [(String, HomeToolKind, String?)] = [
            ("For dinner I need to pick up tomatoes, pasta and basil", .todo, "tomatoes, pasta and basil"),
            ("I should grab milk, eggs and bread on my next grocery run", .todo, "milk, eggs and bread"),
            ("Keep this thought for me: the garden looks beautiful today", .note, "the garden looks beautiful today"),
            ("Help me write to Alex by email saying I'll be there at five", .email, "I'll be there at five"),
            ("Anything new in my inbox?", .inbox, nil),
            ("compare the best email apps for Mac", .none, nil)
        ]
        for (index, sample) in samples.enumerated() {
            let answer = try await AIClient.shared.jev(text: sample.0, key: key, provider: .jevOpenRouter)
            XCTAssertEqual(answer.usable ?? .none, sample.1, "Synthetic intent \(index)")
            if let expected = sample.2 { XCTAssertEqual(answer.content, expected, "Synthetic details \(index)") }
            if sample.1 == .email { XCTAssertEqual(answer.recipient, "Alex") }
            print("INTENT_LIVE sample=\(index) kind=\(answer.usable?.rawValue ?? "none") content_match=\(sample.2 == nil || answer.content == sample.2)")
        }
    }
}
