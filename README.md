# Browse

An independent community fork of [Search](https://github.com/driceroland/Search), a small WebKit browser for macOS. This repository is named Browse; the app itself has not been rebranded yet.

> **Fork status:** Builds still identify themselves as Search and use Search's app identifier, data folder, and Office Commun signed update feed. There are no Browse releases or downloads yet. Don't treat a source build as an independent Browse release.

![Search, with its tabs down the left and a page taking the rest of the window](.github/screenshot.png)

The original Search app and its downloads remain at [Office Commun](https://officecommun.com/search). Those downloads are signed and updated by the original project, not by this fork.

---

## What it is

The browser keeps the page in focus. Tabs can run across the top or down the side, and you type an address or search words in one field.

It uses **WebKit**, the engine built into macOS, rather than bundling Chromium.

## What it does

- **One field.** Type an address and you go there; type words and you search. It finishes addresses from your own history and never sends what you type anywhere until you press Return.
- **Tabs that stay out of the way.** Pin the pages you keep open all day and they shrink to a letter or their icon. Tabs from your last session come back instantly and cost nothing until you click them. `⌘K` lists your open tabs by name.
- **Two pages side by side.** Turn on Split View in Settings › Tabs, then drag a tab onto a page or choose Tabs › Split Current Page. Drag the divider to resize the panes; the outlined pane receives page commands. Pairs and their widths come back with their Space, including after a restart.
- **Reading mode.** `⇧⌘R` strips a page down to the article.
- **Hide anything, for good.** `⇧⌘H`, then click a cookie banner, a newsletter overlay, a rail of "related" nonsense — it goes, and it is still gone on that site next time, before the page has drawn a single frame.
- **An ad blocker that runs before the page.** Third-party trackers and ad networks are stopped at the network level, so there is nothing to render and nothing to slow down. On by default, off per site if something breaks.
- **Video that follows you.** `⇧⌘P` lifts the video out of the page into a small window that stays above everything, including other apps.
- **Passwords, in your keychain.** Search offers to save a sign-in once it has actually worked, and offers your saved accounts, and the Mac's passkeys for the site, under the field when you click it — the way Safari does, never filling anything on its own. Everything lives in the macOS keychain, encrypted by the system, readable only by Search. Bring yours in from Chrome, Arc, Dia, Brave or Edge in one click; nothing leaves the Mac.
- **Light, dark, or the Mac's own.** The frame and the pages follow.
- **Bookmarks, history, downloads** — each a panel, each searchable, each one keystroke away.
- **Chrome extensions, without Chrome.** Paste a Chrome Web Store link in Settings › Extensions, or open the extension's page in Search and press Add. It runs on WebKit's own extension engine — the one Safari uses — and where Chrome has APIs WebKit doesn't (bookmarks, history, downloads, side panel, offscreen documents, fonts, notifications, speech, OAuth sign-in), Search fills them in itself. They live behind the puzzle button; pin the ones you use often. Building your own? Load its folder as an unpacked extension and press Reload after each change, as in Chrome's developer mode. macOS 15.4 or later.
- **Updates:** the current app code checks at launch and hourly, and accepts updates signed by Office Commun. That feed belongs to Search; Browse does not have its own update service yet.

## What it doesn't do

On purpose:

- No extension you have to install to feel at home. Blocking ads, hiding clutter, reading mode, picture-in-picture and passwords are built in; extensions are there for everything else.
- No sync, no account, no cloud. Your tabs, history and passwords are on your Mac and nowhere else.
- No telemetry, no analytics, no crash reports sent anywhere. The current Search updater also contacts the upstream update feed.
- Multiple windows, each with its own tabs and space.

## Privacy, concretely

| What | Where it is | Who can read it |
|---|---|---|
| Passwords | The macOS login keychain, as ordinary keychain items tagged `Search` | Search, signed by Office Commun. Any other app triggers the system's permission dialog. |
| History, bookmarks, open tabs, hidden elements | Small JSON files in `~/Library/Application Support/Search/` | You. |
| Cookies and site data | WebKit's own store for the app | The sites that set them, as in any browser. |
| Extensions | Unpacked in `~/Library/Application Support/Search/Extensions/`, their data in WebKit's extension store | Each extension, within the permissions you accepted when adding it. |
| Anything else | Nowhere. There is no server. | — |

A **private tab** (`⇧⌘N`) has its own cookie jar and leaves nothing behind when it closes.

Apps you allow in System Settings › Privacy & Security › Automation can read the address and title of your tabs with AppleScript; private tabs are never shown.

## Keyboard

| | |
|---|---|
| `⌘L` address · `⌘K` switch tab · `⌘T` new tab · `⌘W` close · `⇧⌘T` reopen | `⌘[` `⌘]` back, forward · `⇧⌘[` `⇧⌘]` previous, next tab · `⌘1`–`⌘9` jump |
| `⇧⌘S` tabs across the top or down the left · `⌘S` fold the sidebar away · `⇧⌘B` bookmark this page | `⇧⌘R` reading mode · `⇧⌘P` float the video · `⇧⌘H` hide something · `⇧⌘U` what is hidden here |
| `⌘F` find · `⌘D` duplicate tab · `⇧⌘C` copy address · `⇧⌘V` paste and go | `⌘Y` history · `⇧⌘J` downloads · `⌘,` settings · `⌥⌘L` passwords |

`⌘R` reloads the page; `⌥⌘R` reloads it from origin, checking everything cached with the site again, as Safari's Reload Page From Origin.

`⌃Tab` and `⌃⇧Tab` walk along the row of tabs; `Tab` stays the page's, for moving through a form. `esc` puts away whatever is open.

With Split View on, `⌥⌘N` splits the current page and `⌃⌘←` / `⌃⌘→` go from one page to the other. `⌘W` closes the focused tab and gives the remaining page the whole area. Tabs › Separate Split Tabs keeps both tabs open separately.

---

## For developers

### Why the source is here

So anyone can read exactly what a browser handling their passwords and history is doing, build it themselves, or fix something that bothers them. The code is small enough to actually read — about 42,000 lines of Swift, no dependencies beyond what Apple ships with macOS, one file per concern.

### Building it

- macOS 14 or later, Xcode 16 / Swift 6 toolchain
- `swift build` — builds the command-line executable; `swift run` launches it
- `./build.sh` — assembles a real, double-clickable `Search.app` in `build/`, ad-hoc signed so it runs on your own Mac

These commands still produce Search, using Search's existing bundle identifier and data location. This fork needs its own app identity and signed update feed before it can ship Browse builds safely.

A build you make yourself won't be notarized or carry Office Commun's Developer ID, so the first launch needs a right-click → Open (or an allow in System Settings → Privacy & Security). That's expected — it's the same thing that happens with any app that isn't from the App Store or a notarized DMG. Your own build also keeps its passwords apart from a signed Search's: the keychain tells the two apart by their signatures.

`./build.sh release dmg` also makes `Search.dmg` / `Search.zip`. `./build.sh release ship` additionally notarizes and staples — that step needs a Developer ID certificate and Apple credentials, so it only really does anything for Office Commun's own releases.

### How it's put together

- **SwiftUI** for everything drawn, **AppKit** for the handful of things SwiftUI doesn't reach on macOS (the window's title bar, dragging the window by an empty part of the tab row), **WKWebView** for pages.
- One `Tab` per page. Its web view is built lazily — a tab restored from last session doesn't cost a process until you switch to it. That's most of why launching with twenty tabs is still instant. Each page runs in WebKit's own content process, as in Safari; a tab you close is really gone.
- The ad blocker is a `WKContentRuleList` compiled once at launch and enforced inside WebKit's networking, before a request is made — zero cost at run time, unlike a JavaScript blocker.
- Hidden elements are a per-site list of selectors injected as a stylesheet at document start, so nothing is ever seen appearing and vanishing.
- Every colour is a light/dark pair in `Design.swift`, resolved by the window's appearance; nothing else in the code knows which mode it is in.
- Extensions run on `WKWebExtension` (macOS 15.4+). `Crx.swift` fetches an extension from the Chrome Web Store's public update address and checks the CRX3 signature against the extension's id before anything is unpacked. `Extensions.swift` is the browser's side of WebKit's contract — tabs, the window, permissions, popups. `ExtensionShims.swift` adds, at install, a small script to the extension's worker, pages and content scripts: it defines the Chrome APIs WebKit lacks — `userScripts`, `privacy`, `browsingData`, `sessions`, the old FileSystem API and more — as calls answered natively by Search, and mends the places where WebKit behaves differently from Chrome: replies from pages that don't answer, listeners added after a worker starts, workers WebKit loses track of, members and constants it leaves out. Extension pages are served from `chrome-extension://<id>/`, the address they have in Chrome, so servers and sites recognise them. `./bench ext-*` drives all of it from the shell against a test run. `ExtensionNative.swift` speaks Chrome's native messaging to hosts registered in Chrome's `NativeMessagingHosts` folders.
- `Sources/Search/` is one file per concern: `Vault.swift` is the keychain, `Shield.swift` the ad blocker, `Curtain.swift` the hidden elements, `Session.swift` what comes back at launch, `Updater.swift` the update, `Bench.swift` the test socket, and so on. There's no framework of its own to learn first.

### Testing it without closing it

Turn on **Settings › General › Let a script drive Search** and the running app listens on a Unix socket in its own folder (readable by your user only). `./bench` at the root of the repository speaks it:

```
./bench open https://example.com     # a tab of its own, at the end of your row, marked with a flask
./bench wait 2e7e7e89                 # until it has loaded
./bench text 2e7e7e89                 # the page's text
./bench shot 2e7e7e89 out.png         # a picture of it
./bench click 2e7e7e89 "button.go"    # click, type, submit — through the page's own events
./bench probe                         # the window's state: open panels, a modal, every window
./bench close all
```

Bench tabs are never selected for you, never enter the session or the history, and go when the script says so. It is how this browser is tested while somebody is using it.

`python3 Tests/split_view.py`, after `./build.sh`, checks Split View through the app's own model in a hidden test run with its own settings and files, all removed afterwards. It never makes or shows a window; what can only be seen (dragging onto a page's edge, the divider under the pointer, the motion) is checked by hand on a release candidate.

### Contributing

Issues and pull requests are genuinely welcome — see [CONTRIBUTING.md](CONTRIBUTING.md) for how this is reviewed and what tends to get merged. The short version: small changes, no new dependencies, nothing that phones home. Found a security problem? Please report it privately, as [SECURITY.md](SECURITY.md) says.

### License

MIT — see [LICENSE](LICENSE). The license covers the source code. Search's name and icon belong to Office Commun; this fork's repository name does not grant rights to those marks.
