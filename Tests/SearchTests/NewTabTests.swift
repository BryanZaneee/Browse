import AppKit
import XCTest
@testable import Search

@MainActor
final class NewTabTests: XCTestCase {
    override class func setUp() {
        setenv("SEARCH_PROBE", "new-tab-\(getpid())", 1)
        super.setUp()
    }

    private func page(privateMode: Bool = false) -> (Browser, Tab) {
        _ = NSApplication.shared
        let browser = Browser(record: WindowRecord())
        if privateMode { browser.newShyTab() }
        let tab = browser.active!
        tab.go(to: URL(string: "about:blank#original")!)
        return (browser, tab)
    }

    func testComposeAndCancelNeverCreatesOrNavigatesATab() {
        let (browser, original) = page()
        let ids = browser.tabs.map(\.id)
        browser.newTab()
        browser.typed = "about:blank#not-submitted"
        XCTAssertTrue(browser.composingTab)
        XCTAssertTrue(browser.fieldShowing)
        XCTAssertEqual(browser.activeID, original.id)
        XCTAssertEqual(browser.tabs.map(\.id), ids)
        XCTAssertEqual(original.address?.fragment, "original")
        browser.dismiss()
        XCTAssertFalse(browser.composingTab)
        XCTAssertFalse(browser.fieldShowing)
        XCTAssertEqual(browser.tabs.map(\.id), ids)
        XCTAssertEqual(original.address?.fragment, "original")
    }

    func testRepeatedNewTabResetsTheComposerWithoutCreatingTabs() {
        let (browser, original) = page()
        let count = browser.tabs.count
        browser.newTab()
        browser.typed = "unfinished"
        browser.newTab()
        XCTAssertTrue(browser.composingTab)
        XCTAssertEqual(browser.typed, "")
        XCTAssertEqual(browser.activeID, original.id)
        XCTAssertEqual(browser.tabs.count, count)
    }

    func testCloseShortcutCancelsComposerWithoutClosingSource() {
        let (browser, original) = page()
        let ids = browser.tabs.map(\.id)
        browser.newTab()
        browser.closeFront()
        XCTAssertFalse(browser.composingTab)
        XCTAssertEqual(browser.activeID, original.id)
        XCTAssertEqual(browser.tabs.map(\.id), ids)
    }

    func testEmptySubmitKeepsComposerAndSource() {
        let (browser, original) = page()
        let count = browser.tabs.count
        browser.newTab()
        browser.submit()
        XCTAssertTrue(browser.composingTab)
        XCTAssertEqual(browser.tabs.count, count)
        XCTAssertEqual(browser.activeID, original.id)
    }

    func testNewTabAddressCommandKeepsComposerOpen() {
        let (browser, original) = page()
        let enabled = browser.prefs.commandBar
        defer { browser.prefs.commandBar = enabled }
        browser.prefs.commandBar = true
        browser.edit()
        browser.typed = "new tab"
        browser.submit()
        XCTAssertTrue(browser.composingTab)
        XCTAssertTrue(browser.fieldShowing)
        XCTAssertEqual(browser.activeID, original.id)
    }

    func testSubmitCreatesDestinationAndPreservesOriginal() {
        for privateMode in [false, true] {
            let (browser, original) = page(privateMode: privateMode)
            let count = browser.tabs.count
            browser.newTab()
            browser.typed = "about:blank#destination"
            browser.submit()
            XCTAssertEqual(browser.tabs.count, count + 1)
            XCTAssertNotEqual(browser.activeID, original.id)
            XCTAssertEqual(browser.active?.address?.fragment, "destination")
            XCTAssertEqual(browser.active?.shy, privateMode)
            XCTAssertEqual(original.address?.fragment, "original")
            XCTAssertFalse(browser.composingTab)
        }
    }

    func testSuggestionClickUsesANewTab() {
        let (browser, original) = page()
        browser.newTab()
        let url = URL(string: "about:blank#clicked")!
        browser.take(Suggestion(key: "Fixture", title: "", url: url, kind: .visited))
        XCTAssertNotEqual(browser.activeID, original.id)
        XCTAssertEqual(browser.active?.address, url)
        XCTAssertEqual(original.address?.fragment, "original")
    }

    func testSearchAndKeyboardSelectionUseANewTab() throws {
        let (browser, original) = page()
        browser.newTab()
        browser.typed = "browse fixture query"
        let index = try XCTUnwrap(browser.offers.firstIndex { $0.kind == .search })
        let url = browser.offers[index].url
        for _ in 0...index { browser.walk(1) }
        browser.submit()
        XCTAssertEqual(browser.active?.address, url)
        XCTAssertNotEqual(browser.activeID, original.id)
        XCTAssertEqual(original.address?.fragment, "original")
    }

    func testCommandReturnKeepsTheSourceInFront() {
        let (browser, original) = page()
        browser.newTab()
        browser.typed = "about:blank#background"
        browser.submit(aside: true)
        XCTAssertEqual(browser.activeID, original.id)
        XCTAssertEqual(browser.tabs.last?.address?.fragment, "background")
        XCTAssertFalse(browser.composingTab)
    }

    func testAddressEditAndSwitcherDoNotInheritNewTabIntent() {
        let (browser, original) = page()
        browser.newTab()
        browser.edit()
        XCTAssertFalse(browser.composingTab)
        browser.typed = "about:blank#edited"
        browser.submit()
        XCTAssertEqual(browser.activeID, original.id)
        XCTAssertEqual(original.address?.fragment, "edited")
        browser.newTab()
        browser.summon()
        XCTAssertFalse(browser.composingTab)
    }

    func testSelectingSourceCancelsComposerAndInternalBlankIsImmediate() {
        let (browser, original) = page()
        browser.newTab()
        browser.select(original)
        XCTAssertFalse(browser.fieldShowing)
        browser.newBlankTab()
        XCTAssertNotEqual(browser.activeID, original.id)
        XCTAssertTrue(browser.active?.isBlank == true)
        XCTAssertFalse(browser.composingTab)
    }
}
