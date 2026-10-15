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
        let host = NSHostingView(rootView: TabAddressField(browser: browser).frame(width: 400, height: 24).background(TabAddressSurface(browser: browser)))
        let window = NSWindow(contentRect: NSRect(x: -20000, y: -20000, width: 400, height: 24),
                              styleMask: .borderless, backing: .buffered, defer: false)
        let container = NSView(frame: window.contentLayoutRect)
        window.contentView = container
        host.frame = container.bounds
        container.addSubview(host)
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

    func testNewTabUsesTheNativeTabFieldAndCancelsWithSuggestions() throws {
        try withField { browser, field, editor in
            let original = try XCTUnwrap(browser.active)
            let address = original.address
            browser.newTab()
            spin()
            XCTAssertNotEqual(browser.editingTab, original.id)
            XCTAssertEqual(browser.editingTab, browser.tabs.last?.id)
            XCTAssertFalse(browser.fieldShowing)
            XCTAssertEqual(field.accessibilityLabel(), "New tab address")
            XCTAssertEqual(field.placeholderAttributedString?.string, "New tab address")
            editor.insertText("yout", replacementRange: editor.selectedRange())
            spin()
            XCTAssertEqual(field.stringValue, "youtube.com")
            XCTAssertTrue(SiteCardPanel.suggestionsShown)
            try key(editor, 53, "\u{1b}")
            XCTAssertNil(browser.editingTab)
            XCTAssertFalse(browser.composingTab)
            XCTAssertEqual(original.address, address)
        }
    }

    func testNewTabReturnOpensDestinationFromTheNativeTabField() throws {
        try withField { browser, field, editor in
            let original = try XCTUnwrap(browser.active)
            let address = original.address
            browser.newTab()
            spin()
            editor.insertText("data:text/html,new-tab", replacementRange: editor.selectedRange())
            try key(editor, 36, "\r")
            XCTAssertNotEqual(browser.activeID, original.id)
            XCTAssertEqual(browser.active?.address?.absoluteString, "data:text/html,new-tab")
            XCTAssertEqual(original.address, address)
            XCTAssertFalse(browser.composingTab)
        }
    }

    func testEscapeBeforeTheNativeEditorClaimsFocus() throws {
        let browser = Browser(record: WindowRecord())
        let tab = browser.open(URL(string: "about:blank")!, foreground: true)
        browser.beginTabEdit(tab)
        browser.changeTabDraft("yout")
        browser.escapeTabEdit()
        XCTAssertTrue(browser.tabOffers.isEmpty)
        XCTAssertNil(browser.tabEnding)
        XCTAssertEqual(browser.tabDraft, "yout")
        XCTAssertEqual(browser.editingTab, tab.id)
        browser.escapeTabEdit()
        XCTAssertNil(browser.editingTab)
    }

    func testCachedSurfaceIsRediscoveredAfterMovingOrDetaching() throws {
        try withField { browser, field, _ in
            let surface = try XCTUnwrap(TabAddressSurface.find(for: browser, field: field))
            let parent = try XCTUnwrap(surface.superview)
            XCTAssertTrue(TabAddressSurface.find(for: browser, field: field, reusing: surface) === surface)
            let replacement = TabAddressSurface.Surface(browser: browser)
            replacement.frame = surface.frame
            parent.addSubview(replacement)
            defer { replacement.removeFromSuperview() }
            let frame = surface.frame
            surface.setFrameOrigin(NSPoint(x: frame.minX + 10000, y: frame.minY))
            XCTAssertTrue(TabAddressSurface.find(for: browser, field: field, reusing: surface) === replacement)
            surface.frame = frame
            surface.removeFromSuperview()
            defer { parent.addSubview(surface) }
            XCTAssertTrue(TabAddressSurface.find(for: browser, field: field, reusing: surface) === replacement)
        }
    }

    func testSiteInformationOnlyOpensWhenRequested() throws {
        try withField { browser, field, _ in
            XCTAssertNotNil(field.currentEditor())
            XCTAssertFalse(SiteCardPanel.isShown)
            XCTAssertFalse(SiteCardPanel.suggestionsShown)
            let tab = try XCTUnwrap(browser.active)
            browser.beginTabEdit(tab, siteInformation: true)
            spin()
            spin()
            XCTAssertTrue(SiteCardPanel.isShown)
            let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
            editor.selectAll(nil)
            editor.insertText("yout", replacementRange: editor.selectedRange())
            spin()
            XCTAssertFalse(SiteCardPanel.isShown)
            XCTAssertTrue(SiteCardPanel.suggestionsShown)
            browser.beginTabEdit(tab)
            spin()
            spin()
            XCTAssertFalse(SiteCardPanel.isShown)
            XCTAssertFalse(SiteCardPanel.suggestionsShown)
        }
    }

    func testSuggestionRevealKeepsFocusAndRespectsReducedMotion() throws {
        try withField { browser, field, editor in
            editor.selectAll(nil)
            editor.insertText("yout", replacementRange: editor.selectedRange())
            spin()
            let panel = try XCTUnwrap(NSApp.windows.first {
                $0.identifier?.rawValue == "tab-address-suggestions" && $0.parent === field.window
            } as? NSPanel)
            let window = try XCTUnwrap(field.window)
            let spot = window.convertToScreen(field.convert(field.bounds, to: nil))
            panel.setFrameOrigin(NSPoint(x: spot.minX, y: spot.minY - panel.frame.height - 3))
            let frame = panel.frame
            let layer = try XCTUnwrap(panel.contentView?.layer)
            SiteCardPanel.reveal(panel, under: field, animated: true)
            let mask = try XCTUnwrap(layer.mask)
            XCTAssertEqual(mask.anchorPoint.y, 1)
            XCTAssertNotNil(mask.animation(forKey: "suggestions-unfold"))
            XCTAssertTrue(field.currentEditor() === editor)
            XCTAssertEqual(panel.frame, frame)
            editor.insertText("u", replacementRange: editor.selectedRange())
            spin()
            XCTAssertTrue(layer.mask === mask, "Typing must not restart the opening animation")
            SiteCardPanel.reveal(panel, under: field, animated: false)
            XCTAssertNil(layer.mask)
            XCTAssertNil(layer.animation(forKey: "suggestions-fade"))
            panel.setFrameOrigin(NSPoint(x: frame.minX, y: spot.maxY + 3))
            SiteCardPanel.reveal(panel, under: field, animated: true)
            XCTAssertEqual(layer.mask?.anchorPoint.y, 0, "An above-field popup unfolds upwards")
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.4))
            XCTAssertNil(layer.mask, "The settled popup must not clip later row changes")
            SiteCardPanel.reveal(panel, under: field, animated: true)
            browser.cancelTabEdit()
            spin()
            XCTAssertNil(panel.parent)
            XCTAssertNil(layer.mask)
            XCTAssertFalse(SiteCardPanel.suggestionsShown)
        }
    }

    func testBlurKeepsCompletionAndPlainDraftWithoutNavigating() throws {
        try withField { browser, field, editor in
            let window = try XCTUnwrap(field.window)
            let tab = try XCTUnwrap(browser.active)
            let address = tab.address
            editor.selectAll(nil)
            editor.insertText("yout", replacementRange: editor.selectedRange())
            spin()
            window.makeFirstResponder(nil)
            spin()
            XCTAssertEqual(tab.address, address)
            XCTAssertEqual(field.stringValue, "youtube.com")
            XCTAssertTrue(browser.tabEditParked)
            XCTAssertFalse(browser.tabAddressFocused)
            XCTAssertNil(field.currentEditor())
            XCTAssertFalse(SiteCardPanel.suggestionsShown)
            browser.beginTabEdit(tab)
            spin()
            XCTAssertEqual(field.stringValue, "youtube.com")
            let resumed = try XCTUnwrap(field.currentEditor() as? NSTextView)
            resumed.selectAll(nil)
            resumed.insertText("words not submitted", replacementRange: resumed.selectedRange())
            spin()
            window.makeFirstResponder(nil)
            spin()
            XCTAssertEqual(field.stringValue, "words not submitted")
            XCTAssertEqual(tab.address, address)
            XCTAssertTrue(browser.tabOffers.isEmpty)
            window.makeFirstResponder(field)
            spin()
            XCTAssertFalse(browser.tabEditParked)
            XCTAssertEqual(field.stringValue, "words not submitted")
        }
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

    func testAccessibilityDescribesKeyboardSelectionAndRename() throws {
        try withField { browser, field, editor in
            XCTAssertEqual(field.accessibilityLabel(), "Tab address")
            XCTAssertTrue(field.accessibilityHelp()?.contains("Up and Down") == true)
            editor.selectAll(nil)
            editor.insertText("yout", replacementRange: editor.selectedRange())
            spin()
            try key(editor, 125, "\u{f701}")
            let offer = try XCTUnwrap(browser.tabOffers.first)
            let description = try XCTUnwrap(field.accessibilityValueDescription())
            XCTAssertTrue(description.contains(offer.key))
            XCTAssertTrue(description.contains(offer.title))
            XCTAssertTrue(description.contains("suggestion 1 of \(browser.tabOffers.count)"))
            XCTAssertTrue(field.currentEditor() === editor)
            try key(editor, 48, "\t")
            XCTAssertNil(field.accessibilityValueDescription())
            browser.beginTabRename(try XCTUnwrap(browser.active))
            spin()
            XCTAssertEqual(field.accessibilityLabel(), "Tab name")
            XCTAssertNil(field.accessibilityHelp())
        }
    }

    func testMarkedTextIsNotCompletedOrSubmitted() throws {
        try withField { browser, field, editor in
            editor.selectAll(nil)
            editor.insertText("yout", replacementRange: editor.selectedRange())
            spin()
            XCTAssertTrue(SiteCardPanel.suggestionsShown)
            editor.selectAll(nil)
            editor.setMarkedText("にほん", selectedRange: NSRange(location: 3, length: 0), replacementRange: editor.selectedRange())
            spin()
            XCTAssertTrue(editor.hasMarkedText())
            XCTAssertEqual(field.stringValue, "にほん")
            XCTAssertTrue(browser.tabOffers.isEmpty)
            XCTAssertFalse(SiteCardPanel.suggestionsShown)
            let coordinator = try XCTUnwrap(field.delegate as? TabAddressField.Coordinator)
            for command in [#selector(NSResponder.insertNewline(_:)), #selector(NSResponder.cancelOperation(_:)),
                            #selector(NSResponder.insertTab(_:)), #selector(NSResponder.moveUp(_:)),
                            #selector(NSResponder.moveDown(_:)), #selector(NSResponder.deleteBackward(_:))] {
                XCTAssertFalse(coordinator.control(field, textView: editor, doCommandBy: command))
            }
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
            tab.go(to: URL(string: "data:text/html,changed")!)
            spin()
            XCTAssertNil(browser.editingTab)
            XCTAssertTrue(browser.tabOffers.isEmpty)
            browser.beginTabEdit(tab)
            browser.changeTabDraft("yout")
            NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: field.window)
            spin()
            XCTAssertTrue(browser.tabEditParked)
            XCTAssertTrue(browser.tabOffers.isEmpty)
        }
    }

    func testASecondLayoutFieldDoesNotStealTheNativeEditor() throws {
        try withField { browser, field, editor in
            let window = try XCTUnwrap(field.window)
            let copy = NSHostingView(rootView: TabAddressField(browser: browser).frame(width: 300, height: 24))
            copy.frame = NSRect(x: 0, y: 0, width: 300, height: 24)
            window.contentView?.addSubview(copy)
            defer { copy.removeFromSuperview() }
            copy.layoutSubtreeIfNeeded()
            spin()
            XCTAssertTrue(window.firstResponder === editor)
            editor.selectAll(nil)
            editor.insertText("yout", replacementRange: editor.selectedRange())
            spin()
            XCTAssertTrue(window.firstResponder === editor)
            XCTAssertEqual(field.stringValue, "youtube.com")
            XCTAssertEqual(editor.selectedRange(), NSRange(location: 4, length: 7))
        }
    }

    func testNativePasteUsesSelectionWithoutMovingMiddleCaret() throws {
        try withField { browser, field, editor in
            let board = NSPasteboard.withUniqueName()
            defer { board.releaseGlobally() }
            board.setString("https://paste.example.test/abc", forType: .string)
            editor.selectAll(nil)
            XCTAssertTrue(editor.readSelection(from: board))
            spin()
            editor.setSelectedRange(NSRange(location: 27, length: 0))
            board.clearContents()
            board.setString("😀", forType: .string)
            XCTAssertTrue(editor.readSelection(from: board))
            spin()
            XCTAssertEqual(editor.selectedRange(), NSRange(location: 29, length: 0))
            XCTAssertEqual(browser.tabDraft, field.stringValue)
            XCTAssertTrue(field.stringValue.contains("😀"))
        }
    }

    func testOmniboxCommandsStayOutOfTabSuggestions() throws {
        try withField { browser, _, _ in
            let enabled = browser.prefs.commandBar
            defer { browser.prefs.commandBar = enabled }
            browser.prefs.commandBar = true
            browser.typed = "settings"
            XCTAssertTrue(browser.offers.first?.kind.isCommand == true)
            browser.changeTabDraft("settings")
            XCTAssertFalse(browser.tabOffers.contains { $0.kind.isCommand })
            XCTAssertFalse(browser.tabOffers.isEmpty)
        }
    }

    func testTabAddressDoesNotUseOmniboxSiteChip() throws {
        try withField { browser, _, editor in
            browser.siteChip = try XCTUnwrap(SiteSearch.match("red"))
            defer { browser.siteChip = nil }
            editor.selectAll(nil)
            editor.insertText("data:text/html,tab-editor", replacementRange: editor.selectedRange())
            try key(editor, 36, "\r")
            XCTAssertEqual(browser.active?.address?.absoluteString, "data:text/html,tab-editor")
        }
    }

    func testReopeningAnEditReclaimsAReusedNativeField() throws {
        try withField { browser, field, _ in
            let tab = try XCTUnwrap(browser.active)
            browser.cancelTabEdit()
            field.window?.makeFirstResponder(nil)
            browser.beginTabEdit(tab)
            spin()
            let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
            XCTAssertEqual(editor.selectedRange(), NSRange(location: 0, length: (field.stringValue as NSString).length))
            XCTAssertEqual(browser.editingTab, tab.id)
        }
    }

}
