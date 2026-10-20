import SwiftUI
import WebKit

/// WebKit keeps the original window.open or form submission suspended until
/// this is answered. No popup view is made, or request replayed, while waiting.
@MainActor
final class PopupQuestion {
    let site: String
    let host: String
    weak var tab: Tab?
    weak var view: WKWebView?
    let page: URL?
    var shown: Date?
    private var reply: ((Bool) -> Void)?

    init(site: String, host: String, tab: Tab, view: WKWebView, reply: @escaping (Bool) -> Void) {
        self.site = site
        self.host = host
        self.tab = tab
        self.view = view
        page = tab.committed ?? view.url
        self.reply = reply
    }

    func answer(_ allowed: Bool) {
        let reply = reply
        self.reply = nil
        reply?(allowed)
    }

    deinit { reply?(false) }
}

extension Browser {
    // The public callback is synchronous. This WebKit hook lets the same
    // permission card as other site requests wait without replaying a URL.
    @objc(_webView:createWebViewWithConfiguration:forNavigationAction:windowFeatures:completionHandler:)
    func createPopup(_ webView: WKWebView, configuration: WKWebViewConfiguration,
                     action: WKNavigationAction, features: WKWindowFeatures,
                     completionHandler: @escaping (WKWebView?) -> Void) {
        requestPopup(webView, configuration: configuration, action: action, features: features,
                     canAsk: true, reply: completionHandler)
    }

    func requestPopup(_ webView: WKWebView, configuration: WKWebViewConfiguration,
                      action: WKNavigationAction, features: WKWindowFeatures,
                      canAsk: Bool, reply: @escaping (WKWebView?) -> Void) {
        guard let opener = popupTab(for: webView) else { return reply(nil) }
        let clicked = opener.popupGesture.take(origin: PopupGesture.origin(action.sourceFrame),
                                               mainFrame: action.sourceFrame.isMainFrame)
        if !clicked, opener.popupGesture.spent() { return reply(nil) }
        let nativeLink = (webView as? PageView)?.takeLinkRequest()
        let behind = nativeLink == true
        let top = opener.committed ?? webView.url
        let topSite = BlockedPopups.site(of: top)
        let frameSite = BlockedPopups.site(scheme: action.sourceFrame.securityOrigin.protocol,
                                          host: action.sourceFrame.securityOrigin.host)
        let make: () -> WKWebView? = { [weak self, weak opener, weak webView] in
            guard let self, let opener, let webView, popupTab(for: webView) === opener,
                  (opener.committed ?? webView.url) == top else { return nil }
            return makePopup(from: webView, opener: opener, configuration: configuration,
                             action: action, features: features, clicked: clicked, behind: behind)
        }
        // A native menu command is already an explicit request. Opaque and
        // extension frames retain their existing gesture checks.
        guard nativeLink == nil, topSite != nil, let site = frameSite else {
            if clicked || popupsAllowed(opener, from: action.sourceFrame, top: top) {
                reply(make())
            } else {
                opener.noteBlocked(action.request.url)
                reply(nil)
            }
            return
        }
        // An embedded site must have received its own real interaction.
        // Neither the top site's click nor its allow choice authorizes it.
        guard site == topSite || clicked else {
            opener.noteBlocked(action.request.url)
            return reply(nil)
        }
        let blocked = opener.shy ? opener.blockedPopupSites : prefs.blockedPopupSites
        if blocked.contains(site) {
            opener.noteBlocked(action.request.url)
            return reply(nil)
        }
        let allowed = opener.shy ? opener.popupSites : prefs.popupSites
        if allowed.contains(site) { return reply(make()) }
        guard canAsk, pendingPopup == nil, asking == nil else {
            opener.noteBlocked(action.request.url)
            return reply(nil)
        }
        let question = PopupQuestion(site: site, host: action.sourceFrame.securityOrigin.host,
                                     tab: opener, view: webView) { allowed in
            if !allowed { opener.noteBlocked(action.request.url) }
            reply(allowed ? make() : nil)
        }
        pendingPopup = question
        opener.onPopupCancel = { [weak self, weak question] in
            guard let self, let question, pendingPopup === question else { return }
            cancelPopup()
        }
        ask(from: webView, show: { [weak self, weak question] in
            guard let self, let question, pendingPopup === question else { return }
            guard let view = question.view, popupTab(for: view) === question.tab,
                  (question.tab?.committed ?? view.url) == question.page else { return cancelPopup() }
            question.shown = Date()
            askingPopup = question
        }, drop: { [weak self, weak question] in
            guard let self, let question, pendingPopup === question else { return }
            cancelPopup()
        })
    }

    func answerPopup(allow: Bool, keep: Bool = true) {
        guard let question = askingPopup, pendingPopup === question,
              let shown = question.shown, Date().timeIntervalSince(shown) > 0.5 else { return }
        guard let tab = question.tab, let view = question.view,
              popupTab(for: view) === tab, (tab.committed ?? view.url) == question.page
        else { return cancelPopup() }
        clearPopup(question)
        if !keep {
            question.answer(allow)
            return
        }
        if tab.shy {
            if allow {
                tab.popupSites.insert(question.site)
                tab.blockedPopupSites.remove(question.site)
            } else {
                tab.blockedPopupSites.insert(question.site)
                tab.popupSites.remove(question.site)
            }
        } else if allow {
            prefs.popupSites.insert(question.site)
            prefs.blockedPopupSites.remove(question.site)
        } else {
            prefs.blockedPopupSites.insert(question.site)
            prefs.popupSites.remove(question.site)
        }
        question.answer(allow)
    }

    func cancelPopup(for view: WKWebView? = nil) {
        guard let question = pendingPopup, view == nil || question.view === view else { return }
        clearPopup(question)
        question.answer(false)
    }

    func popupKey(_ event: NSEvent) -> Bool {
        guard askingPopup != nil, [UInt16(36), 76, 53].contains(event.keyCode),
              event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return false }
        cancelPopup()
        return true
    }

    private func clearPopup(_ question: PopupQuestion) {
        pendingPopup = nil
        askingPopup = nil
        question.tab?.onPopupCancel = nil
    }
}

struct PopupPermissionCard: View {
    @ObservedObject var browser: Browser
    let question: PopupQuestion

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "rectangle.on.rectangle")
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.muted)
                    .padding(.top, 2)
                Text("Allow pop-ups from \(question.site)?")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("This site is trying to open a new tab."
                 + (question.tab?.shy == true ? " Your choice lasts until this private tab closes." : " You can change this in Settings › Privacy."))
                .font(.system(size: 12))
                .foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                Button { browser.answerPopup(allow: false) } label: {
                    Text("Don’t allow")
                        .padding(.horizontal, 8)
                        .padding(.vertical, 7)
                        .contentShape(Rectangle())
                }
                Spacer(minLength: 12)
                Button { browser.answerPopup(allow: true, keep: false) } label: {
                    Text("Allow this time")
                        .padding(.horizontal, 8)
                        .padding(.vertical, 7)
                        .contentShape(Rectangle())
                }
                Button { browser.answerPopup(allow: true) } label: {
                    Text("Always allow")
                        .foregroundStyle(Palette.ground)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Palette.ink, in: Capsule())
                }
            }
            .font(.system(size: 12))
            .foregroundStyle(Palette.muted)
            .buttonStyle(.plain)
        }
        .frame(maxWidth: 400, alignment: .leading)
        .padding(18)
        .background(Palette.ground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Palette.hairline, lineWidth: 1))
        .shadow(color: .black.opacity(0.12), radius: 20, y: 6)
        .padding(.horizontal, 16)
    }
}
