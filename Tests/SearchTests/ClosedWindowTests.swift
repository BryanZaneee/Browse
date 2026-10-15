import AppKit
import SwiftUI
import XCTest
@testable import Search

@MainActor
final class ClosedWindowTests: XCTestCase {
    func testRetirementReleasesWindowBrowserAndKeyHook() throws {
        try assertRetirementReleases(waitForSetup: true)
    }

    func testClosingBeforeQueuedSetupCannotRestoreCallbacks() throws {
        try assertRetirementReleases(waitForSetup: false)
    }

    func testRefreshedSceneCanSetUpBeforeRegistration() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let scene = SceneSlot.shared
        let previous = scene.browser
        scene.refresh()
        let browser = scene.browser
        XCTAssertFalse(Browsers.all.contains { $0 === browser })
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 800, height: 600),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer {
            ContentView.forget(browser)
            window.contentView = nil
            browser.window = nil
            // Retire the original scene fixture without retaining a last window.
            previous.extensionPopup = "lifecycle-fixture"
            previous.window = window
            Browsers.closing(window)
        }
        window.contentView = NSHostingView(rootView: ContentView(browser: browser))
        window.contentView?.layoutSubtreeIfNeeded()
        let deadline = Date(timeIntervalSinceNow: 3)
        while !window.titlebarAppearsTransparent, Date() < deadline {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
        }
        XCTAssertTrue(window.titlebarAppearsTransparent)
        XCTAssertTrue(browser.window === window)
        XCTAssertFalse(Browsers.all.contains { $0 === browser })
    }

    private func assertRetirementReleases(waitForSetup: Bool) throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let keeper = Browser(record: WindowRecord())
        let keeperWindow = NSWindow(contentRect: .zero, styleMask: [], backing: .buffered, defer: false)
        keeper.window = keeperWindow
        Browsers.register(keeper)
        // A retained last window is intentional; it supplies the open sibling here.
        keeper.shut = false
        defer {
            keeper.extensionPopup = "lifecycle-fixture"
            Browsers.closing(keeperWindow)
        }
        for cycle in 1...5 {
            weak var releasedBrowser: Browser?
            weak var releasedWindow: NSWindow?
            var identity: ObjectIdentifier?
            autoreleasepool {
                let browser = Browser(record: WindowRecord())
                releasedBrowser = browser
                identity = ObjectIdentifier(browser)
                Browsers.open(browser, frame: NSRect(x: -10000, y: -10000, width: 800, height: 600))
                releasedWindow = browser.window
                browser.window?.orderOut(nil)
                browser.window?.contentView?.layoutSubtreeIfNeeded()
                if waitForSetup {
                    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
                    XCTAssertNotNil(ContentView.keyHooks[ObjectIdentifier(browser)])
                }
                browser.window?.close()
            }
            let deadline = Date(timeIntervalSinceNow: 3)
            while (releasedWindow != nil || releasedBrowser != nil), Date() < deadline {
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
            }
            XCTAssertNil(ContentView.keyHooks[try XCTUnwrap(identity)])
            XCTAssertNil(releasedWindow, "retired window must not be retained by its view")
            XCTAssertNil(releasedBrowser, "cycle \(cycle): monitors and Lights must release the retired browser")
        }
    }
}
