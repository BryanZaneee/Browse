import AppKit
import SwiftUI
import XCTest
@testable import Search

@MainActor
final class TabAddressTests: XCTestCase {
    override class func setUp() {
        setenv("SEARCH_PROBE", "tab-address-\(getpid())", 1)
        super.setUp()
    }

    private func withField(_ check: (Browser, NSTextField, NSTextView) throws -> Void) throws {
        _ = NSApplication.shared
        let browser = Browser(record: WindowRecord())
        let tab = browser.open(URL(string: "about:blank")!, foreground: true)
        spin()
        browser.beginTabEdit(tab)
        let host = NSHostingView(rootView: TabAddressField(browser: browser).frame(width: 400, height: 24))
        let window = NSWindow(contentRect: NSRect(x: -20000, y: -20000, width: 400, height: 24),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        spin()
        func find(_ view: NSView) -> NSTextField? {
            if let field = view as? NSTextField { return field }
            return view.subviews.lazy.compactMap(find).first
        }
        let field = try XCTUnwrap(find(host))
        if field.currentEditor() == nil { window.makeFirstResponder(field) }
        let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
        defer {
            browser.cancelTabEdit()
            window.makeFirstResponder(nil)
            window.contentView = nil
            SiteCardPanel.hide()
        }
        try check(browser, field, editor)
    }

    private func spin() {
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.08))
    }

    func testMiddleInsertionPreservesNativeCaret() throws {
        try withField { browser, field, editor in
            editor.selectAll(nil)
            editor.insertText("https://example.test/abc", replacementRange: editor.selectedRange())
            editor.setSelectedRange(NSRange(location: 22, length: 0))
            editor.insertText("X", replacementRange: editor.selectedRange())
            spin()
            XCTAssertEqual(field.stringValue, "https://example.test/aXbc")
            XCTAssertEqual(browser.tabDraft, field.stringValue)
            XCTAssertEqual(editor.selectedRange(), NSRange(location: 23, length: 0))
        }
    }

    func testHistorySuffixIsSelectedInNativeEditor() throws {
        try withField { browser, field, editor in
            let url = URL(string: "https://tab-completion.example.test/Path?Q=One")!
            browser.history.record(url, title: "Completion fixture")
            defer { browser.history.forget(History.identity(for: url)) }
            editor.selectAll(nil)
            editor.insertText("tab-completion.example.test/P", replacementRange: editor.selectedRange())
            spin()
            XCTAssertEqual(field.stringValue, "tab-completion.example.test/Path?Q=One")
            XCTAssertEqual(editor.selectedRange(), NSRange(location: 29, length: (field.stringValue as NSString).length - 29))
        }
    }
    private func key(_ editor: NSTextView, _ code: UInt16, _ characters: String) throws {
        let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: 0, windowNumber: editor.window?.windowNumber ?? 0, context: nil,
            characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code))
        editor.keyDown(with: event)
        spin()
    }

    func testDeletionTabAndEscapeThroughNativeKeys() throws {
        try withField { browser, field, editor in
            editor.selectAll(nil)
            editor.insertText("yout", replacementRange: editor.selectedRange())
            spin()
            XCTAssertEqual(field.stringValue, "youtube.com")
            try key(editor, 51, "\u{7f}")
            XCTAssertEqual(field.stringValue, "yout")
            XCTAssertEqual(editor.selectedRange(), NSRange(location: 4, length: 0))
            editor.insertText("u", replacementRange: editor.selectedRange())
            spin()
            try key(editor, 48, "\t")
            XCTAssertEqual(field.stringValue, "youtube.com")
            XCTAssertEqual(browser.tabDraft, "youtube.com")
            XCTAssertNotNil(browser.editingTab)
            XCTAssertTrue(browser.tabOffers.isEmpty)
            XCTAssertEqual(editor.selectedRange(), NSRange(location: 11, length: 0))
            editor.selectAll(nil)
            editor.insertText("yout", replacementRange: editor.selectedRange())
            spin()
            try key(editor, 53, "\u{1b}")
            XCTAssertEqual(field.stringValue, "yout")
            XCTAssertNotNil(browser.editingTab)
            XCTAssertTrue(browser.tabOffers.isEmpty)
            try key(editor, 53, "\u{1b}")
            XCTAssertNil(browser.editingTab)
        }
    }

    func testMiddleDeletionAndUnicodeSelection() throws {
        try withField { browser, field, editor in
            let url = URL(string: "https://unicode.example.test/😀/Résumé?Q=A")!
            browser.history.record(url, title: "Unicode")
            defer { browser.history.forget(History.identity(for: url)) }
            let prefix = "unicode.example.test/😀/R"
            editor.selectAll(nil)
            editor.insertText(prefix, replacementRange: editor.selectedRange())
            spin()
            XCTAssertEqual(editor.selectedRange().length, 0)
            XCTAssertEqual(editor.selectedRange().location, (prefix as NSString).length)
            editor.setSelectedRange(NSRange(location: 5, length: 0))
            try key(editor, 51, "\u{7f}")
            XCTAssertEqual(editor.selectedRange(), NSRange(location: 4, length: 0))
            XCTAssertTrue(field.stringValue.hasPrefix("unicde"))
            XCTAssertNil(browser.tabEnding)
        }
    }

    func testMarkedTextIsNotCompletedOrSubmitted() throws {
        try withField { browser, field, editor in
            editor.selectAll(nil)
            editor.setMarkedText("yout", selectedRange: NSRange(location: 4, length: 0), replacementRange: editor.selectedRange())
            spin()
            XCTAssertTrue(editor.hasMarkedText())
            XCTAssertEqual(field.stringValue, "yout")
            XCTAssertTrue(browser.tabOffers.isEmpty)
            let coordinator = try XCTUnwrap(field.delegate as? TabAddressField.Coordinator)
            XCTAssertFalse(coordinator.control(field, textView: editor, doCommandBy: #selector(NSResponder.insertNewline(_:))))
            XCTAssertNotNil(browser.editingTab)
            editor.insertText("youtube", replacementRange: editor.markedRange())
            spin()
            XCTAssertFalse(editor.hasMarkedText())
            XCTAssertEqual(field.stringValue, "youtube.com")
        }
    }

    func testSuggestionParityAndRenameIsolation() throws {
        try withField { browser, _, _ in
            for text in ["", "yout", "YOUT", "two words", "zzzz-no-match.example", "localhost:3210/A?Q=B"] {
                browser.changeTabDraft(text)
                XCTAssertEqual(browser.tabOffers, browser.addressSuggestions(for: text))
                XCTAssertEqual(browser.tabEnding, browser.history.completion(for: text, among: browser.tabOffers))
            }
            let tab = try XCTUnwrap(browser.active)
            browser.beginTabRename(tab)
            browser.changeTabDraft("yout")
            XCTAssertTrue(browser.tabOffers.isEmpty)
            XCTAssertNil(browser.tabEnding)
            browser.commitTabEdit()
            XCTAssertEqual(tab.name, "yout")
            XCTAssertEqual(tab.address?.absoluteString, "about:blank")
        }
    }

    func testStaleSuggestionCannotNavigateAfterSwitchOrCancel() throws {
        try withField { browser, _, editor in
            editor.selectAll(nil)
            editor.insertText("yout", replacementRange: editor.selectedRange())
            let tab = try XCTUnwrap(browser.active)
            let offer = try XCTUnwrap(browser.tabOffers.first)
            browser.cancelTabEdit()
            browser.takeTabSuggestion(offer, for: tab.id)
            XCTAssertEqual(tab.address?.absoluteString, "about:blank")
            browser.beginTabEdit(tab)
            browser.changeTabDraft("yout")
            let other = browser.open(URL(string: "about:blank")!, foreground: true)
            browser.takeTabSuggestion(offer, for: tab.id)
            XCTAssertNil(browser.editingTab)
            XCTAssertTrue(browser.tabOffers.isEmpty)
            XCTAssertEqual(other.address?.absoluteString, "about:blank")
            XCTAssertEqual(tab.address?.absoluteString, "about:blank")
        }
    }

    func testPasteUndoRedoAndRefocusKeepNativeEditing() throws {
        try withField { browser, field, editor in
            editor.allowsUndo = true
            editor.selectAll(nil)
            editor.insertText("https://edit.example.test/abc", replacementRange: editor.selectedRange())
            spin()
            editor.breakUndoCoalescing()
            editor.setSelectedRange(NSRange(location: 25, length: 0))
            editor.insertText("X", replacementRange: editor.selectedRange())
            spin()
            let changed = field.stringValue
            XCTAssertEqual(editor.selectedRange(), NSRange(location: 26, length: 0))
            let undo = try XCTUnwrap(editor.undoManager)
            XCTAssertTrue(undo.canUndo)
            XCTAssertTrue(editor.tryToPerform(NSSelectorFromString("undo:"), with: nil))
            spin()
            XCTAssertEqual(field.stringValue, "https://edit.example.test/abc")
            XCTAssertTrue(undo.canRedo)
            XCTAssertTrue(editor.tryToPerform(NSSelectorFromString("redo:"), with: nil))
            spin()
            XCTAssertEqual(field.stringValue, changed)
            field.window?.makeFirstResponder(field)
            spin()
            XCTAssertNotNil(browser.editingTab, "reclaiming the same editor must not commit a queued blur")
        }
    }

    func testUndoRedoOfInlineCompletion() throws {
        try withField { browser, field, editor in
            editor.allowsUndo = true
            editor.selectAll(nil)
            editor.insertText("yout", replacementRange: editor.selectedRange())
            spin()
            XCTAssertEqual(field.stringValue, "youtube.com")
            let undo = try XCTUnwrap(editor.undoManager)
            XCTAssertTrue(undo.canUndo)
            XCTAssertTrue(editor.tryToPerform(NSSelectorFromString("undo:"), with: nil))
            spin()
            XCTAssertEqual(field.stringValue, "about:blank")
            XCTAssertNil(browser.tabEnding)
            XCTAssertTrue(editor.tryToPerform(NSSelectorFromString("redo:"), with: nil))
            spin()
            XCTAssertEqual(field.stringValue, "youtube.com")
            XCTAssertNil(browser.tabEnding)
        }
    }

    func testNavigationAndWindowChangeDismissStaleSuggestions() throws {
        try withField { browser, field, editor in
            editor.selectAll(nil)
            editor.insertText("yout", replacementRange: editor.selectedRange())
            let tab = try XCTUnwrap(browser.active)
            tab.go(to: URL(string: "about:blank#changed")!)
            spin()
            XCTAssertNil(browser.editingTab)
            XCTAssertTrue(browser.tabOffers.isEmpty)
            browser.beginTabEdit(tab)
            browser.changeTabDraft("yout")
            NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: field.window)
            spin()
            XCTAssertNil(browser.editingTab)
            XCTAssertTrue(browser.tabOffers.isEmpty)
        }
    }

}
