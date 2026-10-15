import AppKit
import WebKit

// Only metadata is read from the system board; all contents below are synthetic.
let systemBoard = NSPasteboard.general
let systemCount = systemBoard.changeCount
TestPasteboard.install()
let board = NSPasteboard.general
precondition(board.name.rawValue.hasPrefix("org.browse.test."), "clipboard isolation was not installed")
precondition(NSPasteboard(name: .general).name == board.name, "named factory bypasses isolation")
func unchanged() {
    precondition(systemBoard.changeCount == systemCount, "system clipboard changed")
}
func expect(_ value: String, _ stage: String) {
    unchanged()
    precondition(board.string(forType: .string) == value, "synthetic clipboard mismatch")
    print("PASS \(stage)")
}
let text = NSTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 50))
text.string = "synthetic native copy"
text.selectAll(nil)
text.copy(nil)
expect("synthetic native copy", "NSTextView copy")
text.cut(nil)
precondition(text.string.isEmpty)
text.paste(nil)
precondition(text.string == "synthetic native copy")
unchanged()
print("PASS NSTextView cut and paste")

_ = NSApplication.shared
NSApp.setActivationPolicy(.prohibited)
let config = WKWebViewConfiguration()
config.websiteDataStore = .nonPersistent()
precondition(config.preferences.responds(to: NSSelectorFromString("_setJavaScriptCanAccessClipboard:")))
config.preferences.setValue(true, forKey: "javaScriptCanAccessClipboard")
let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 400, height: 200), configuration: config)
var finished = false
class Delegate: NSObject, WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webView.evaluateJavaScript("document.querySelector('textarea').select(); document.execCommand('copy')") { value, error in
            precondition(error == nil && (value as? Bool) == true, "DOM copy failed")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                expect("synthetic DOM copy", "document.execCommand copy")
                webView.callAsyncJavaScript("await navigator.clipboard.writeText('synthetic async copy'); return true", arguments: [:], in: nil, in: .page) { result in
                    guard case .success = result else { fatalError("navigator.clipboard.writeText failed") }
                    expect("synthetic async copy", "navigator.clipboard.writeText")
                    finished = true
                }
            }
        }
    }
}
let delegate = Delegate()
web.navigationDelegate = delegate
web.loadHTMLString("<!doctype html><textarea>synthetic DOM copy</textarea>", baseURL: URL(string: "https://clipboard.example.test/")!)
let deadline = Date().addingTimeInterval(15)
while !finished && Date() < deadline {
    RunLoop.current.run(until: Date().addingTimeInterval(0.05))
}
precondition(finished, "WebKit clipboard fixture timed out")
unchanged()
board.releaseGlobally()
print("PASS system clipboard changeCount unchanged throughout")
