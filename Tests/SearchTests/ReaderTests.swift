import AppKit
import WebKit
import SwiftUI
import XCTest
@testable import Search

@MainActor
final class ReaderTests: XCTestCase {
    private var views: [WKWebView] = []
    private var tabs: [Search.Tab] = []
    private var folders: [URL] = []

    override func tearDown() {
        views.forEach { $0.stopLoading(); $0.removeFromSuperview() }
        views = []
        tabs.forEach { $0.close() }; tabs = []
        folders.forEach { try? FileManager.default.removeItem(at: $0) }; folders = []
        super.tearDown()
    }

    private func page(_ extra: String = "") async throws -> WKWebView {
        _ = NSApplication.shared
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 900, height: 900), configuration: configuration)
        views.append(web)
        let prose = String(repeating: "This synthetic article explains the local reader fixture and its deliberately ordinary paragraphs. ", count: 5)
        // Resource policy remains in the document head after reader extraction.
        // No fixture can fetch external frames, images, fonts, scripts or media.
        let marker = "reader-" + UUID().uuidString
        web.loadHTMLString("""
        <!doctype html><meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; img-src data:">
        <title>\(marker)</title><h1>A local article</h1>
        <article><p>\(prose)</p><p>\(prose)</p>\(extra)</article>
        """, baseURL: URL(string: "https://reader.example.test/article"))
        for _ in 0..<250 {
            if (try? await web.evaluateJavaScript("document.title === '\(marker)' && document.readyState === 'complete' && document.querySelectorAll('article p').length >= 2")) as? Bool == true, !web.isLoading { return web }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("Local article did not load")
        throw NSError(domain: "ReaderFixture", code: 1)
    }

    private func isolated(_ script: String, in web: WKWebView) async throws -> Any {
        try await withCheckedThrowingContinuation { continuation in
            web.evaluateJavaScript(script, in: nil, in: Web.world) { result in
                continuation.resume(with: result)
            }
        }
    }

    private func read(_ web: WKWebView, look: Look = .system) async throws {
        let result = try await isolated(Reader.apply(look) + Reader.script, in: web)
        XCTAssertEqual(result as? String, "read")
    }

    func testRejectsDeceptiveFramesAndBoundsApprovedEmbeds() async throws {
        let bad = ["https://youtube.com.evil.test/embed/x", "https://evil.test/youtube.com/embed/x",
                   "https://www.youtube.com/watch?v=x", "http://www.youtube.com/embed/x",
                   "https://user@www.youtube.com/embed/x", "https://www.youtube.com:444/embed/x"]
        let extra = bad.map { "<figure><iframe src='\($0)'></iframe></figure>" }.joined()
            + String(repeating: "<iframe data-src='https://www.youtube.com/embed/fixture?autoplay=1' srcdoc='arbitrary content'></iframe>", count: 12)
        let web = try await page(extra)
        try await read(web)
        let result = try await web.evaluateJavaScript("""
        Array.from(document.querySelectorAll('iframe')).every(f =>
          f.src === 'https://www.youtube.com/embed/fixture' && !f.hasAttribute('srcdoc') &&
          f.loading === 'lazy' && f.getAttribute('allow').includes("autoplay 'none'"))
        """)
        XCTAssertEqual(result as? Bool, true)
        let count = try await web.evaluateJavaScript("document.querySelectorAll('iframe').length")
        XCTAssertEqual(count as? Int, 8)
    }

    func testMediaRequiresInteractionAndCopiedHandlersAreRemoved() async throws {
        let web = try await page(String(repeating: "<video autoplay loop preload='auto' onplay='bad()' src='https://reader.example.test/movie'></video>", count: 20)
            + "<img src='https://reader.example.test/photo' onerror='bad()'><p onclick='bad()'>Caption</p>")
        try await read(web)
        let result = try await web.evaluateJavaScript("""
        document.querySelectorAll('video').length === 16 &&
        Array.from(document.querySelectorAll('video')).every(v => !v.autoplay && !v.loop && v.preload === 'none' && v.controls && v.paused) &&
        !document.querySelector('[onclick],[onplay],[onerror]') && document.querySelector('img').loading === 'lazy'
        """)
        XCTAssertEqual(result as? Bool, true)
    }

    func testArticleKeepsAddressLinksAndFindableText() async throws {
        let web = try await page("<a href='/related'>Related fixture</a><h1>A local article</h1>")
        let before = try await web.evaluateJavaScript("location.href") as? String
        try await read(web)
        let after = try await web.evaluateJavaScript("location.href") as? String
        XCTAssertEqual(before, after)
        let link = try await web.evaluateJavaScript("document.querySelector('a').href") as? String
        XCTAssertEqual(link, "https://reader.example.test/related")
        let headings = try await web.evaluateJavaScript("document.querySelectorAll('h1').length") as? Int
        XCTAssertEqual(headings, 1)
        let found = try await web.find("synthetic article", configuration: WKFindConfiguration())
        XCTAssertTrue(found.matchFound)
    }

    func testTwoArticlesKeepIndependentExplicitThemes() async throws {
        let left = try await page(), right = try await page()
        try await read(left, look: .light)
        try await read(right, look: .dark)
        let light = try await left.evaluateJavaScript("getComputedStyle(document.body).backgroundColor") as? String
        let dark = try await right.evaluateJavaScript("getComputedStyle(document.body).backgroundColor") as? String
        XCTAssertEqual(light, "rgb(255, 255, 255)")
        XCTAssertEqual(dark, "rgb(28, 28, 28)")
        _ = try await right.evaluateJavaScript(Reader.apply(.light))
        let unchanged = try await left.evaluateJavaScript("document.documentElement.getAttribute('data-office-look')") as? String
        XCTAssertEqual(unchanged, "light")
    }

    func testSystemThemeTracksNativeWindowAppearance() async throws {
        let web = try await page()
        let window = NSWindow(contentRect: web.bounds, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.setFrameOrigin(NSPoint(x: -20000, y: -20000))
        window.contentView = web
        window.orderFront(nil)
        defer { window.close() }
        try await read(web)
        for (appearance, expected) in [(NSAppearance.Name.aqua, "rgb(255, 255, 255)"), (.darkAqua, "rgb(28, 28, 28)")] {
            window.appearance = NSAppearance(named: appearance)
            var actual: String?
            for _ in 0..<100 {
                actual = try await web.evaluateJavaScript("getComputedStyle(document.body).backgroundColor") as? String
                if actual == expected { break }
                try await Task.sleep(nanoseconds: 20_000_000)
            }
            XCTAssertEqual(actual, expected)
        }
    }


    private func waitForDocument(_ web: WKWebView, title: String) async throws {
        for _ in 0..<250 {
            let current = try? await web.evaluateJavaScript("document.title") as? String
            let complete = try? await web.evaluateJavaScript("document.readyState === 'complete'") as? Bool
            if current == title, complete == true, !web.isLoading { return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("Expected completed document: \(title)")
        throw NSError(domain: "ReaderFixture", code: 2)
    }

    private func readerTab(media: Bool = false) async throws -> (Browser, Search.Tab, URL) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("browse-reader-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        folders.append(folder)
        let prose = String(repeating: "Local reader navigation fixture text. ", count: 24)
        let article = folder.appendingPathComponent("article.html")
        if media {
            let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/PictureInPicture/landscape.mp4")
            try FileManager.default.copyItem(at: source, to: folder.appendingPathComponent("landscape.mp4"))
        }
        let movie = media ? "<video id='movie' muted autoplay loop playsinline src='landscape.mp4'></video>" : ""
        try "<meta http-equiv='Content-Security-Policy' content=\"default-src 'none'; style-src 'unsafe-inline'; media-src file:\"><title>Reader navigation fixture</title><h1>Local navigation</h1><article><p>\(prose)</p><p>\(prose)</p><textarea id='draft'>Synthetic draft</textarea><a id='next' href='next.html'>Next fixture</a>\(movie)</article>".write(to: article, atomically: true, encoding: .utf8)
        try "<title>Next navigation fixture</title><p>Another local page</p>".write(to: folder.appendingPathComponent("next.html"), atomically: true, encoding: .utf8)
        let configuration = Web.configuration(shy: true)
        if media { configuration.mediaTypesRequiringUserActionForPlayback = [] }
        let tab = Tab(shy: true, configuration: configuration)
        tabs.append(tab)
        let browser = Browser(record: WindowRecord(space: Space.firstID))
        browser.prepare(tab)
        browser.showRow([tab], active: tab.id)
        tab.go(to: article)
        try await waitForDocument(tab.web, title: "Reader navigation fixture")
        return (browser, tab, article)
    }

    func testTabReaderStateClearsOnCommittedNavigation() async throws {
        let (browser, tab, article) = try await readerTab()
        defer { withExtendedLifetime(browser) {} }
        XCTAssertEqual(tab.address, article)
        let success = await withCheckedContinuation { continuation in
            tab.toggleReader { continuation.resume(returning: $0) }
        }
        XCTAssertTrue(success)
        XCTAssertTrue(tab.reader)
        XCTAssertEqual(tab.address, article)
        tab.readerLook = .dark
        for _ in 0..<100 {
            if (try? await tab.web.evaluateJavaScript("document.documentElement.getAttribute('data-office-look')")) as? String == "dark" { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        let look = try await tab.web.evaluateJavaScript("document.documentElement.getAttribute('data-office-look')") as? String
        XCTAssertEqual(look, "dark")
        // A page-originated navigation bypasses Tab.go; didCommit must clear it.
        tab.web.loadHTMLString("<title>Next local page</title><p>Next page</p>", baseURL: nil)
        for _ in 0..<250 {
            if !tab.reader && !tab.web.isLoading { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertFalse(tab.reader)
    }


    func testCaptureNativeReaderFixtures() async throws {
        guard let directory = ProcessInfo.processInfo.environment["BROWSE_READER_SCREENSHOTS"] else {
            throw XCTSkip("Set BROWSE_READER_SCREENSHOTS for reproducible native WebKit captures")
        }
        let output = URL(fileURLWithPath: directory, isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let web = try await page("<figure><svg width='400' height='100' viewBox='0 0 400 100'><rect width='400' height='100' fill='#36719b'/><circle cx='200' cy='50' r='30' fill='#e4b86a'/></svg><figcaption>A synthetic chart, drawn locally.</figcaption></figure>")
        let window = NSWindow(contentRect: web.bounds, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.setFrameOrigin(NSPoint(x: -20000, y: -20000))
        window.contentView = web
        window.orderFront(nil)
        defer { window.close() }
        for name in ["before", "light", "dark"] {
            if name != "before" { try await read(web, look: name == "dark" ? .dark : .light) }
            try await Task.sleep(nanoseconds: 300_000_000)
            let snapshot = try await web.takeSnapshot(configuration: nil)
            let bitmap = try XCTUnwrap(snapshot.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
            let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: output.appendingPathComponent(name + ".png"))
        }
    }


    func testDirtyReaderEntryCancelApproveAndNavigationRace() async throws {
        let (browser, tab, article) = try await readerTab()
        _ = try await isolated("window.__officeForms = {unsaved: () => true}; true", in: tab.web)
        var approve: (() -> Void)?
        browser.confirmReader = { approve = $0 }
        browser.toggleReader()
        for _ in 0..<100 {
            if approve != nil { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertNotNil(approve)
        XCTAssertFalse(tab.reader)
        let draft = try await tab.web.evaluateJavaScript("document.querySelector('textarea').value") as? String
        XCTAssertEqual(draft, "Synthetic draft")
        // A confirmation for the prior document cannot transform its successor.
        tab.web.loadHTMLString("<title>Another document</title><p>Keep this page</p>", baseURL: nil)
        for _ in 0..<100 {
            if (try? await tab.web.evaluateJavaScript("document.title === 'Another document' && document.readyState === 'complete'")) as? Bool == true, !tab.web.isLoading { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        approve?()
        XCTAssertFalse(tab.reader)
        tab.go(to: article)
        for _ in 0..<100 {
            if (try? await tab.web.evaluateJavaScript("document.title === 'Reader navigation fixture' && document.readyState === 'complete'")) as? Bool == true, !tab.web.isLoading { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        _ = try await isolated("window.__officeForms = {unsaved: () => true}; true", in: tab.web)
        approve = nil
        browser.toggleReader()
        for _ in 0..<100 {
            if approve != nil { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertNotNil(approve)
        approve?()
        for _ in 0..<100 {
            if tab.reader { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertTrue(tab.reader)
    }


    func testSplitTabsKeepTheirReaderChoicesWhenSelectedAgain() async throws {
        let (browser, left, article) = try await readerTab()
        let right = Tab(shy: true)
        tabs.append(right)
        browser.prepare(right)
        browser.showRow([left, right], active: left.id)
        let previousSplit = browser.prefs.splitView
        defer { browser.prefs.splitView = previousSplit }
        browser.prefs.splitView = true
        browser.pair(left, with: right, onLeft: true)
        right.go(to: article)
        try await waitForDocument(right.web, title: "Reader navigation fixture")
        left.readerLook = .light
        right.readerLook = .dark
        for tab in [left, right] {
            let success = await withCheckedContinuation { continuation in
                tab.toggleReader { continuation.resume(returning: $0) }
            }
            XCTAssertTrue(success)
        }
        browser.select(right)
        browser.select(left)
        XCTAssertEqual(browser.splits.count, 1)
        XCTAssertTrue(left.reader && right.reader)
        XCTAssertEqual(left.readerLook, .light)
        XCTAssertEqual(right.readerLook, .dark)
        let leftLook = try await left.web.evaluateJavaScript("document.documentElement.getAttribute('data-office-look')") as? String
        let rightLook = try await right.web.evaluateJavaScript("document.documentElement.getAttribute('data-office-look')") as? String
        XCTAssertEqual(leftLook, "light")
        XCTAssertEqual(rightLook, "dark")
    }


    func testRetainsArticleImageCaptionAndBylineWithoutPlayerControls() async throws {
        let web = try await page("<figure><button><img loading='lazy' data-src='https://reader.example.test/photo'></button><figcaption>Local photo credit</figcaption></figure><div class='newsletter'><p>Unrelated subscription</p></div>")
        _ = try await web.evaluateJavaScript("document.querySelector('article').insertAdjacentHTML('beforebegin', '<div class=byline>Fixture author</div>')")
        try await read(web)
        let result = try await web.evaluateJavaScript("""
        document.querySelector('figure img').src === 'https://reader.example.test/photo' &&
        document.querySelector('figcaption').textContent === 'Local photo credit' &&
        document.querySelector('.office-above').textContent === 'Fixture author' &&
        !document.querySelector('button,.newsletter')
        """)
        XCTAssertEqual(result as? Bool, true)
    }


    func testReaderLinkBackForwardAndExitReload() async throws {
        let (browser, tab, article) = try await readerTab()
        defer { withExtendedLifetime(browser) {} }
        func toggle() async -> Bool {
            await withCheckedContinuation { continuation in
                tab.toggleReader { continuation.resume(returning: $0) }
            }
        }
        let entered = await toggle()
        XCTAssertTrue(entered)
        _ = try await tab.web.evaluateJavaScript("document.querySelector('#next').click()")
        try await waitForDocument(tab.web, title: "Next navigation fixture")
        XCTAssertFalse(tab.reader)
        XCTAssertTrue(tab.web.canGoBack)
        tab.web.goBack()
        try await waitForDocument(tab.web, title: "Reader navigation fixture")
        XCTAssertEqual(tab.address, article)
        XCTAssertTrue(tab.web.canGoForward)
        tab.web.goForward()
        try await waitForDocument(tab.web, title: "Next navigation fixture")
        tab.web.goBack()
        try await waitForDocument(tab.web, title: "Reader navigation fixture")
        let reentered = await toggle()
        XCTAssertTrue(reentered)
        XCTAssertTrue(tab.reader)
        let exited = await toggle()
        XCTAssertTrue(exited)
        try await waitForDocument(tab.web, title: "Reader navigation fixture")
        XCTAssertFalse(tab.reader)
        XCTAssertEqual(tab.address, article)
        var restored = false
        for _ in 0..<100 {
            restored = (try? await tab.web.evaluateJavaScript("!!document.querySelector('#draft') && !document.querySelector('#office-reader') && document.readyState === 'complete'")) as? Bool == true
            if restored, !tab.web.isLoading { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertTrue(restored)
    }


    func testCaptureNativeAppearanceControlsWithoutCreatingAWebView() async throws {
        guard let directory = ProcessInfo.processInfo.environment["BROWSE_READER_SCREENSHOTS"] else {
            throw XCTSkip("Set BROWSE_READER_SCREENSHOTS for native control captures")
        }
        _ = NSApplication.shared
        let tab = Tab(shy: true)
        let host = NSHostingView(rootView: ReaderLook(tab: tab).frame(width: 160, height: 70))
        let window = NSWindow(contentRect: NSRect(x: -20000, y: -20000, width: 160, height: 70), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        defer { window.close() }
        for look in [Look.light, .dark] {
            tab.readerLook = look
            window.appearance = NSAppearance(named: look == .dark ? .darkAqua : .aqua)
            try await Task.sleep(nanoseconds: 100_000_000)
            host.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            let output = URL(fileURLWithPath: directory, isDirectory: true)
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            try png.write(to: output.appendingPathComponent("controls-" + look.rawValue + ".png"))
        }
        XCTAssertNil(tab.built)
    }

    func testPageCannotSpoofCompletedReaderWithAnElementID() async throws {
        let web = try await page("<div id='office-reader'><iframe src='https://evil.example.test/frame'></iframe></div>")
        // Page-world globals cannot impersonate our isolated-world marker.
        _ = try await web.evaluateJavaScript("window.__browseReaderDocument = document; true")
        try await read(web)
        let result = try await web.evaluateJavaScript("document.querySelectorAll('#office-reader').length === 1 && !document.querySelector('iframe') && document.querySelector('h1').textContent === 'A local article'")
        XCTAssertEqual(result as? Bool, true)
    }


    func testExtractionPausesOriginalMediaRetainedByPageScripts() async throws {
        let (browser, tab, _) = try await readerTab(media: true)
        defer { withExtendedLifetime(browser) {} }
        let window = NSWindow(contentRect: NSRect(x: -20000, y: -20000, width: 900, height: 900), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = tab.web
        window.orderFront(nil)
        defer { window.close() }
        _ = try await tab.web.evaluateJavaScript("window.savedMedia = document.querySelector('#movie'); savedMedia.play().catch(e => window.playError = e.message); true")
        var playing = false
        for _ in 0..<150 {
            playing = (try? await tab.web.evaluateJavaScript("!savedMedia.paused && savedMedia.currentTime > 0")) as? Bool == true
            if playing { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        let diagnostic = try await tab.web.evaluateJavaScript("JSON.stringify({paused:savedMedia.paused,time:savedMedia.currentTime,ready:savedMedia.readyState,error:savedMedia.error && savedMedia.error.message,playError:window.playError,visible:document.visibilityState})")
        XCTAssertTrue(playing, "Synthetic local media must actually play before extraction: \(String(describing: diagnostic))")
        let entered = await withCheckedContinuation { continuation in
            tab.toggleReader { continuation.resume(returning: $0) }
        }
        XCTAssertTrue(entered)
        let stopped = try await tab.web.evaluateJavaScript("savedMedia.paused && !savedMedia.isConnected") as? Bool
        XCTAssertEqual(stopped, true)
    }

}
