import AppKit
import SwiftUI
import XCTest
@testable import Search

@MainActor
final class ClosedWindowTests: XCTestCase {
    func testRetirementReleasesWindowBrowserAndKeyHook() throws {
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
        var retired: [() -> Browser?] = []
        for cycle in 1...5 {
            weak var releasedBrowser: Browser?
            weak var releasedWindow: NSWindow?
            var identity: ObjectIdentifier?
            autoreleasepool {
                let browser = Browser(record: WindowRecord())
                releasedBrowser = browser
                retired.append { [weak browser] in browser }
                identity = ObjectIdentifier(browser)
                Browsers.open(browser, frame: NSRect(x: -10000, y: -10000, width: 800, height: 600))
                releasedWindow = browser.window
                browser.window?.orderOut(nil)
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
                XCTAssertNotNil(ContentView.keyHooks[ObjectIdentifier(browser)])
                browser.window?.close()
            }
            let deadline = Date(timeIntervalSinceNow: 3)
            while (releasedWindow != nil || releasedBrowser != nil), Date() < deadline {
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
            }
            let surviving = retired.enumerated().compactMap { $0.element() == nil ? nil : $0.offset + 1 }
            print("Lifecycle cycle \(cycle): surviving browser cycles \(surviving); registered=\(Browsers.all.contains { $0 === releasedBrowser }); front=\(releasedBrowser != nil && Front.shared.browser === releasedBrowser)")
            XCTAssertNil(ContentView.keyHooks[try XCTUnwrap(identity)])
            XCTAssertNil(releasedWindow, "retired window must not be retained by its view")
            XCTAssertNil(releasedBrowser, "cycle \(cycle): monitors and Lights must release the retired browser")
        }
    }
}
