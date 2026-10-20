import AppKit
import SwiftUI
import XCTest
@testable import Search

@MainActor
final class TabShortcutHintTests: XCTestCase {
    override class func setUp() {
        setenv("SEARCH_PROBE", "tab-shortcut-hints-\(getpid())", 1)
        super.setUp()
    }

    func testDefaultAndPersistence() {
        let saved = Store.settings.object(forKey: "tabs.shortcuts")
        defer { Store.settings.set(saved, forKey: "tabs.shortcuts") }
        Store.settings.removeObject(forKey: "tabs.shortcuts")
        XCTAssertFalse(Preferences().showsTabShortcuts)
        let prefs = Preferences()
        prefs.showsTabShortcuts = true
        XCTAssertTrue(Preferences().showsTabShortcuts)
    }

    func testNumbersFollowVisibleTabsIncludingPinsGroupsAndSplits() {
        _ = NSApplication.shared
        let browser = Browser(record: WindowRecord())
        let prefs = browser.prefs
        let saved = (prefs.showsTabShortcuts, prefs.usesTabGroups, prefs.splitView)
        defer {
            browser.closeAll()
            prefs.showsTabShortcuts = saved.0
            prefs.usesTabGroups = saved.1
            prefs.splitView = saved.2
        }
        prefs.showsTabShortcuts = true
        prefs.usesTabGroups = false
        browser.commandHeld = true
        for count in 1...11 {
            if count > 1 { browser.newTab() }
            browser.tabs.last?.restore(url: URL(string: "about:blank#\(count)")!, title: "Tab \(count)")
            assertNumbers(browser)
        }
        browser.pin(browser.tabs[3])
        prefs.splitView = true
        let left = browser.tabs[5], right = browser.tabs[6]
        browser.pair(right, with: left, onLeft: false)
        XCTAssertNil(browser.tabShortcutNumbers[right.id])
        assertNumbers(browser)
        prefs.usesTabGroups = true
        let grouped = browser.tabs.filter { $0.pin == nil && $0.id != left.id && $0.id != right.id }.prefix(2)
        let group = browser.addTabGroup(containing: grouped.first!)
        browser.move(grouped.last!, toGroup: group)
        browser.select(browser.tabs.last!)
        browser.toggleTabGroup(group)
        for tab in grouped { XCTAssertNil(browser.tabShortcutNumbers[tab.id]) }
        assertNumbers(browser)
        browser.move(browser.tabs.last!, to: 1)
        assertNumbers(browser)
        browser.commandHeld = false
        XCTAssertTrue(browser.tabShortcutNumbers.isEmpty)
        browser.commandHeld = true
        prefs.showsTabShortcuts = false
        XCTAssertTrue(browser.tabShortcutNumbers.isEmpty)
    }

    func testCommandEventsAndFocusLoss() async throws {
        _ = NSApplication.shared
        let browser = Browser(record: WindowRecord())
        let prefs = browser.prefs
        let saved = (prefs.showsTabShortcuts, prefs.sidebar)
        prefs.showsTabShortcuts = true
        prefs.sidebar = true
        for number in 1...11 {
            if number > 1 { browser.newTab() }
            browser.tabs.last?.restore(url: URL(string: "about:blank#\(number)")!, title: "Tab \(number)")
        }
        let window = NSWindow(contentRect: NSRect(x: -20_000, y: -20_000, width: 900, height: 600),
                              styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: ContentView(browser: browser))
        window.orderFrontRegardless()
        let previousFront = Front.shared.browser
        Front.shared.set(browser)
        defer {
            Front.shared.set(previousFront)
            ContentView.forget(browser)
            window.contentView = nil
            window.close()
            browser.closeAll()
            prefs.showsTabShortcuts = saved.0
            prefs.sidebar = saved.1
        }
        try await settle()
        try await flags(.command, in: window)
        XCTAssertTrue(browser.commandHeld)
        XCTAssertEqual(browser.tabShortcutNumbers.count, 9)
        for (number, code, characters) in [(2, UInt16(19), "é"), (9, UInt16(25), "ç")] {
            let hinted = try XCTUnwrap(browser.tabShortcutNumbers.first { $0.value == number }?.key)
            let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero,
                modifierFlags: .command, timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, characters: characters, charactersIgnoringModifiers: characters,
                isARepeat: false, keyCode: code))
            XCTAssertNil(ContentView.keyHooks[ObjectIdentifier(browser)]?(event))
            XCTAssertEqual(browser.activeID, hinted, "The physical shortcut must select its hinted tab")
        }
        try await flags([], in: window)
        XCTAssertFalse(browser.commandHeld)
        try await flags(.command, in: window)
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
        XCTAssertFalse(browser.commandHeld)
        try await flags(.command, in: window)
        NotificationCenter.default.post(name: NSApplication.didResignActiveNotification, object: NSApp)
        XCTAssertFalse(browser.commandHeld)
        try await flags(.command, in: window)
        prefs.showsTabShortcuts = false
        XCTAssertTrue(browser.tabShortcutNumbers.isEmpty)
        try await flags(.command, in: window)
        XCTAssertFalse(browser.commandHeld)
    }

    private func assertNumbers(_ browser: Browser, file: StaticString = #filePath, line: UInt = #line) {
        let shown = browser.shownTabs
        for (index, tab) in shown.enumerated() {
            let expected = index < 8 ? index + 1 : (index == shown.count - 1 ? 9 : nil)
            XCTAssertEqual(browser.tabShortcutNumbers[tab.id], expected, file: file, line: line)
        }
    }

    private func flags(_ flags: NSEvent.ModifierFlags, in window: NSWindow) async throws {
        let event = try XCTUnwrap(NSEvent.keyEvent(with: .flagsChanged, location: .zero,
            modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "",
            isARepeat: false, keyCode: 55))
        NSApp.postEvent(event, atStart: false)
        if let queued = NSApp.nextEvent(matching: .flagsChanged, until: Date(timeIntervalSinceNow: 1), inMode: .default, dequeue: true) {
            NSApp.sendEvent(queued)
        }
        try await settle()
    }

    private func settle() async throws { try await Task.sleep(for: .milliseconds(250)) }
}
