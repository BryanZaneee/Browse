import AppKit
import SwiftUI
import ImageIO
import UniformTypeIdentifiers

@main
struct Fixture {
    @MainActor
    static func main() throws {
        _ = NSApplication.shared
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let before = CommandLine.arguments.last == "--before"
        let suggestions = [
            Suggestion(key: "example.test/guide", title: "Browse guide", url: URL(string: "https://example.test/guide")!, kind: .visited),
            Suggestion(key: "example.test/notes", title: "Project notes", url: URL(string: "https://example.test/notes")!, kind: .visited),
            Suggestion(key: "example", title: "Search the web", url: URL(string: "https://example.test/search?q=example")!, kind: .search)
        ]
        for dark in [false, true] {
            for over in [false, true] {
                let browser = Browser()
                browser.active = Browser.Tab(isBlank: !over)
                browser.typed = "example"
                let size = NSSize(width: 1440, height: 900)
                let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
                NSApp.appearance = appearance
                let host = NSHostingView(rootView: ZStack {
                    Palette.ground
                    if over {
                        VStack(alignment: .leading, spacing: 18) {
                            Text("A page you are reading").font(.largeTitle)
                            Text("Your current page stays here while you choose a new destination.")
                            Divider()
                            Text("Synthetic document · no browsing data or network access")
                                .foregroundStyle(Palette.muted)
                            Spacer()
                        }
                        .padding(100)
                        .foregroundStyle(Palette.ink)
                    }
                    Omnibox(browser: browser, over: over, fitted: over)
                }.environment(\.colorScheme, dark ? .dark : .light))
                let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: -20000, y: -20000), size: size), styleMask: .borderless, backing: .buffered, defer: false)
                window.appearance = appearance
                window.contentView = host
                host.frame = NSRect(origin: .zero, size: size)
                window.orderFront(nil)
                spin(0.2)
                let field = findField(host)!
                let originalFrame = field.convert(field.bounds, to: host)
                browser.offers = suggestions
                browser.picked = 0
                spin(0.25)
                let expandedFrame = field.convert(field.bounds, to: host)
                precondition(abs(originalFrame.minY - expandedFrame.minY) < 0.5, "Suggestions moved the address field")
                precondition(abs(originalFrame.minX - expandedFrame.minX) < 0.5)
                if !before {
                    precondition(field.accessibilityLabel() == "Search or enter address")
                    precondition(field.accessibilityHelp()?.contains("Up and Down") == true)
                }
                let name = "\(before ? "before" : "after")-\(over ? "composer" : "home")-\(dark ? "dark" : "light")"
                let bitmap = capture(host)
                try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name + ".png"))

                if !before && !dark && !over {
                    browser.offers = []
                    spin(0.25)
                    var frames: [CGImage] = []
                    for index in 0..<24 {
                        if index == 4 { browser.offers = suggestions }
                        if index == 16 { browser.offers = [] }
                        spin(1.0 / 30)
                        frames.append(capture(host).cgImage!)
                    }
                    let destination = CGImageDestinationCreateWithURL(output.appendingPathComponent("connected-search-motion.gif") as CFURL, UTType.gif.identifier as CFString, frames.count, nil)!
                    CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
                    for frame in frames {
                        CGImageDestinationAddImage(destination, frame, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1.0 / 30]] as CFDictionary)
                    }
                    precondition(CGImageDestinationFinalize(destination))
                }
                // Exercise the real native field delegate, without storage or WebKit.
                if !before {
                    browser.offers = suggestions
                    browser.picked = nil
                    window.makeFirstResponder(field)
                    let editor = field.currentEditor() as! NSTextView
                    let coordinator = field.delegate as! AddressField.Coordinator
                    precondition(coordinator.control(field, textView: editor, doCommandBy: #selector(NSResponder.moveDown(_:))))
                    precondition(browser.picked == 0)
                    precondition(coordinator.control(field, textView: editor, doCommandBy: #selector(NSResponder.insertNewline(_:))))
                    precondition(browser.opened == suggestions[0].url)
                    browser.picked = nil
                    spin(0.2)
                    let rect = field.convert(field.bounds, to: host)
                    // The second 34-point row is below field padding, divider and list inset.
                    let distance: CGFloat = 14 + 1 + 6 + 34 + 17
                    let point = NSPoint(x: rect.minX + 60, y: host.isFlipped ? rect.maxY + distance : rect.minY - distance)
                    let location = host.convert(point, to: nil)
                    for kind in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                        let event = NSEvent.mouseEvent(with: kind, location: location, modifierFlags: [],
                            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                            context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
                        window.sendEvent(event)
                        spin(0.05)
                    }
                    precondition(browser.opened == suggestions[1].url, "Expanded suggestion row did not receive a mouse click")
                    if over {
                        host.setFrameSize(NSSize(width: 420, height: 720))
                        spin(0.2)
                        let narrow = field.convert(field.bounds, to: host)
                        precondition(narrow.minX >= 14 && narrow.maxX <= 406, "Field overflows a narrow pane")
                    }
                }
                window.orderOut(nil)
                window.contentView = nil
            }
        }
        if before {
            print("Native baseline fixture captured; field-anchor checks passed")
        } else {
            print("Native omnibox fixture: field anchor, narrow layout, accessibility metadata, keyboard delegate and suggestion click checks passed; Reduce Motion = \(Motion.reduced)")
        }
    }

    @MainActor
    private static func spin(_ duration: TimeInterval) {
        RunLoop.main.run(until: Date(timeIntervalSinceNow: duration))
    }

    @MainActor
    private static func findField(_ view: NSView) -> NSTextField? {
        if let field = view as? NSTextField { return field }
        return view.subviews.lazy.compactMap(findField).first
    }

    @MainActor
    private static func capture(_ view: NSView) -> NSBitmapImageRep {
        view.layoutSubtreeIfNeeded()
        let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
        view.cacheDisplay(in: view.bounds, to: bitmap)
        return bitmap
    }
}
