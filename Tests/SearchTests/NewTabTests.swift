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

    func testDraftAppearsAtEndAndCancelRestoresTheOriginalTabs() {
        let (browser, original) = page()
        let ids = browser.tabs.map(\.id)
        browser.newTab()
        browser.changeTabDraft("about:blank#not-submitted")
        XCTAssertTrue(browser.composingTab)
        XCTAssertTrue(browser.tabAddressFocused)
        XCTAssertNotEqual(browser.editingTab, original.id)
        XCTAssertEqual(browser.editingTab, browser.tabs.last?.id)
        XCTAssertFalse(browser.fieldShowing)
        XCTAssertEqual(browser.activeID, original.id)
        XCTAssertEqual(browser.tabs.count, ids.count + 1)
        XCTAssertEqual(Array(browser.tabs.dropLast()).map(\.id), ids)
        XCTAssertEqual(original.address?.absoluteString, "about:blank#original")
        browser.dismiss()
        XCTAssertFalse(browser.composingTab)
        XCTAssertFalse(browser.fieldShowing)
        XCTAssertEqual(browser.tabs.map(\.id), ids)
        XCTAssertEqual(original.address?.absoluteString, "about:blank#original")
    }

    func testRepeatedNewTabReusesTheSameDraft() {
        let (browser, original) = page()
        let count = browser.tabs.count
        browser.newTab()
        let draft = browser.editingTab
        browser.changeTabDraft("unfinished")
        browser.newTab()
        XCTAssertTrue(browser.composingTab)
        XCTAssertEqual(browser.tabDraft, "")
        XCTAssertEqual(browser.activeID, original.id)
        XCTAssertEqual(browser.tabs.count, count + 1)
        XCTAssertEqual(browser.editingTab, draft)
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
        browser.commitTabEdit()
        XCTAssertTrue(browser.composingTab)
        XCTAssertEqual(browser.tabs.count, count + 1)
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
        XCTAssertFalse(browser.fieldShowing)
        XCTAssertEqual(browser.activeID, original.id)
    }

    func testBlurCancelsTheTabDropdownWithoutParkingADraft() {
        let (browser, original) = page()
        browser.newTab()
        browser.changeTabDraft("about:blank#unsubmitted")
        browser.finishTabEdit()
        XCTAssertFalse(browser.composingTab)
        XCTAssertNil(browser.editingTab)
        XCTAssertFalse(browser.tabEditParked)
        XCTAssertEqual(browser.activeID, original.id)
        XCTAssertEqual(original.address?.absoluteString, "about:blank#original")
    }

    func testNewTabOnHomeUsesTheTabFieldInsteadOfTheHomeField() {
        let browser = Browser(record: WindowRecord())
        let id = browser.activeID
        browser.newTab()
        XCTAssertTrue(browser.composingTab)
        XCTAssertTrue(browser.tabAddressFocused)
        XCTAssertFalse(browser.fieldShowing)
        XCTAssertNotEqual(browser.editingTab, id)
        XCTAssertEqual(browser.editingTab, browser.tabs.last?.id)
        XCTAssertEqual(browser.activeID, id)
        browser.escapeTabEdit()
        XCTAssertFalse(browser.composingTab)
        XCTAssertNil(browser.editingTab)
        XCTAssertTrue(browser.fieldShowing)
    }

    func testSubmitCreatesDestinationAndPreservesOriginal() throws {
        for privateMode in [false, true] {
            let (browser, original) = page(privateMode: privateMode)
            let count = browser.tabs.count
            browser.newTab()
            browser.changeTabDraft("about:blank#destination")
            browser.commitTabEdit()
            let destination = try XCTUnwrap(browser.active)
            XCTAssertEqual(browser.tabs.count, count + 1)
            XCTAssertNotEqual(browser.activeID, original.id)
            XCTAssertEqual(browser.active?.address?.absoluteString, "about:blank#destination")
            XCTAssertEqual(browser.active?.shy, privateMode)
            if privateMode {
                XCTAssertFalse(destination.store === original.store, "New private tabs keep their own ephemeral store")
            }
            XCTAssertEqual(original.address?.absoluteString, "about:blank#original")
            XCTAssertFalse(browser.composingTab)
        }
    }

    func testSuggestionClickUsesANewTab() throws {
        let (browser, original) = page()
        browser.newTab()
        browser.changeTabDraft("browse fixture query")
        let offer = try XCTUnwrap(browser.tabOffers.first)
        browser.takeTabSuggestion(offer, for: try XCTUnwrap(browser.editingTab))
        XCTAssertNotEqual(browser.activeID, original.id)
        XCTAssertEqual(browser.active?.address, offer.url)
        XCTAssertEqual(original.address?.absoluteString, "about:blank#original")
    }

    func testAnExistingBlankAndItsDraftStayUntouched() {
        let (browser, original) = page()
        browser.newBlankTab()
        let blank = browser.active!
        browser.typed = "unfinished address"
        browser.select(original)
        let count = browser.tabs.count
        browser.newTab()
        browser.dismiss()
        XCTAssertTrue(blank.isBlank)
        XCTAssertEqual(blank.draft, "unfinished address")
        XCTAssertEqual(browser.activeID, original.id)
        browser.newTab()
        let draft = browser.editingTab
        browser.changeTabDraft("about:blank#destination")
        browser.commitTabEdit()
        XCTAssertEqual(browser.tabs.count, count + 1)
        XCTAssertEqual(browser.activeID, draft)
        XCTAssertTrue(blank.isBlank)
        XCTAssertEqual(blank.draft, "unfinished address")
    }

    func testSelectingTheDraftKeepsTheOriginalPageVisible() throws {
        let (browser, original) = page()
        browser.newTab()
        let draft = try XCTUnwrap(browser.tabs.last)
        XCTAssertNotEqual(draft.id, original.id)
        browser.select(draft)
        XCTAssertTrue(browser.composingTab)
        XCTAssertEqual(browser.editingTab, draft.id)
        XCTAssertEqual(browser.activeID, original.id)
        XCTAssertFalse(browser.fieldShowing)
    }

    func testClosingTheDraftCreatesNoClosedTabHistory() throws {
        let (browser, original) = page()
        let count = browser.tabs.count
        let ghosts = browser.ghosts.count
        browser.newTab()
        let draft = try XCTUnwrap(browser.tabs.last)
        browser.close(draft)
        XCTAssertEqual(browser.tabs.count, count)
        XCTAssertEqual(browser.ghosts.count, ghosts)
        XCTAssertEqual(browser.activeID, original.id)
        XCTAssertFalse(browser.composingTab)
    }

    func testInternalBlankCreationReplacesOnlyTheUnsubmittedDraft() {
        let (browser, original) = page()
        browser.newTab()
        let draft = browser.editingTab
        browser.newBlankTab()
        XCTAssertFalse(browser.composingTab)
        XCTAssertNil(browser.editingTab)
        XCTAssertFalse(browser.tabs.contains { $0.id == draft })
        XCTAssertEqual(browser.tabs.count, 2)
        XCTAssertTrue(browser.active?.isBlank == true)
        XCTAssertTrue(browser.tabs.contains { $0.id == original.id })
    }

    func testClosingTheSourceDiscardsTheUnsubmittedDraft() {
        let (browser, original) = page()
        browser.newTab()
        let draft = browser.editingTab
        browser.close(original)
        XCTAssertFalse(browser.composingTab)
        XCTAssertNil(browser.editingTab)
        XCTAssertFalse(browser.tabs.contains { $0.id == draft })
        XCTAssertTrue(browser.active?.isBlank == true)
    }

    func testAnUnsubmittedDraftCannotMoveToAnotherWindow() throws {
        let (browser, original) = page()
        let destination = Browser(record: WindowRecord())
        let count = destination.tabs.count
        browser.newTab()
        let draft = try XCTUnwrap(browser.tabs.last)
        browser.moveToWindow(draft, destination)
        XCTAssertEqual(destination.tabs.count, count)
        XCTAssertTrue(browser.composingTab)
        XCTAssertEqual(browser.activeID, original.id)
        XCTAssertEqual(browser.editingTab, draft.id)
    }

    func testMovingTheSourceToAnotherSpaceCancelsItsDraft() {
        let (browser, original) = page(privateMode: true)
        let enabled = browser.prefs.usesSpaces
        defer { browser.prefs.usesSpaces = enabled }
        browser.prefs.usesSpaces = true
        let destination = Space(id: UUID(), name: "Fixture", colour: 0)
        browser.spaces.append(destination)
        browser.newTab()
        let draft = browser.editingTab
        browser.move(original, toSpace: destination.id)
        XCTAssertFalse(browser.composingTab)
        XCTAssertNil(browser.editingTab)
        XCTAssertFalse(browser.tabs.contains { $0.id == draft || $0.id == original.id })
        XCTAssertNotEqual(browser.activeID, original.id)
        XCTAssertEqual(browser.parked[destination.id]?.tabs.first?.id, original.id)
    }

    func testHomeAddressDraftSurvivesNewTabCancellation() {
        let browser = Browser(record: WindowRecord())
        browser.typed = "unfinished address"
        browser.newTab()
        browser.escapeTabEdit()
        XCTAssertEqual(browser.typed, "unfinished address")
        XCTAssertTrue(browser.fieldShowing)
    }

    func testPendingDraftCannotSplitOrLeaveARenameForARemovedTab() throws {
        let (browser, original) = page()
        let enabled = browser.prefs.splitView
        defer { browser.prefs.splitView = enabled }
        browser.prefs.splitView = true
        browser.newTab()
        let draft = try XCTUnwrap(browser.tabs.last)
        browser.pair(draft, with: original, onLeft: false)
        XCTAssertTrue(browser.splits.isEmpty)
        XCTAssertEqual(browser.activeID, original.id)
        XCTAssertTrue(browser.composingTab)
        browser.beginTabRename(draft)
        XCTAssertNil(browser.editingTab)
        XCTAssertFalse(browser.composingTab)
        XCTAssertFalse(browser.tabs.contains { $0.id == draft.id })
        XCTAssertEqual(browser.activeID, original.id)
    }

    func testSearchAndKeyboardSelectionUseANewTab() throws {
        let (browser, original) = page()
        browser.newTab()
        browser.changeTabDraft("browse fixture query")
        let index = try XCTUnwrap(browser.tabOffers.firstIndex { $0.kind == .search })
        let url = browser.tabOffers[index].url
        for _ in 0...index { browser.walkTabSuggestions(1) }
        browser.commitTabEdit()
        XCTAssertEqual(browser.active?.address, url)
        XCTAssertNotEqual(browser.activeID, original.id)
        XCTAssertEqual(original.address?.absoluteString, "about:blank#original")
    }

    func testCommandReturnKeepsTheSourceInFront() {
        let (browser, original) = page()
        browser.newTab()
        browser.changeTabDraft("about:blank#background")
        browser.commitTabEdit(aside: true)
        XCTAssertEqual(browser.activeID, original.id)
        XCTAssertEqual(browser.tabs.last?.address?.absoluteString, "about:blank#background")
        XCTAssertFalse(browser.composingTab)
    }

    func testBackgroundSubmissionPreservesTheHomeAddressDraft() {
        let browser = Browser(record: WindowRecord())
        let original = browser.activeID
        browser.typed = "unfinished address"
        browser.newTab()
        browser.changeTabDraft("about:blank#background")
        browser.commitTabEdit(aside: true)
        XCTAssertEqual(browser.activeID, original)
        XCTAssertEqual(browser.typed, "unfinished address")
        XCTAssertTrue(browser.fieldShowing)
        XCTAssertEqual(browser.tabs.last?.address?.absoluteString, "about:blank#background")
    }

    func testAddressEditAndSwitcherDoNotInheritNewTabIntent() {
        let (browser, original) = page()
        browser.newTab()
        browser.edit()
        XCTAssertFalse(browser.composingTab)
        browser.typed = "about:blank#edited"
        browser.submit()
        XCTAssertEqual(browser.activeID, original.id)
        XCTAssertEqual(original.address?.absoluteString, "about:blank#edited")
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
