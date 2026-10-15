import AppKit
import SwiftUI
import XCTest
import ImageIO
import UniformTypeIdentifiers
@testable import Search

@MainActor
final class NewTabScreenshotTests: XCTestCase {
    override class func setUp() {
        setenv("SEARCH_PROBE", "tab-entry-\(getpid())", 1)
        super.setUp()
    }

    func testCaptureTabEntry() throws {
        guard let path = ProcessInfo.processInfo.environment["BROWSE_SCREENSHOT_DIR"] else {
            throw XCTSkip("Opt-in native fixture: Tests/TabEntryFixture/run.sh")
        }
        _ = NSApplication.shared
        let output = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let previousAppearance = NSApp.appearance
        defer { NSApp.appearance = previousAppearance }
        for dark in [false, true] {
            let browser = Browser(record: WindowRecord())
            let original = try XCTUnwrap(browser.active)
            original.restore(url: URL(string: "about:blank#fixture")!, title: "Fixture document")
            let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            NSApp.appearance = appearance
            let host = NSHostingView(rootView: VStack(spacing: 0) {
                TabBar(browser: browser)
                ZStack {
                    Palette.ground
                    VStack(alignment: .leading, spacing: 16) {
                        Text("The current page stays here").font(.largeTitle)
                        Text("New Tab uses the address field in the tab strip.")
                        Divider()
                        Text("Native tab-entry fixture · synthetic document background")
                            .foregroundStyle(Palette.muted)
                        Spacer()
                    }
                    .padding(80)
                    .foregroundStyle(Palette.ink)
                }
            }.background(Palette.ground).environment(\.colorScheme, dark ? .dark : .light))
            let window = NSWindow(contentRect: NSRect(x: 80, y: 80, width: 1440, height: 900),
                                  styleMask: .borderless, backing: .buffered, defer: false)
            window.appearance = appearance
            window.contentView = host
            browser.window = window
            window.orderFront(nil)
            defer {
                browser.cancelTabEdit()
                SiteCardPanel.hide()
                window.orderOut(nil)
                window.contentView = nil
                browser.window = nil
            }
            browser.newTab()
            spin()
            XCTAssertFalse(browser.fieldShowing)
            XCTAssertEqual(browser.activeID, original.id)
            XCTAssertNotEqual(browser.editingTab, original.id)
            XCTAssertEqual(browser.editingTab, browser.tabs.last?.id)
            let field = try XCTUnwrap(findField(host))
            XCTAssertEqual(field.accessibilityLabel(), "New tab address")
            let theme = dark ? "dark" : "light"
            try capture(window).write(to: output.appendingPathComponent("new-tab-empty-\(theme).png"))
            let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
            editor.insertText("goo", replacementRange: editor.selectedRange())
            spin()
            XCTAssertTrue(SiteCardPanel.suggestionsShown)
            XCTAssertEqual(browser.activeID, original.id)
            XCTAssertFalse(browser.fieldShowing)
            try capture(window).write(to: output.appendingPathComponent("new-tab-dropdown-\(theme).png"))
            if !dark {
                browser.escapeTabEdit()
                spin()
                var frames: [CGImage] = []
                for index in 0..<16 {
                    if index == 2 { browser.newTab() }
                    if index == 6 {
                        let entry = try XCTUnwrap(findField(host))
                        let editor = try XCTUnwrap(entry.currentEditor() as? NSTextView)
                        editor.insertText("goo", replacementRange: editor.selectedRange())
                    }
                    if index == 12 { browser.escapeTabEdit() }
                    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.035))
                    let source = try XCTUnwrap(CGImageSourceCreateWithData(try capture(window) as CFData, nil))
                    frames.append(try XCTUnwrap(CGImageSourceCreateThumbnailAtIndex(source, 0, [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceThumbnailMaxPixelSize: 1440
                    ] as CFDictionary)))
                }
                let file = output.appendingPathComponent("new-tab-dropdown-motion.gif")
                let gif = try XCTUnwrap(CGImageDestinationCreateWithURL(file as CFURL, UTType.gif.identifier as CFString, frames.count, nil))
                CGImageDestinationSetProperties(gif, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
                for frame in frames {
                    CGImageDestinationAddImage(gif, frame, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.1]] as CFDictionary)
                }
                XCTAssertTrue(CGImageDestinationFinalize(gif))
            }
        }
    }

    private func spin() { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.4)) }

    private func findField(_ view: NSView) -> NSTextField? {
        if let field = view as? NSTextField { return field }
        return view.subviews.lazy.compactMap(findField).first
    }

    private func capture(_ window: NSWindow) throws -> Data {
        let root = try XCTUnwrap(window.contentView)
        let image = NSImage(size: root.bounds.size)
        do {
            image.lockFocus()
            defer { image.unlockFocus() }
            // Include the real child suggestion panel in its native window position.
            for part in [window] + (window.childWindows ?? []) {
                let view = try XCTUnwrap(part.contentView)
                view.layoutSubtreeIfNeeded()
                let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
                view.cacheDisplay(in: view.bounds, to: bitmap)
                let rect = window.convertFromScreen(part.frame)
                NSGraphicsContext.saveGraphicsState()
                if part !== window {
                    // View caching omits the child window's layer corner mask.
                    let radius = view.layer?.cornerRadius ?? 0
                    let clip = NSBezierPath()
                    clip.move(to: NSPoint(x: rect.minX, y: rect.maxY))
                    clip.line(to: NSPoint(x: rect.maxX, y: rect.maxY))
                    clip.line(to: NSPoint(x: rect.maxX, y: rect.minY + radius))
                    clip.appendArc(from: NSPoint(x: rect.maxX, y: rect.minY), to: NSPoint(x: rect.maxX - radius, y: rect.minY), radius: radius)
                    clip.line(to: NSPoint(x: rect.minX + radius, y: rect.minY))
                    clip.appendArc(from: NSPoint(x: rect.minX, y: rect.minY), to: NSPoint(x: rect.minX, y: rect.minY + radius), radius: radius)
                    clip.close()
                    clip.addClip()
                }
                bitmap.draw(in: rect)
                NSGraphicsContext.restoreGraphicsState()
            }
        }
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiff))
        return try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
    }
}
