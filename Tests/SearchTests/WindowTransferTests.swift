import AppKit
import WebKit
import XCTest
@testable import Search

@MainActor
final class WindowTransferTests: XCTestCase {
    private var browsers: [Browser] = []
    private var windows: [NSWindow] = []
    private var littleWindows: [LittleWindow] = []

    override func tearDown() {
        for little in littleWindows { little.close() }
        littleWindows = []
        for browser in browsers {
            browser.extensionPopup = "transfer-fixture"
            if let window = browser.window { Browsers.closing(window) }
            browser.tabs.forEach { $0.close() }
        }
        windows.forEach { $0.close() }
        windows = []
        browsers = []
        super.tearDown()
    }

    private func browser(space: UUID = Space.firstID) -> Browser {
        _ = NSApplication.shared
        let browser = Browser(record: WindowRecord(space: space))
        browser.spaceID = space
        let window = NSWindow(contentRect: NSRect(x: -20000 + windows.count * 1200, y: -20000, width: 900, height: 640),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.setFrame(NSRect(x: -20000 + windows.count * 1200, y: -20000, width: 900, height: 640), display: false)
        browser.window = window
        browsers.append(browser)
        windows.append(window)
        Browsers.register(browser)
        return browser
    }

    private func wait(_ predicate: () -> Bool) async throws {
        for _ in 0..<150 {
            if predicate() { return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("Timed out waiting for fixture")
    }

    private func dirty(_ tab: Tab) async throws {
        let web = tab.web
        let marker = "transfer-" + UUID().uuidString
        web.loadHTMLString("<title>\(marker)</title><textarea id='draft'>fixture draft</textarea>", baseURL: nil)
        // isLoading can still be false before this requested navigation starts.
        // Wait for this document, not the compact window's initial about:blank.
        for _ in 0..<150 {
            let revision = tab.navigationRevision
            let ready = try? await web.evaluateJavaScript("""
                document.title === '\(marker)' && document.readyState === 'complete' &&
                !!document.querySelector('#draft')
                """)
            if ready as? Bool == true, !web.isLoading, tab.navigationRevision == revision {
                // Exercise transfer decisions with a deterministic dirty report,
                // without OS-specific synthesis of trusted WebKit input events.
                _ = try await web.evaluateJavaScript("window.__officeForms = {unsaved: () => true}", in: nil, in: Web.world)
                if !web.isLoading, tab.navigationRevision == revision { return }
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("Requested dirty fixture did not finish loading")
    }

    private func tab(in browser: Browser, shy: Bool = false) async throws -> Tab {
        let tab = Tab(shy: shy, configuration: Web.configuration(shy: shy, space: browser.spaceID))
        browser.prepare(tab)
        browser.showRow(browser.tabs + [tab], active: tab.id)
        try await dirty(tab)
        return tab
    }

    func testCancelPreservesFormComposerAndSplitInBothWindows() async throws {
        let source = browser(), target = browser(space: UUID())
        let moving = try await tab(in: source)
        let partner = try await tab(in: source)
        source.prefs.splitView = true
        source.pair(moving, with: partner, onLeft: true)
        XCTAssertEqual(source.splits.count, 1)
        source.select(moving)
        source.newTab()
        source.tabDraft = "unfinished source address"
        target.newTab()
        target.tabDraft = "unfinished target address"
        let sourceIDs = source.tabs.map(\.id), targetIDs = target.tabs.map(\.id)
        let sourceEditing = source.editingTab, targetEditing = target.editingTab
        let web = moving.built
        var offered = false
        target.confirmWindowMove = { _ in offered = true } // Cancel: do not approve.
        source.moveToWindow(moving, target)
        try await wait { offered }
        XCTAssertEqual(source.tabs.map(\.id), sourceIDs)
        XCTAssertEqual(target.tabs.map(\.id), targetIDs)
        XCTAssertEqual(source.splits.count, 1)
        XCTAssertEqual(source.editingTab, sourceEditing)
        XCTAssertEqual(target.editingTab, targetEditing)
        XCTAssertEqual(source.tabDraft, "unfinished source address")
        XCTAssertEqual(target.tabDraft, "unfinished target address")
        XCTAssertTrue(moving.built === web)
        let text = try await moving.web.evaluateJavaScript("document.querySelector('textarea').value") as? String
        XCTAssertEqual(text, "fixture draft")
    }

    func testApprovedCrossStoreMoveDetachesOnlyMovedSplitMember() async throws {
        let source = browser(), target = browser(space: UUID())
        let moving = try await tab(in: source), partner = try await tab(in: source)
        source.prefs.splitView = true
        source.pair(moving, with: partner, onLeft: true)
        XCTAssertEqual(source.splits.count, 1)
        let web = moving.built
        var approve: (() -> Void)?
        target.confirmWindowMove = { approve = $0 }
        source.moveToWindow(moving, target)
        try await wait { approve != nil }
        approve?()
        XCTAssertFalse(source.tabs.contains { $0 === moving })
        XCTAssertTrue(source.tabs.contains { $0 === partner })
        XCTAssertTrue(target.tabs.contains { $0 === moving })
        XCTAssertTrue(source.splits.isEmpty)
        XCTAssertTrue(moving.store === Spaces.store(for: target.spaceID))
        XCTAssertFalse(moving.built === web)
    }

    func testSameStoreAndPrivateMovesKeepLiveViewsWithoutPrompt() async throws {
        for shy in [false, true] {
            let source = browser(), target = browser(space: shy ? UUID() : Space.firstID)
            let moving = try await tab(in: source, shy: shy)
            let web = moving.built, store = moving.store
            target.confirmWindowMove = { _ in XCTFail("Live transfer must not prompt") }
            source.moveToWindow(moving, target)
            XCTAssertTrue(target.tabs.contains { $0 === moving })
            XCTAssertTrue(moving.built === web)
            XCTAssertTrue(moving.store === store)
        }
    }

    func testChangedDestinationOrDocumentInvalidatesApproval() async throws {
        for change in 0..<8 {
            let source = browser(), target = browser(space: UUID())
            let moving = try await tab(in: source)
            var approve: (() -> Void)?
            target.confirmWindowMove = { approve = $0 }
            source.moveToWindow(moving, target)
            try await wait { approve != nil }
            switch change {
            case 0: target.shut = true
            case 1: target.spaceID = UUID()
            case 2: source.spaceID = UUID()
            case 3: moving.didCommit() // Same-URL reload: address equality is insufficient.
            case 4: source.newTab(); source.tabDraft = "newer source draft"
            case 5: target.newTab(); target.tabDraft = "newer destination draft"
            case 6: Spaces.sharing.insert(target.spaceID)
            default: source.shut = true
            }
            approve?()
            XCTAssertTrue(source.tabs.contains { $0 === moving })
            XCTAssertFalse(target.tabs.contains { $0 === moving })
        }
    }

    func testNavigationDuringDirtyQueryDoesNotMove() async throws {
        let source = browser(), target = browser(space: UUID())
        let moving = try await tab(in: source)
        target.confirmWindowMove = { _ in XCTFail("Stale query must not prompt") }
        source.moveToWindow(moving, target)
        moving.didCommit()
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertTrue(source.tabs.contains { $0 === moving })
        XCTAssertFalse(target.tabs.contains { $0 === moving })
    }

    func testDragUsesTheSamePreflight() async throws {
        let source = browser(), target = browser(space: UUID())
        let moving = try await tab(in: source)
        var offered = false
        target.confirmWindowMove = { _ in offered = true }
        let frame = try XCTUnwrap(target.window).frame
        XCTAssertTrue(source.dragOut(moving, at: NSPoint(x: frame.midX, y: frame.midY)))
        try await wait { offered }
        XCTAssertTrue(source.tabs.contains { $0 === moving })
        XCTAssertFalse(target.tabs.contains { $0 === moving })
    }

    func testCompactWindowCancelAndClosedSourcePreserveOwnership() async throws {
        let target = browser()
        Browsers.becameKey(target)
        LittleWindow.show(URL(string: "about:blank")!, for: target, front: false)
        let little = try XCTUnwrap(LittleWindow.all.last)
        littleWindows.append(little)
        try await dirty(little.tab)
        target.spaceID = UUID()
        var approve: (() -> Void)?
        target.confirmWindowMove = { approve = $0 }
        // Loading the compact fixture yields to AppKit's pending key-window
        // events. Select the destination at the action boundary, as Keep does.
        Browsers.becameKey(target)
        XCTAssertTrue(Browsers.front === target)
        XCTAssertFalse(little.tab.web.isLoading)
        let revision = little.tab.navigationRevision
        little.keep()
        try await wait { approve != nil }
        XCTAssertNotNil(approve, "Keep approval missing; revision \(revision) -> \(little.tab.navigationRevision), loading=\(little.tab.web.isLoading), intended front=\(Browsers.front === target)")
        XCTAssertTrue(LittleWindow.all.contains { $0 === little })
        XCTAssertFalse(target.tabs.contains { $0 === little.tab })
        little.close()
        approve?()
        XCTAssertFalse(target.tabs.contains { $0 === little.tab })
    }
    func testApprovedCompactMoveClosesOnlyAfterTransfer() async throws {
        let target = browser()
        Browsers.becameKey(target)
        LittleWindow.show(URL(string: "about:blank")!, for: target, front: false)
        let little = try XCTUnwrap(LittleWindow.all.last)
        littleWindows.append(little)
        try await dirty(little.tab)
        target.spaceID = UUID()
        var approve: (() -> Void)?
        target.confirmWindowMove = { approve = $0 }
        // Loading the compact fixture yields to AppKit's pending key-window
        // events. Select the destination at the action boundary, as Keep does.
        Browsers.becameKey(target)
        XCTAssertTrue(Browsers.front === target)
        XCTAssertFalse(little.tab.web.isLoading)
        let revision = little.tab.navigationRevision
        little.keep()
        try await wait { approve != nil }
        XCTAssertNotNil(approve, "Keep approval missing; revision \(revision) -> \(little.tab.navigationRevision), loading=\(little.tab.web.isLoading), intended front=\(Browsers.front === target)")
        approve?()
        XCTAssertFalse(LittleWindow.all.contains { $0 === little })
        XCTAssertTrue(target.tabs.contains { $0 === little.tab })
        XCTAssertTrue(little.tab.store === Spaces.store(for: target.spaceID))
    }

    func testNativeAlertCancelKeepsThePage() async throws {
        _ = NSApplication.shared
        let previous = NSApp.appearance
        defer { NSApp.appearance = previous }
        for dark in [false, true] {
            NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            let source = browser(), target = browser(space: UUID())
            Browsers.becameKey(source)
            source.window?.appearance = NSApp.appearance
            source.window?.orderFront(nil)
            let moving = try await tab(in: source)
            source.moveToWindow(moving, target)
            try await wait { source.window?.attachedSheet != nil }
            try await Task.sleep(nanoseconds: 350_000_000)
            let sheet = try XCTUnwrap(source.window?.attachedSheet)
            let content = try XCTUnwrap(sheet.contentView)
            content.layoutSubtreeIfNeeded()
            func buttons(_ view: NSView) -> [NSButton] {
                (view as? NSButton).map { [$0] } ?? view.subviews.flatMap(buttons)
            }
            let cancel = try XCTUnwrap(buttons(content).first { $0.title == "Cancel" })
            if let directory = ProcessInfo.processInfo.environment["BROWSE_MOVE_SCREENSHOTS"] {
                let bitmap = try XCTUnwrap(content.bitmapImageRepForCachingDisplay(in: content.bounds))
                content.cacheDisplay(in: content.bounds, to: bitmap)
                let image = NSImage(size: content.bounds.size)
                NSApp.effectiveAppearance.performAsCurrentDrawingAppearance {
                    image.lockFocus()
                    NSColor.windowBackgroundColor.setFill()
                    content.bounds.fill()
                    let foreground = NSImage(size: content.bounds.size)
                    foreground.addRepresentation(bitmap)
                    foreground.draw(in: content.bounds, from: .zero, operation: .sourceOver, fraction: 1)
                    image.unlockFocus()
                }
                let rendered = try XCTUnwrap(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
                let png = try XCTUnwrap(rendered.representation(using: .png, properties: [:]))
                let output = URL(fileURLWithPath: directory, isDirectory: true)
                try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
                try png.write(to: output.appendingPathComponent(dark ? "dark.png" : "light.png"))
            }
            let escape = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero,
                modifierFlags: [], timestamp: 0, windowNumber: sheet.windowNumber,
                context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}",
                isARepeat: false, keyCode: 53))
            XCTAssertTrue(cancel.performKeyEquivalent(with: escape))
            try await wait { source.window?.attachedSheet == nil }
            XCTAssertTrue(source.tabs.contains { $0 === moving })
            XCTAssertFalse(target.tabs.contains { $0 === moving })
        }
    }

}
