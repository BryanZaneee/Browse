# Browse

An independent, community-maintained fork of [Search](https://github.com/driceroland/Search), a small WebKit browser for macOS. The app is named Browse and has its own bundle ID, data folder, keychain labels, icon, and GitHub update feed.

> **Release status:** The signed release workflow is ready, but Browse downloads are not published until the repository has its own Apple Developer ID certificate and notarization credentials configured (see [Releasing](#releasing)).

![Browse, with its tabs down the left and a page taking the rest of the window](.github/screenshot.png)

Browse builds on Search's open-source code and keeps the original project linked above. Browse releases and updates are managed from this repository.

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
- **Video that follows you.** `⇧⌘P` uses macOS Picture in Picture to lift video out of the page.
- **Passwords, in your keychain.** Browse offers to save a sign-in once it has actually worked, and offers your saved accounts and the Mac's passkeys for the site under the field when you click it — never filling anything on its own. Passwords live in the macOS keychain under Browse. Bring yours in from Chrome, Arc, Dia, Brave or Edge in one click; nothing leaves the Mac.
- **Light, dark, or the Mac's own.** The frame and the pages follow.
- **Bookmarks, history, downloads** — each a panel, each searchable, each one keystroke away.
- **Chrome extensions, without Chrome.** Paste a Chrome Web Store link in Settings › Extensions, or open the extension's page in Browse and press Add. It runs on WebKit's own extension engine — the one Safari uses — and where Chrome has APIs WebKit doesn't (bookmarks, history, downloads, side panel, offscreen documents, fonts, notifications, speech), Browse fills them in itself. They live behind the puzzle button; pin the ones you use often. Building your own? Load its folder as an unpacked extension and press Reload after each change, as in Chrome's developer mode. macOS 15.4 or later.
- **In-tab history.** Type in the address field to find pages from your history and open tabs, then choose a result without leaving the current tab.
- **Updates:** signed Browse releases check at launch and hourly. The updater verifies the appcast signature, archive checksum, app identifier, and Developer ID before replacing the app.

## What it doesn't do

On purpose:

- No extension you have to install to feel at home. Blocking ads, hiding clutter, reading mode, picture-in-picture and passwords are built in; extensions are there for everything else.
- No sync, no account, no cloud. Your tabs, history and passwords are on your Mac and nowhere else.
- No telemetry, no analytics, no crash reports sent anywhere.
- Multiple windows, each with its own tabs and space.

## Privacy, concretely

| What | Where it is | Who can read it |
|---|---|---|
| Passwords | The macOS login keychain, as ordinary keychain items tagged `Browse` | Browse; macOS controls app access and may ask you to approve it. |
| History, bookmarks, open tabs, hidden elements | Small JSON files in `~/Library/Application Support/Browse/` | You. |
| Cookies and site data | WebKit's own store for the app | The sites that set them, as in any browser. |
| Extensions | Unpacked in `~/Library/Application Support/Browse/Extensions/`, their data in WebKit's extension store | Each extension, within the permissions you accepted when adding it. |
| Update checks | Signed appcast and release archives on this repository's GitHub Releases | GitHub receives the request; Browse sends no profile or browsing data. |
| Anything else | No account, sync, analytics or telemetry | — |

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

Saved-data failures are reported with a chance to keep working before quitting; [recovery details](docs/PERSISTENCE-RECOVERY.md) explain preserved unreadable files.

## For developers

### Why the source is here

So anyone can read exactly what a browser handling their passwords and history is doing, build it themselves, or fix something that bothers them. The code is small enough to actually read — about 42,000 lines of Swift, no dependencies beyond what Apple ships with macOS, one file per concern.

### Building it

- macOS 14 or later, Xcode 16 / Swift 6 toolchain
- `swift build` — builds the command-line executable; `swift run` launches it
- `./build.sh` — assembles a double-clickable `Browse.app` in `build/`, ad-hoc signed so it runs on your own Mac

`swift build` refers to the internal SwiftPM product named Search. After `./build.sh debug`, use `./fresh.sh --visible` for a disposable review window, or `./fresh.sh` for a hidden scripted test. Direct development launches refuse to open an unprepared profile. Each test world has an owned bundle identity, files, preferences and WebKit stores; installed Browse still uses `~/Library/Application Support/Browse/`. See [test isolation](docs/TEST-ISOLATION.md).

A local build is ad-hoc signed, so macOS may require right-click → Open the first time. It does not check for or install updates. `./build.sh release dmg` creates archives for local inspection; `./build.sh release ship` signs and notarizes both archives, staples the DMG, and creates the signed update feed.

### Releasing

Push a tag matching `VERSION` (for example, set `VERSION` to `1.0.6`, then push `v1.0.6`) to run `.github/workflows/release.yml`. It builds and notarizes Apple Silicon and Intel apps, signs separate update feeds, and attaches the downloads to a GitHub release. Configure these repository Actions secrets first:

- `BROWSE_DEVELOPER_ID_P12`: base64-encoded Developer ID Application certificate in PKCS#12 format.
- `BROWSE_CERTIFICATE_PASSWORD`: password for that certificate.
- `BROWSE_NOTARY_APPLE_ID`, `BROWSE_NOTARY_PASSWORD`, `BROWSE_NOTARY_TEAM_ID`: Apple notarytool credentials for the same Developer team.

The updater learns the trusted Team ID from the installed signed app, so every release must use the same Developer ID team. An unsigned local build has no updater identity. Passkeys, the local AI engine, and OpenRouter sign-in remain disabled for Browse until their entitlements, signed engine release, and OAuth callback setup are ready.

### How it's put together

- **SwiftUI** for everything drawn, **AppKit** for the handful of things SwiftUI doesn't reach on macOS (the window's title bar, dragging the window by an empty part of the tab row), **WKWebView** for pages.
- One `Tab` per page. Its web view is built lazily — a tab restored from last session doesn't cost a process until you switch to it. That's most of why launching with twenty tabs is still instant. Each page runs in WebKit's own content process, as in Safari; a tab you close is really gone.
- The ad blocker is a `WKContentRuleList` compiled once at launch and enforced inside WebKit's networking, before a request is made — zero cost at run time, unlike a JavaScript blocker.
- Hidden elements are a per-site list of selectors injected as a stylesheet at document start, so nothing is ever seen appearing and vanishing.
- Every colour is a light/dark pair in `Design.swift`, resolved by the window's appearance; nothing else in the code knows which mode it is in.
- Extensions run on `WKWebExtension` (macOS 15.4+). `Crx.swift` fetches an extension from the Chrome Web Store's public update address and checks the CRX3 signature against the extension's id before anything is unpacked. `Extensions.swift` is the browser's side of WebKit's contract — tabs, the window, permissions, popups. `ExtensionShims.swift` adds, at install, a small script to the extension's worker, pages and content scripts: it defines the Chrome APIs WebKit lacks — `userScripts`, `privacy`, `browsingData`, `sessions`, the old FileSystem API and more — as calls answered natively by Browse, and mends the places where WebKit behaves differently from Chrome: replies from pages that don't answer, listeners added after a worker starts, workers WebKit loses track of, members and constants it leaves out. Extension pages are served from `chrome-extension://<id>/`, the address they have in Chrome, so servers and sites recognise them. `./bench ext-*` drives all of it from the shell against a test run. `ExtensionNative.swift` speaks Chrome's native messaging to hosts registered in Chrome's `NativeMessagingHosts` folders.
- `Sources/Search/` is one file per concern: `Vault.swift` is the keychain, `Shield.swift` the ad blocker, `Curtain.swift` the hidden elements, `Session.swift` what comes back at launch, `Updater.swift` the update, `Bench.swift` the test socket, and so on. There's no framework of its own to learn first.

### Testing it without closing it

Turn on **Settings › General › Let a script drive Browse** and the running app listens on a Unix socket in its own folder (readable by your user only). `./bench` at the root of the repository speaks it:

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

MIT — see [LICENSE](LICENSE). The source license does not transfer Search's name or original icon; Browse uses its own app name and icon.
