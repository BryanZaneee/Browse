import SwiftUI
import WebKit

/// WebKit presents only the video; its page stays in the browser's stage.
@MainActor
final class Float: ObservableObject {
    enum Entry { case started, unavailable, cancelled }

    @Published private(set) var tab: Tab?
    @Published private(set) var starting = false
    private var stopping = false
    private(set) var automatic = false
    private var frame: VideoRelay.Frame?
    private var request: String?
    private var timeout: DispatchWorkItem?
    var showing: Bool { tab != nil }

    static func enable(_ preferences: WKPreferences) {
        // WKWebView's public PiP switch is iOS-only. Ask before using its macOS counterpart.
        let set = NSSelectorFromString("_setAllowsPictureInPictureMediaPlayback:")
        guard preferences.responds(to: set) else { return }
        typealias Setter = @convention(c) (AnyObject, Selector, Bool) -> Void
        unsafeBitCast(preferences.method(for: set), to: Setter.self)(preferences, set, true)
    }

    func lift(_ tab: Tab, automatically: Bool, then: @escaping (Entry) -> Void) {
        guard !showing, let web = tab.built, web.fullscreenState == .notInFullscreen,
              let frame = tab.video.best(playing: automatically) else { then(.unavailable); return }
        let token = UUID().uuidString
        self.tab = tab
        self.frame = frame
        automatic = automatically
        starting = true
        request = token
        var answered = false
        let finish: (Entry) -> Void = { result in
            guard !answered else { return }
            answered = true
            then(result)
        }
        let expiry = DispatchWorkItem { [weak self] in
            guard let self, self.request == token else { finish(.cancelled); return }
            self.drop()
            finish(.unavailable)
        }
        timeout = expiry
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: expiry)
        web.callAsyncJavaScript("return window.__searchPiP?.enter(documentID, token, automatic) ?? false;",
                                arguments: ["documentID": frame.id, "token": token, "automatic": automatically],
                                in: frame.info, in: Web.world) { [weak self] result in
            guard let self, self.request == token else { finish(.cancelled); return }
            self.timeout?.cancel()
            self.timeout = nil
            guard (try? result.get()) as? Bool == true else {
                self.drop { finish(.unavailable) }
                return
            }
            self.starting = false
            tab.floating = true
            finish(.started)
        }
    }

    func changed(_ tab: Tab, frame: VideoRelay.Frame, active: Bool, token: String?) {
        if stopping, self.tab === tab, self.frame?.id == frame.id { return }
        if active {
            // A cancelled entry can finish after another tab has requested PiP.
            if let token, token != request {
                exit(tab, frame: frame, token: token)
                return
            }
            if self.tab !== tab || self.frame?.id != frame.id {
                let previous = self.tab, source = self.frame, token = request
                clear()
                if let previous, let source { exit(previous, frame: source, token: token) }
                self.tab = tab
                self.frame = frame
                automatic = false
            }
            tab.floating = true
        } else if self.tab === tab, self.frame?.id == frame.id, !starting {
            clear()
        }
    }

    func lost(_ tab: Tab, document: String? = nil) {
        guard self.tab === tab, document == nil || frame?.id == document else { return }
        drop()
    }

    func drop(then: (() -> Void)? = nil) {
        guard !stopping else { return }
        guard let previous = tab, let source = frame else { clear(); then?(); return }
        let token = request, stop = UUID().uuidString
        request = stop
        starting = false
        stopping = true
        timeout?.cancel()
        let finish = { [weak self] in
            guard let self, self.request == stop else { return }
            self.clear()
            then?()
        }
        let expiry = DispatchWorkItem(block: finish)
        timeout = expiry
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: expiry)
        guard let web = previous.built else { finish(); return }
        web.callAsyncJavaScript("return window.__searchPiP?.exit(documentID, token);",
                                arguments: ["documentID": source.id, "token": token as Any? ?? NSNull()],
                                in: source.info, in: Web.world) { [weak self] _ in
            guard self?.request == stop else { return }
            guard web.fullscreenState == .notInFullscreen else { finish(); return }
            // Native exit can wait for a hidden source to become visible. Close it,
            // then preserve playback: closing all presentations also pauses media.
            web.closeAllMediaPresentations { [weak self] in
                guard self?.request == stop else { return }
                guard previous.built === web else { finish(); return }
                web.callAsyncJavaScript("return window.__searchPiP?.returned(documentID, token);",
                                        arguments: ["documentID": source.id, "token": token as Any? ?? NSNull()],
                                        in: source.info, in: Web.world) { _ in finish() }
            }
        }
    }

    private func clear() {
        timeout?.cancel()
        timeout = nil
        tab?.floating = false
        tab = nil
        frame = nil
        request = nil
        starting = false
        stopping = false
        automatic = false
    }

    private func exit(_ tab: Tab, frame: VideoRelay.Frame, token: String?) {
        tab.built?.callAsyncJavaScript("window.__searchPiP?.exit(documentID, token);",
                                      arguments: ["documentID": frame.id, "token": token as Any? ?? NSNull()],
                                      in: frame.info, in: Web.world, completionHandler: nil)
    }
}

/// Each frame reports its own media from Search's isolated world, including cross-origin embeds.
@MainActor
final class VideoRelay: NSObject, WKScriptMessageHandler {
    static let name = "searchVideo"
    weak var tab: Tab?
    struct Frame {
        let id: String
        let info: WKFrameInfo
        let available: Bool
        let playing: Bool
        let area: Double
    }
    private var frames: [String: Frame] = [:]

    func best(playing: Bool) -> Frame? {
        frames.values.filter { $0.available && (!playing || $0.playing) }.max {
            if $0.playing != $1.playing { return !$0.playing }
            return $0.area < $1.area
        }
    }

    func reset() {
        if let tab { Shared.floater.lost(tab); tab.hasVideo = false }
        frames.removeAll()
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let tab, message.webView === tab.built,
              let body = message.body as? [String: Any],
              let id = body["id"] as? String, UUID(uuidString: id) != nil,
              let gone = body["gone"] as? Bool else { return }
        if gone {
            frames.removeValue(forKey: id)
            Shared.floater.lost(tab, document: id)
        } else {
            guard let available = body["available"] as? Bool, let playing = body["playing"] as? Bool,
                  let active = body["active"] as? Bool, let area = body["area"] as? Double,
                  area.isFinite, area >= 0 else { return }
            let frame = Frame(id: id, info: message.frameInfo, available: available, playing: playing, area: area)
            frames[id] = frame
            Shared.floater.changed(tab, frame: frame, active: active, token: body["token"] as? String)
        }
        tab.hasVideo = best(playing: false) != nil
    }

    static let script = #"""
    (() => {
      if (window.__searchPiP) return;
      const bytes = crypto.getRandomValues(new Uint8Array(16));
      bytes[6] = (bytes[6] & 15) | 64; bytes[8] = (bytes[8] & 63) | 128;
      const hex = Array.from(bytes, b => b.toString(16).padStart(2, '0')).join('');
      const id = [hex.slice(0,8),hex.slice(8,12),hex.slice(12,16),hex.slice(16,20),hex.slice(20)].join('-');
      let token = null, target = null, pending = null, cancelled = null, returning = null, last = '', queued = false;
      const active = v => v.webkitPresentationMode === 'picture-in-picture';
      const supports = v => !v.disablePictureInPicture && v.readyState >= 2 && v.videoWidth > 0
        && typeof v.webkitSetPresentationMode === 'function'
        && v.webkitSupportsPresentationMode?.('picture-in-picture');
      const playing = v => !v.paused && !v.ended;
      const area = v => { const r = v.getBoundingClientRect(); return r.width * r.height; };
      // shortcut: shadow-root players are not enumerated; extend discovery when a supported site needs it.
      function best(automatic) {
        return Array.from(document.querySelectorAll('video')).filter(v => supports(v) && (!automatic || playing(v)))
          .sort((a,b) => Number(playing(b)) - Number(playing(a)) || area(b) - area(a))[0];
      }
      function report(gone = false) {
        const videos = Array.from(document.querySelectorAll('video'));
        const out = videos.find(active), candidate = best(false);
        const state = {id, gone, available: !!candidate, playing: !!candidate && playing(candidate),
          area: candidate ? area(candidate) : 0, active: !!out, token};
        const value = JSON.stringify(state);
        if (value === last) return;
        last = value;
        window.webkit.messageHandlers.searchVideo.postMessage(state);
      }
      function schedule() {
        if (queued) return;
        queued = true;
        queueMicrotask(() => { queued = false; report(); });
      }
      function exit(documentID, expected) {
        if (documentID !== id || (expected !== null && expected !== token)) return false;
        cancelled = token;
        if (pending) pending.finish(false);
        const v = Array.from(document.querySelectorAll('video')).find(active);
        returning = v ? {video:v, playing:playing(v), token:expected} : null;
        if (v) v.webkitSetPresentationMode('inline');
        return true;
      }
      window.__searchPiP = {
        exit,
        returned(documentID, expected) {
          if (documentID !== id || returning?.token !== expected) return false;
          const saved = returning; returning = null;
          if (saved.playing && saved.video.isConnected && saved.video.paused && !saved.video.ended)
            return saved.video.play().then(() => true, () => false);
          return true;
        },
        enter(documentID, next, automatic) {
          if (documentID !== id) return false;
          const v = best(automatic);
          if (!v) return false;
          if (pending) pending.finish(false);
          token = next; target = v; cancelled = null;
          return new Promise(resolve => {
            const request = {finish(ok) {
              if (pending !== request) return;
              clearTimeout(request.timer); clearInterval(request.retry); pending = null;
              resolve(ok);
            }};
            pending = request;
            request.timer = setTimeout(() => request.finish(active(v)), 1800);
            // WebKit can still be closing its native window after reporting inline.
            const attempt = () => {
              if (active(v)) return;
              try { v.webkitSetPresentationMode('picture-in-picture'); }
              catch (_) { request.finish(false); }
            };
            request.retry = setInterval(attempt, 100);
            attempt();
          });
        }
      };
      for (const event of ['loadedmetadata','loadeddata','canplay','play','pause','ended','emptied','webkitpresentationmodechanged','enterpictureinpicture','leavepictureinpicture']) {
        document.addEventListener(event, e => {
          if (!(e.target instanceof HTMLVideoElement)) return;
          if (event === 'enterpictureinpicture' && pending && e.target === target) pending.finish(true);
          if (event === 'webkitpresentationmodechanged') {
            if (active(e.target)) {
              if (cancelled !== null && cancelled === token) e.target.webkitSetPresentationMode('inline');
            } else {
              if (!pending) token = null;
            }
          }
          schedule();
        }, true);
      }
      new MutationObserver(records => {
        if (records.some(r => (r.type === 'attributes' && r.target instanceof HTMLVideoElement) || [...r.addedNodes,...r.removedNodes].some(n =>
          n.nodeType === 1 && (n.matches('video') || n.querySelector('video'))))) schedule();
      }).observe(document.documentElement, {subtree:true, childList:true, attributes:true,
        attributeFilter:['disablepictureinpicture','src']});
      addEventListener('pagehide', () => { exit(id, null); report(true); });
      addEventListener('pageshow', () => { last = ''; schedule(); });
      report();
    })();
    """#
}

struct VideoDoor: View {
    @ObservedObject var browser: Browser
    @ObservedObject var tab: Tab
    @ObservedObject private var floater = Shared.floater

    var body: some View {
        if browser.prefs.showsPiPButton && (tab.hasVideo || floater.tab === tab) {
            let out = floater.tab === tab
            Door(icon: out ? "pip.exit" : "pip.enter", on: out,
                 help: out ? "Return Video to Page" : "Picture in Picture") {
                browser.toggleFloat()
            }
            .accessibilityLabel(out ? "Return Video to Page" : "Picture in Picture")
            .accessibilityIdentifier("picture-in-picture")
        }
    }
}

/// Sites with a player worth following into the little window.
///
/// Anywhere else, a playing video is as likely to be a background as a film,
/// and the difference isn't something a script can tell from the outside. So
/// the list is of places people go to watch, and the shortcut covers the rest.
enum Players {
    /// A host suffix, and for a few shops that also stream, the path that
    /// separates the film from the product page.
    private static let known: [(host: String, path: String?)] = [
        ("youtube.com", nil), ("youtu.be", nil), ("netflix.com", nil),
        ("primevideo.com", nil), ("amazon.com", "/gp/video"), ("amazon.fr", "/gp/video"),
        ("amazon.co.uk", "/gp/video"), ("amazon.de", "/gp/video"),
        ("disneyplus.com", nil), ("tv.apple.com", nil), ("twitch.tv", nil),
        ("vimeo.com", nil), ("dailymotion.com", nil), ("max.com", nil), ("hbomax.com", nil),
        ("canalplus.com", nil), ("mycanal.fr", nil), ("arte.tv", nil), ("france.tv", nil),
        ("tf1.fr", nil), ("6play.fr", nil), ("crunchyroll.com", nil), ("plex.tv", nil),
        ("peacocktv.com", nil), ("hulu.com", nil), ("paramountplus.com", nil),
        ("molotov.tv", nil), ("ocs.fr", nil), ("mubi.com", nil), ("criterionchannel.com", nil),
        ("ted.com", nil), ("nebula.tv", nil), ("curiositystream.com", nil),
    ]

    static func knows(_ url: URL?) -> Bool {
        guard let url, let host = url.host()?.lowercased() else { return false }
        let path = url.path().lowercased()
        return known.contains { entry in
            guard host == entry.host || host.hasSuffix("." + entry.host) else { return false }
            guard let needle = entry.path else { return true }
            return path.hasPrefix(needle)
        }
    }
}

/// Sites whose videos never float out on their own: the site card's Don't
/// Float Videos Here (#267). Only switching tabs or apps is held back; ⇧⌘P
/// still lifts one by hand. Kept by host, as a site's sound is, and
/// forgotten with the other site choices (Browser.forgetCaptureChoices).
enum Grounded {
    static let prefix = "nofloat."

    static func holds(_ host: String) -> Bool {
        Store.settings.bool(forKey: prefix + host)
    }

    /// Off keeps nothing, as Autoplay's does.
    static func set(_ on: Bool, for host: String) {
        if on {
            Store.settings.set(true, forKey: prefix + host)
        } else {
            Store.settings.removeObject(forKey: prefix + host)
        }
    }
}
