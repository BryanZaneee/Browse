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
        browser.beginTabEdit(tab)
        let host = NSHostingView(rootView: TabAddressField(browser: browser).frame(width: 400, height: 24))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 24),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        spin()
        func find(_ view: NSView) -> NSTextField? {
            if let field = view as? NSTextField { return field }
            return view.subviews.lazy.compactMap(find).first
        }
        let field = try XCTUnwrap(find(host))
        window.makeFirstResponder(field)
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
            editor.insertText("tab-completion", replacementRange: editor.selectedRange())
            spin()
            XCTAssertEqual(field.stringValue, "tab-completion.example.test/Path?Q=One")
            XCTAssertEqual(editor.selectedRange(), NSRange(location: 14, length: (field.stringValue as NSString).length - 14))
        }
    }
}
