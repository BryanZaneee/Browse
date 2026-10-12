import AppKit
import Combine
import SecurityInterface
import SwiftUI

// The site card: what Right-click › Site Information… shows under its address,
// in the column and in the bar across the top alike — whether the connection
// is private, and the few things that belong to the page (copy its address,
// print it, its zoom, whether it may play sound by itself, whether its videos
// float out). It goes as soon
// as you type, when the address is left, or when one of its lines is used.
// From #56, whose bar it came with; the bar itself stayed out, since Search
// has the column or the strip, never a second row over the page.

/// The card's own small window, under the tab's address. It never takes the
/// keys: the address stays in the tab being edited, the caret where it was,
/// and a click on the card is only a click.
@MainActor
enum SiteCardPanel {
    private static var panel: Panel?
    private static var resign: Any?

    static var isShown: Bool { panel != nil && !suggestionsShown }
    private(set) static var suggestionsShown = false
    private static weak var suggestionBrowser: Browser?
    private static weak var suggestionSurface: TabAddressSurface.Surface?

    static func hideSuggestions(for browser: Browser) {
        if suggestionsShown, suggestionBrowser === browser { hide() }
    }

    static func suggest(_ browser: Browser, under field: NSTextField) {
        guard let id = browser.editingTab, !browser.renamingTab, !browser.tabOffers.isEmpty,
              field.currentEditor() != nil, let window = field.window else { return }
        guard let surface = TabAddressSurface.find(for: browser, field: field) else { return }
        let width = surface.bounds.width
        if suggestionsShown, suggestionBrowser === browser, let panel, panel.parent === window {
            if let host = panel.contentView?.subviews.first as? FirstClick, host.frame.width != width {
                host.rootView = AnyView(TabSuggestions(browser: browser, tab: id).frame(width: width))
            }
            if suggestionSurface !== surface { suggestionSurface?.attach(above: nil) }
            suggestionSurface = surface
            position(panel, under: field)
            return
        }
        hide()
        suggestionsShown = true
        suggestionBrowser = browser
        suggestionSurface = surface
        present(AnyView(TabSuggestions(browser: browser, tab: id).frame(width: width)), under: field)
    }

    // MARK: - when

    /// The field the address is being edited in. SwiftUI can make it and
    /// throw it away several times as the edit begins, so the card follows
    /// the browser's edit rather than any one field, and stands under the one
    /// with the caret.
    private static weak var anchor: NSView?

    static func follow(_ browser: Browser, anchor field: NSView) {
        anchor = field
        guard browser.tabInformationWatch == nil else { return }
        var original: String?
        browser.tabInformationWatch = browser.$editingTab.combineLatest(browser.$tabDraft)
            .receive(on: DispatchQueue.main)
            .sink { [weak browser] editing, draft in
                MainActor.assumeIsolated {
                    guard let browser else { return }
                    guard let id = editing, !browser.renamingTab,
                          let tab = browser.tabs.first(where: { $0.id == id }), !tab.isBlank
                    else { original = nil; hide(); return }
                    if original == nil, browser.showingTabInformation {
                        // The edit began: the card comes up under the field once it
                        // is in its window.
                        original = draft
                        place(tab, browser, original: draft, tries: 0)
                    } else if draft != original, !suggestionsShown {
                        // Typing somewhere else: the card was about the page you are on.
                        hide()
                    }
                }
            }
    }

    private static func place(_ tab: Tab, _ browser: Browser, original: String, tries: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
            guard browser.showingTabInformation, browser.editingTab == tab.id, browser.tabDraft == original else { return }
            // The field with the caret in it is the one on screen; failing
            // that, the latest one made.
            let focused = ((browser.window ?? Links.window)?.firstResponder as? NSTextView)?.delegate as? NSTextField
            guard let field = focused ?? anchor, field.window != nil else {
                if tries < 15 { place(tab, browser, original: original, tries: tries + 1) }
                return
            }
            show(for: tab, in: browser, under: field)
        }
    }

    /// Under `field`, the tab's address, in `browser`'s window.
    private static func show(for tab: Tab, in browser: Browser, under field: NSView) {
        guard field.window != nil else { return }
        hide()
        let card = SiteCard(browser: browser, tab: tab) {
            SiteCardPanel.hide()
            browser.cancelTabEdit()
        }
        present(AnyView(card.fixedSize()), under: field)
    }

    private static func present(_ content: AnyView, under field: NSView) {
        guard let window = field.window else { return }
        let host = FirstClick(rootView: content)
        let size = host.fittingSize
        let glass: NSView
        if suggestionsShown {
            glass = NSView(frame: NSRect(origin: .zero, size: size))
        } else {
            let effect = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
            effect.material = .menu
            effect.state = .active
            glass = effect
        }
        glass.wantsLayer = true
        glass.layer?.cornerRadius = suggestionsShown ? 9 : MenuMetrics.corner
        glass.layer?.cornerCurve = .continuous
        glass.layer?.masksToBounds = true
        glass.layer?.borderWidth = suggestionsShown ? 0 : 0.5
        glass.layer?.borderColor = MenuMetrics.edge.cgColor
        // Before macOS 26 the material behind the window ignores the layer's
        // corners, and showed square ones; a mask rounds it there too.
        if #unavailable(macOS 26), let effect = glass as? NSVisualEffectView { effect.maskImage = Self.rounded(MenuMetrics.corner) }
        host.frame = glass.bounds
        host.autoresizingMask = [.width, .height]
        glass.addSubview(host)

        let panel = Panel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        if suggestionsShown { panel.identifier = NSUserInterfaceItemIdentifier("tab-address-suggestions") }
        panel.contentView = glass
        if suggestionsShown {
            panel.minSize = .zero
            panel.contentMinSize = .zero
        }
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = !suggestionsShown
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = true
        position(panel, under: field)
        window.addChildWindow(panel, ordered: .above)
        if suggestionsShown { reveal(panel, under: field, animated: !Motion.reduced) }
        host.onResize = { [weak panel, weak field] fitted in
            guard let panel, let field, fitted.width > 0, fitted.height > 0,
                  panel.frame.size != fitted else { return }
            let width = panel.identifier?.rawValue == "tab-address-suggestions" ? suggestionSurface?.bounds.width ?? fitted.width : fitted.width
            panel.setContentSize(NSSize(width: width, height: fitted.height))
            position(panel, under: field)
        }
        self.panel = panel
        resign = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                suggestionBrowser?.dismissTabSuggestions()
                SiteCardPanel.hide()
            }
        }
    }

    private static func position(_ panel: NSPanel, under field: NSView) {
        guard let window = field.window else { return }
        let surface = panel.identifier?.rawValue == "tab-address-suggestions" ? suggestionSurface : nil
        let anchor = surface ?? field
        let spot = window.convertToScreen(anchor.convert(anchor.bounds, to: nil))
        if let surface, panel.frame.width != surface.bounds.width {
            panel.setContentSize(NSSize(width: surface.bounds.width, height: panel.frame.height))
        }
        let size = panel.frame.size
        let gap: CGFloat = surface == nil ? 12 : 0
        var origin = NSPoint(x: spot.minX - (surface == nil ? 12 : 0), y: spot.minY - gap - size.height)
        if let screen = window.screen?.visibleFrame {
            origin.x = max(screen.minX + 8, min(origin.x, screen.maxX - size.width - 8))
            if origin.y < screen.minY + 8 { origin.y = min(spot.maxY + gap, screen.maxY - size.height - 8) }
        }
        if let surface {
            let above = origin.y >= spot.maxY
            surface.attach(above: above)
            panel.contentView?.layer?.maskedCorners = above
                ? [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
                : [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        }
        panel.setFrameOrigin(origin)
    }

    /// Uncover the rows from the field's edge without moving the native editor
    /// or scaling its text. The panel keeps its final hit-testing geometry.
    static func reveal(_ panel: NSPanel, under field: NSView, animated: Bool) {
        guard let glass = panel.contentView, let layer = glass.layer else { return }
        layer.mask = nil
        layer.removeAnimation(forKey: "suggestions-fade")
        guard animated, let window = field.window else { return }
        let spot = window.convertToScreen(field.convert(field.bounds, to: nil))
        let below = panel.frame.midY < spot.midY
        let mask = CALayer()
        mask.backgroundColor = NSColor.black.cgColor
        mask.bounds = glass.bounds
        mask.anchorPoint = CGPoint(x: 0.5, y: below ? 1 : 0)
        mask.position = CGPoint(x: glass.bounds.midX, y: below ? glass.bounds.maxY : glass.bounds.minY)
        mask.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        layer.mask = mask

        let unfold = CABasicAnimation(keyPath: "transform.scale.y")
        unfold.fromValue = 0
        unfold.toValue = 1
        unfold.duration = 0.30
        // The same gentle ease-out used for Search's native pane transitions.
        unfold.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1, 0.36, 1)
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        fade.duration = 0.14
        fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak layer, weak panel] in
            MainActor.assumeIsolated {
                guard layer?.mask === mask else { return }
                layer?.mask = nil
                panel?.invalidateShadow()
            }
        }
        mask.add(unfold, forKey: "suggestions-unfold")
        layer.add(fade, forKey: "suggestions-fade")
        CATransaction.commit()
    }

    /// A rounded rectangle that stretches to any size, its corners kept.
    private static func rounded(_ corner: CGFloat) -> NSImage {
        let side = corner * 2 + 1
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: corner, yRadius: corner).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: corner, left: corner, bottom: corner, right: corner)
        image.resizingMode = .stretch
        return image
    }

    static func hide() {
        suggestionsShown = false
        suggestionBrowser = nil
        suggestionSurface?.attach(above: nil)
        suggestionSurface = nil
        if let resign { NotificationCenter.default.removeObserver(resign) }
        resign = nil
        guard let panel else { return }
        panel.contentView?.layer?.mask = nil
        panel.contentView?.layer?.removeAnimation(forKey: "suggestions-fade")
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
        self.panel = nil
    }

    private final class Panel: NSPanel {
        override var canBecomeKey: Bool { false }
        override var canBecomeMain: Bool { false }
    }

    /// Takes the first click even though its window never becomes key, and
    /// says when what it shows changes size.
    private final class FirstClick: NSHostingView<AnyView> {
        var onResize: ((NSSize) -> Void)?
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func layout() {
            super.layout()
            // SwiftUI can lay out a different card without invalidating the
            // host's intrinsic size. Measure after layout and resize outside it.
            let fitted = fittingSize
            let size = NSSize(width: ceil(fitted.width), height: ceil(fitted.height))
            guard size != frame.size else { return }
            DispatchQueue.main.async { [weak self] in self?.onResize?(size) }
        }
    }
}

/// The site the tab is on: how private the connection is, and the few things
/// that belong to this page rather than to the browser. The connection's line
/// goes a step further in, to what it means and the certificate behind it.
struct SiteCard: View {
    let browser: Browser
    @ObservedObject var tab: Tab
    let close: () -> Void

    /// One step in: the connection, said in full.
    @State private var deeper: Bool
    /// Whether this Mac trusts the site's certificate. Unknown until it has
    /// been asked, off the main thread: asking can go to the network.
    @State private var certified: Bool?

    init(browser: Browser, tab: Tab, deeper: Bool = false, close: @escaping () -> Void) {
        self.browser = browser
        self.tab = tab
        self.close = close
        _deeper = State(initialValue: deeper)
    }

    var body: some View {
        Group {
            if deeper, let safety {
                security(safety)
            } else {
                front
            }
        }
        .padding(.vertical, MenuMetrics.pad)
        .frame(minWidth: 180)
        .fixedSize()
        .transition(.opacity)
        .animation(Motion.quick, value: deeper)
        .onAppear(perform: certify)
    }

    /// The host as a person says it, without the www. A page with no host —
    /// a file, about:blank — is named by what it is.
    static func site(_ url: URL) -> String {
        if let host = url.host(), !host.isEmpty {
            return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        }
        if url.isFileURL { return "File" }
        return url.scheme ?? url.absoluteString
    }

    // MARK: - the card, drawn as the system draws a menu

    private var front: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let url = tab.pageAddress {
                Header(title: SiteCard.site(url))
            }
            if let safety {
                Row(safety.title, submenu: true) { deeper = true }
            }
            Row("Copy Address", keys: "⇧⌘C") { after { browser.copyAddress() } }
            Separator()
            Row("Print…", keys: "⌘P") { after { browser.printPage() } }
            zoom
            sound
            grounded
        }
    }

    /// Whether the site's videos float out on their own (see Grounded).
    /// Only on a site they would float from, with one of Settings › General's
    /// Float the video switches on, and not in a private tab.
    @ViewBuilder private var grounded: some View {
        if !tab.shy, browser.prefs.floatsOnLeave || browser.prefs.floatsAway,
           let url = tab.pageAddress, ["http", "https"].contains(url.scheme?.lowercased()),
           Players.knows(url), let host = url.host() {
            Ground(host: host)
        }
    }

    /// Whether the site may play sound by itself (see Autoplay), a switch at
    /// the end of its line. Not in a private tab, which remembers nothing,
    /// nor with Settings › Videos wait for a click on, which lets no site.
    @ViewBuilder private var sound: some View {
        if !tab.shy, !Store.settings.bool(forKey: Preferences.waitsKey),
           let url = tab.pageAddress, ["http", "https"].contains(url.scheme?.lowercased()),
           let host = url.host() {
            Sound(host: host)
        }
    }

    /// The page's size, remembered for the site (see Tab.rememberZoom), as a
    /// menu puts a control on one of its lines: the name, and the steps at
    /// its end. The number puts it back to the size every site starts at.
    private var zoom: some View {
        HStack(spacing: 0) {
            Text("Zoom")
                .font(MenuMetrics.font)
                .foregroundStyle(Color(nsColor: .labelColor))
            Spacer(minLength: 24)
            Step(symbol: "minus", help: "Zoom Out   ⌘-") { browser.zoom(by: 1 / 1.1) }
            Button { browser.resetZoom() } label: {
                Text("\(Int((tab.zoom * 100).rounded()))%")
                    .font(MenuMetrics.font)
                    .monospacedDigit()
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                    .frame(width: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Actual Size   ⌘0")
            Step(symbol: "plus", help: "Zoom In   ⌘+") { browser.zoom(by: 1.1) }
        }
        .padding(.leading, MenuMetrics.text)
        .padding(.trailing, MenuMetrics.inset + 4)
        .frame(height: MenuMetrics.row)
    }

    /// The line itself. WebKit takes it as a page loads, so a page already
    /// open stays as it came, and the line says so once flipped.
    private struct Sound: View {
        let host: String
        private let was: Bool
        @State private var on: Bool

        init(host: String) {
            self.host = host
            was = Autoplay.allowed(host)
            _on = State(initialValue: was)
        }

        var body: some View {
            HStack(spacing: 0) {
                Text("Play Sound by Itself")
                    .font(MenuMetrics.font)
                    .foregroundStyle(Color(nsColor: .labelColor))
                    .fixedSize()
                Spacer(minLength: 24)
                if on != was {
                    Text("from the next page")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                        .fixedSize()
                        .padding(.trailing, 8)
                }
                Switch(on: $on)
            }
            .padding(.leading, MenuMetrics.text)
            .padding(.trailing, MenuMetrics.trailing)
            .frame(height: MenuMetrics.row)
            .onChange(of: on) { _, value in Autoplay.set(value, for: host) }
        }
    }

    /// Its line. Asked each time a video would float, so it holds at once,
    /// for the page already open too.
    private struct Ground: View {
        let host: String
        @State private var on: Bool

        init(host: String) {
            self.host = host
            _on = State(initialValue: Grounded.holds(host))
        }

        var body: some View {
            HStack(spacing: 0) {
                Text("Don't Float Videos Here")
                    .font(MenuMetrics.font)
                    .foregroundStyle(Color(nsColor: .labelColor))
                    .fixedSize()
                Spacer(minLength: 24)
                Switch(on: $on)
            }
            .padding(.leading, MenuMetrics.text)
            .padding(.trailing, MenuMetrics.trailing)
            .frame(height: MenuMetrics.row)
            .onChange(of: on) { _, value in Grounded.set(value, for: host) }
        }
    }

    // MARK: - one step in

    private func security(_ safety: Safety) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let url = tab.pageAddress {
                Header(title: SiteCard.site(url))
            }
            Text(safety.title)
                .font(MenuMetrics.font)
                .foregroundStyle(Color(nsColor: .labelColor))
                .padding(.leading, MenuMetrics.text)
                .frame(height: MenuMetrics.row, alignment: .leading)
            Text(safety.detail)
                .font(.system(size: 11))
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 230, alignment: .leading)
                .padding(.leading, MenuMetrics.text)
                .padding(.trailing, MenuMetrics.trailing)
                .padding(.bottom, 6)
            Separator()
            if let trust = safety.trust {
                Row(certified == false ? "Show Certificate (Not Valid)…" : "Show Certificate…") {
                    after { SiteCard.show(trust) }
                }
            }
            Row("Back") { deeper = false }
        }
    }

    // MARK: - the connection

    /// What there is to say about the connection, from a page's own address
    /// and what WebKit knows of how it came.
    private struct Safety {
        let symbol: String
        let title: String
        let detail: String
        let tint: Color
        /// The certificate the page came with, for an https page.
        let trust: SecTrust?
    }

    /// Asked when the card opens: a page that pulls in something over plain
    /// http after that is not worth a card that changes under you.
    private var safety: Safety? {
        switch tab.pageAddress?.scheme {
        case "https":
            let trust = tab.built?.serverTrust
            // Only a certificate this Mac refused and you let through anyway
            // (see Dialogs.trust) gets this far untrusted.
            if certified == false {
                return Safety(
                    symbol: "lock.open", title: "Connection is not secure",
                    detail: "This site's certificate isn't trusted by this Mac. Someone could be reading what you send.",
                    tint: Palette.unsafe, trust: trust
                )
            }
            if tab.built?.hasOnlySecureContent == false {
                return Safety(
                    symbol: "lock.trianglebadge.exclamationmark", title: "Parts of this page are not secure",
                    detail: "The page came privately, but some of what it shows was fetched over plain http, where anyone on the network could read or change it.",
                    tint: Palette.unsafe, trust: trust
                )
            }
            return Safety(
                symbol: "lock", title: "Connection is secure",
                detail: "Your information (for example, passwords or credit card numbers) is private when it is sent to this site.",
                tint: Palette.safe, trust: trust
            )
        case "http":
            return Safety(
                symbol: "lock.open", title: "Connection is not secure",
                detail: "Don't enter passwords or credit card numbers here: anything sent to this site can be read on the way.",
                tint: Palette.unsafe, trust: nil
            )
        default:
            return nil
        }
    }

    /// Asks whether this Mac trusts the certificate, the way it would for
    /// any app. Off the main thread: the answer can need a revocation check.
    private func certify() {
        guard certified == nil, let trust = tab.built?.serverTrust else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            let ok = SecTrustEvaluateWithError(trust, nil)
            DispatchQueue.main.async { certified = ok }
        }
    }

    /// The system's own certificate sheet, over the window.
    private static func show(_ trust: SecTrust) {
        guard let window = Links.window else { return }
        SFCertificatePanel.shared().beginSheet(
            for: window, modalDelegate: nil, didEnd: nil, contextInfo: nil, trust: trust, showGroup: false
        )
    }

    /// The card goes first, then the thing is done: a print panel or a sheet
    /// coming up under a popover still on its way out lands behind it.
    private func after(_ act: @escaping () -> Void) {
        close()
        DispatchQueue.main.async(execute: act)
    }

    /// One line, as a menu item draws it: its title in the menu's font where
    /// a menu puts its text, a key equivalent at the end, the accent colour
    /// behind it and white letters under the pointer. A line that opens more
    /// ends in the submenu's chevron.
    private struct Row: View {
        let title: String
        var keys = ""
        var submenu = false
        let act: () -> Void

        @State private var hovering = false

        init(_ title: String, keys: String = "", submenu: Bool = false, act: @escaping () -> Void) {
            self.title = title
            self.keys = keys
            self.submenu = submenu
            self.act = act
        }

        var body: some View {
            HStack(spacing: 0) {
                Text(title)
                    .font(MenuMetrics.font)
                    .foregroundStyle(hovering ? Color.white : Color(nsColor: .labelColor))
                    .lineLimit(1)
                    .fixedSize()
                Spacer(minLength: keys.isEmpty ? 24 : 26)
                if !keys.isEmpty {
                    Text(keys)
                        .font(MenuMetrics.font)
                        .foregroundStyle(hovering ? Color.white : Color(nsColor: .secondaryLabelColor))
                        .fixedSize()
                }
                if submenu {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(hovering ? Color.white : Color(nsColor: .secondaryLabelColor))
                }
            }
            .padding(.leading, MenuMetrics.text - MenuMetrics.inset)
            .padding(.trailing, MenuMetrics.trailing - MenuMetrics.inset)
            .frame(height: MenuMetrics.row)
            .background(
                RoundedRectangle(cornerRadius: MenuMetrics.highlight, style: .continuous)
                    .fill(hovering ? MenuMetrics.selection : .clear)
            )
            .padding(.horizontal, MenuMetrics.inset)
            .contentShape(Rectangle())
            .onTapGesture(perform: act)
            .onHover { hovering = $0 }
        }
    }

    /// The site's name over the lines, as a menu's section header is drawn.
    private struct Header: View {
        let title: String

        var body: some View {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                .lineLimit(1)
                .padding(.leading, MenuMetrics.text)
                .padding(.trailing, MenuMetrics.trailing)
                .frame(height: MenuMetrics.row, alignment: .leading)
        }
    }

    /// A menu's separator: a hairline in its own band.
    private struct Separator: View {
        var body: some View {
            Rectangle()
                .fill(Color(nsColor: .separatorColor))
                .frame(height: 1)
                .padding(.horizontal, MenuMetrics.rule)
                .frame(height: MenuMetrics.separator)
        }
    }

    /// A step of the zoom: the symbol alone, on the accent colour under the
    /// pointer as a menu's line would be.
    private struct Step: View {
        let symbol: String
        let help: String
        let act: () -> Void

        @State private var hovering = false

        var body: some View {
            Button(action: act) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(hovering ? Color.white : Color(nsColor: .labelColor))
                    .frame(width: 22, height: 18)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(hovering ? MenuMetrics.selection : .clear)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .help(help)
        }
    }
}

/// A menu's measurements, as macOS lays out an NSMenu (measured from one:
/// NSMenu.size with the same items), so the card sits beside the tab's
/// right-click menu as one of its own.
enum MenuMetrics {
    static let font = Font(NSFont.menuFont(ofSize: 0))
    /// One item.
    static let row: CGFloat = 24
    /// A separator's band.
    static let separator: CGFloat = 11
    /// Above the first item and under the last.
    static let pad: CGFloat = 5
    /// Where the highlight starts, from the menu's edge.
    static let inset: CGFloat = 5
    /// Where an item's text starts, from the menu's edge: a context menu
    /// without a checkmark column, as the tab's right-click is.
    static let text: CGFloat = 17
    /// From the end of the text, or of its key equivalent, to the menu's edge.
    static let trailing: CGFloat = 17
    /// A separator's line, in from either edge.
    static let rule: CGFloat = 16
    static let highlight: CGFloat = 6
    static let corner: CGFloat = 12
    /// The line under the pointer: the accent colour as a menu shows it over
    /// its glass, lighter than the accent itself (111, 162, 249 for blue).
    static let selection = Color(nsColor: NSColor(name: nil) { appearance in
        let accent = NSColor.controlAccentColor.usingColorSpace(.sRGB) ?? .systemBlue
        return appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? accent.blended(withFraction: 0.15, of: .black) ?? accent
            : accent.blended(withFraction: 0.42, of: .white) ?? accent
    })
    /// The panel's hairline edge.
    static let edge = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor.white.withAlphaComponent(0.18) : NSColor.black.withAlphaComponent(0.26)
    }
}

/// The omnibox's rows, beside the address actually being edited.
private struct TabSuggestions: View {
    @ObservedObject var browser: Browser
    let tab: Tab.ID

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(browser.tabOffers.enumerated()), id: \.element.id) { index, offer in
                Button { browser.takeTabSuggestion(offer, for: tab) } label: {
                    Omnibox.Row(offer: offer, picked: browser.tabPicked == index, selectionBackground: Palette.ground)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(offer.key + (offer.title.isEmpty ? "" : ", " + offer.title))
                .accessibilityAddTraits(browser.tabPicked == index ? .isSelected : [])
            }
        }
        .padding(6)
        .background(Palette.wash)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Address suggestions")
    }
}
