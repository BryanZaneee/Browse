# Browse foundation and upstream audit

Assessment date: **2026-10-14**. Browse [`3241006`](https://github.com/BryanZaneee/Browse/commit/3241006e72b8b4c4212095552eaed8f9d99f226a); Search [`615bbca`](https://github.com/driceroland/Search/commit/615bbca0ecdda876973b325476587d3d8b4c2bb9).

**What this repo does:** Browse is a native macOS browser built with SwiftUI, AppKit and WebKit. It combines tabs, Spaces, split views, reading tools, passwords, downloads and a substantial Chrome-extension compatibility layer. It also contains disabled AI infrastructure.

**Assessment:** This is a credible foundation for a lightweight, native browser. It is **not ready to call rock solid or release from the audited checkout**. Two rebrand regressions block building and packaging; the automation CLI targets the old app; inherited correctness problems affect persistence, window lifetime, extensions and address parsing. The right first milestone is a trustworthy Browse release with repeatable validation. Adding AI or importing a broad collection of features before that would obscure the baseline.

No application source was changed, no PR was merged, and nothing was published. Test-only experiments used disposable source copies. This audit adds documentation only.

## Coverage and how to read this report

| Upstream records | Open | Closed without GitHub merge | Merged | Total |
|---|---:|---:|---:|---:|
| Issues | 44 | 203 | — | 247 |
| Pull requests | 62 | 192 | 103 | 357 |
| Total | 106 | 395 | 103 | **604** |

- [OPEN-TRIAGE.md](OPEN-TRIAGE.md): individual disposition, priority, effort and overlap for **all 44 open issues and all 62 open PRs**.
- [ALL-ITEMS.md](ALL-ITEMS.md): complete index of all 604 records, including historical work.
- [INVENTORY.json](INVENTORY.json): titles, bodies, source URLs, authors, dates, PR head revisions, extracted references, comment URLs and recommendations.
- [VALIDATION.md](VALIDATION.md): commands, observed results and verification boundaries.

The collection includes 984 conversation comments, nine inline review comments, current open-PR metadata and all 62 open-PR diffs. Open items received individual triage; deeper source and patch review concentrated on foundation risks and promising integrations. Historical titles were surveyed, with selected bodies/discussions and landing commits traced. **This is an exhaustive inventory and open-item triage, not a claim that all 604 reports were reproduced or all historical patches fully audited.**

At collection time, 44 open PRs conflicted with **Search main**; 18 were reported mergeable. Browse can have additional conflicts. None of the 62 had formal GitHub reviews or a status-check rollup on its current last commit. That does not mean no review or tests: maintainers leave substantive reviews in conversation comments and several authors link external CI. All 62 were non-draft in live metadata, even where descriptions still called the work a draft. Every open issue was unassigned, but discussion establishes ownership for many.

“Adopt” throughout means a promising candidate to rebase, inspect and validate against Browse—not permission to merge its current branch blindly. Priorities are Browse impact: P0 release/validation blocker; P1 foundation; P2 useful correctness/polish; P3 optional/later.

## What Browse has already inherited

Git ancestry shows Browse is **25 commits ahead and zero behind Search main**. Fetching and merging upstream main will not supply the outstanding fixes: they live in unmerged PRs. Source VERSION is 1.0.6 in Browse versus 1.0.5 in Search; that is not evidence of a working signed release.

Browse already contains the branches behind upstream [#593 native PiP](https://github.com/driceroland/Search/pull/593) and [#597 autocomplete](https://github.com/driceroland/Search/pull/597). Those upstream PRs remain open. Browse's own [#2 PiP](https://github.com/BryanZaneee/Browse/pull/2) also remains open despite its feature branch being in main's ancestry. Do not merge these features a second time. Validate them and reconcile tracking instead.

The fork also has [#1 Jev native tools](https://github.com/BryanZaneee/Browse/pull/1), which should wait for the foundation milestone; [#3 Read Later](https://github.com/BryanZaneee/Browse/pull/3) and [#5 Copy Clean Link](https://github.com/BryanZaneee/Browse/pull/5) are planning work, not finished implementations. [#4 autocomplete](https://github.com/BryanZaneee/Browse/pull/4) is merged. Remote branches for periodic extension updates and local paths exist but are not in main.

## Architecture: what to keep, what to watch

| Area | Current design | Consequence for Browse |
|---|---|---|
| App and engine | SwiftPM executable, SwiftUI/AppKit, system WKWebView; macOS 14 minimum; extension engine requires macOS 15.4+. Swift tools 6 with Swift 5 language mode. | Good native starting point without bundling Chromium. WebKit and OS-version behavior remain part of the compatibility contract. |
| Dependency footprint | No external Swift package dependencies in the app package. Optional local AI helper uses llama.cpp; build/distribution tooling has additional dependencies. | Keep the core small. “No dependencies” should not be read as covering every optional component and build tool. |
| Tabs and windows | Browser model per window; Tab owns a lazily created web view; saved tabs wake on demand. Split views, small windows and peek add ownership paths. | Preserve lazy creation. Window/tab transfer and close paths deserve concentrated testing. |
| Memory | Background sleep after a delay, memory-pressure handling, exclusions for visible, pinned, playing, capturing, downloading or unsaved pages. | Small app size is not a RAM guarantee. Measure the host app and WebKit child processes separately. |
| State | Local JSON for sessions, pins, history, bookmarks and settings; shared state for some resources; serialized atomic writes. | Sensible existing primitives, with error-reporting and corruption-recovery gaps described below. |
| Spaces | Explicitly isolated Spaces use different WebKit cookie stores; ordinary Spaces may share sign-ins. History, bookmarks and extensions are not separate full profiles. | Do not promise work/personal isolation beyond what is actually isolated. This matters before adding email identities. |
| Credentials | Native keychain storage, site matching and user-initiated fill. Browse's passkey entitlement remains disabled pending its own setup. | Keep secrets out of page extraction and AI context. Password-manager compatibility is a release criterion. |
| Extensions | WKWebExtension plus CRX verification, install preparation, native messaging and many shims for Chrome APIs. | Valuable functionality and a major maintenance burden. Unsupported APIs and worker lifecycle differences prevent universal Chrome compatibility. |
| Updates | Signed appcast, archive checksum, bundle/team/build checks and replacement rollback. | Good mechanisms; Browse still needs a verified signed/notarized install-update-rollback exercise. |
| Automation | App-owned bench socket and isolated test worlds. | Useful existing infrastructure; repair branding and identity before trusting it. |

There are approximately **51,017 Swift source lines under Sources/Search**. Several responsibilities are concentrated in large files: Browser (~5,161 lines), ExtensionShims (~4,436), Bench (~3,155), Tab (~2,154) and Extensions (~2,008). This is still navigable, but extensions and window/session coordination dominate the risk. Do not start a broad architectural rewrite: fix shared failure points and extract responsibilities only when a concrete change warrants it.

The code already includes useful defensive work: CRX identity/signature validation, extension path boundaries and atomic replacement, keychain/site separation, corrupt session/history/bookmark quarantine, and checked updater identity. These are reasons to preserve the architecture, not evidence that the entire security surface has been certified. Several features use private WebKit selectors; a supported-OS test matrix is essential.

## Must fix before a foundation release

### 1. P0 — The current checkout does not compile

**Evidence:** `swift test` fails at [Store.swift](../../../Sources/Search/Store.swift), line 111. `Store.folder` became a multi-statement closure during rebranding but its final URL expression has no `return`.

**Effect:** A clean checkout cannot reach its tests or produce the executable. This is a Browse regression, not an upstream feature dependency.

**Smallest fix:** Restore the return. The isolated experiment with that one-line change built successfully and reached all 82 XCTest cases. Keep build/test checks on every PR so this cannot silently recur.

### 2. P0 — App packaging fails independently of the Swift package

**Evidence:** After the temporary Store fix, `./build.sh debug` fails at [Icon/icon.swift](../../../Icon/icon.swift), lines 98–101. The remaining Icon Composer SVG generation references undefined `canvas` and `markData` from the removed Search mark.

**Effect:** A passing Swift package build would still not deliver Browse.app.

**Smallest fix:** Make both generated icon formats consistently use Browse's icon source. Preserve Browse branding; do not restore Search's old mark just to compile. Add app-bundle assembly to the validation gate.

### 3. P0 — The automation CLI still addresses Search's data folder

**Evidence:** [bench](../../../bench), lines 139–141, computes `Application Support/Search` or `Search (world)`; Store now uses Browse. [Tests/split_view.py](../../../Tests/split_view.py), line 115, also identifies probe sockets using `/Search (`. I evaluated only the pure folder function, without contacting an app.

**Effect:** Commands fail to reach Browse or could reach an old Search instance if its bench socket is enabled. Tests can misidentify probe processes. The environment-isolation promise is not currently reliable end to end.

**Smallest fix:** Align app, CLI, harness, fresh-world cleanup, bundle identity and documentation. Borrow the worktree-isolation concept from [#497](https://github.com/driceroland/Search/pull/497), including the still-requested orphan-world cleanup. [#475](https://github.com/driceroland/Search/pull/475)'s different display name/icon alone does not isolate production data. Verify distinct worlds without touching a real profile.

### 4. P1 — Public domains can receive an implicit HTTP URL

**Evidence:** [Address.swift](../../../Sources/Search/Address.swift), lines 35–60, treats string prefixes `10.` and `192.168.` as private IPv4 addresses; its 172.16–31 check also accepts nonnumeric trailing labels. A standalone run of the current parser returned `http://10.io`, `http://192.168.1.1.example.com` and `http://172.16.foo.com`.

**Effect:** Some public-domain navigation begins on HTTP. A later redirect or site policy is not a substitute for selecting HTTPS correctly.

**Fix:** Adapt focused [#592](https://github.com/driceroland/Search/pull/592), addressing [#590](https://github.com/driceroland/Search/issues/590), and retain cases covering all three private ranges, actual local addresses, ports and public numeric-prefix names. Do not import the duplicate bundled in #603 as well.

### 5. P1 — Moving a pin to another Space can lose its persisted destination

**Evidence:** [Browser.swift](../../../Sources/Search/Browser.swift), `finishMove` around line 3036, updates the destination row/session without correctly updating the destination's authoritative pin definitions. The source aligns with the reproduction and patch in [#587](https://github.com/driceroland/Search/pull/587).

**Effect:** A moved pin can disappear on relaunch when the destination was not subsequently opened. This is a persistence defect, independent of whether Browse wants global pins.

**Fix:** Take #587's destination pin update and tier-order regression. Test an unopened destination, multiple windows and relaunch. Do not take the entire global-pins feature [#463](https://github.com/driceroland/Search/pull/463) just to obtain this fix. Source-confirmed here; its GUI reproduction was not rerun.

### 6. P1 — Closed windows have retained ownership paths

**Evidence:** [App.swift](../../../Sources/Search/App.swift), lines 367 and 1050–1061, holds a window in view state and stores key hooks; [Lights.swift](../../../Sources/Search/Lights.swift) retains entries and closures. [Windows.swift](../../../Sources/Search/Windows.swift), `retire` at line 262, does not remove all those roots. [#549](https://github.com/driceroland/Search/pull/549) identifies the connected lifetime problem and supplies cleanup.

**Effect:** Repeatedly opening and closing windows can retain browser/window state and grow host memory. This is distinct from intentional retention of the last closed window or WebKit's page memory.

**Fix:** Adapt #549, checking it together with [#431](https://github.com/driceroland/Search/pull/431) and [#554](https://github.com/driceroland/Search/pull/554). Validate repeated window cycles, small windows, reopen, key ownership and external-link launch. Upstream measurements were reviewed; no fresh Browse leak measurement was made.

### 7. P1 — Native messaging can miss replies and accept unbounded frames

**Evidence:** [ExtensionNative.swift](../../../Sources/Search/ExtensionNative.swift): `send` writes before registering its reply waiter; `connect` starts a process before installing callbacks; termination and stdout EOF both finish the pipe; the incoming UInt32 frame length lacks a limit even though outgoing messages are capped.

**Effect:** A fast native host can reply or exit before the browser is ready. Large frames can accumulate memory. Password-manager integrations depend on this path.

**Fix:** Adapt the latest [#483](https://github.com/driceroland/Search/pull/483), preserving its fake-host regressions: waiter/callback ordering, stdout drain through EOF, bounded input, disconnect and child cleanup. Author-reported tests are not a substitute for running them on Browse. This is not a claim of a demonstrated remote exploit.

### 8. P1 — Cross-window moves bypass the unsaved-form protection

**Evidence:** [Browser.swift](../../../Sources/Search/Browser.swift), `moveToWindow` at line 3078, detaches and calls `receive`; `receive` rehomes the tab into the destination Space. [Tab.swift](../../../Sources/Search/Tab.swift), `rehome` at line 1072, can discard/recreate its web view when stores differ. The analogous direct move-to-Space operation explicitly checks `tab.unsaved` first.

**Effect:** Moving a page with a draft into a window using a different cookie store can recreate it without the existing warning. This is also acknowledged in the inherited roadmap.

**Smallest fix:** Reuse the unsaved-state decision before detaching when the destination store differs, with cancellation leaving both windows intact. Cover menu moves and drag-out. No dedicated current upstream fix was identified; this is worthwhile Browse-owned work. Source finding, not a new live draft-loss reproduction.

### 9. P1 — Persistence errors are hidden; corruption recovery is inconsistent

**Evidence:** [Store.swift](../../../Sources/Search/Store.swift), `Disk.write` around line 173, suppresses directory/write failures. [Windows.swift](../../../Sources/Search/Windows.swift), `read` at line 337, converts decode failure into an empty list. [Pins.swift](../../../Sources/Search/Pins.swift), `load` at line 43, falls back and writes without quarantining an existing unreadable pins file. Other stores already use `Store.quarantine`.

**Effect:** A full or unwritable disk can leave the UI appearing saved while changes vanish after restart. A malformed windows/pins file can lose recoverable original bytes when fallback state is saved.

**Smallest fixes:** Surface failed persistence through the existing app notification/error path; preserve unreadable files consistently before replacement, distinguishing missing files from corrupt files. Verify injected write failures and malformed files using disposable directories. Atomic writes prevent partial replacement but do not make failed writes successful. These are source-confirmed error paths; disk exhaustion was not induced.

### 10. P0 process gate / P1 maintenance — No dependable automated release baseline

Only [release.yml](../../../.github/workflows/release.yml) is present under workflows. It publishes on version tags and does not run the test suite. There is no checked-in PR build/test workflow. The temporary buildable checkout runs **82 tests: 81 pass and one fails** on this host. The failing file-access test also fails on pristine upstream; its granted-file expectation differs from current WebKit behavior, so it is not evidence that the file-denial boundary failed.

Establish a clean PR gate: Swift build/tests, history and extension-file regressions, and unsigned app assembly. Adapt [#579](https://github.com/driceroland/Search/pull/579)'s download fixture/lifecycle improvements independently of the declined model-backed #580. Correct the file-access fixture while preserving denial checks. Signed release jobs should depend on a passing gate and a reviewed release candidate.

Also adopt [#589](https://github.com/driceroland/Search/pull/589): current extension update checks run at initialization, so a browser left running misses recurring checks. The focused timer and in-flight guard reuse existing throttle logic. This improves long-running extension maintenance without adding a feature surface.

## Integration order and overlap

### Highest-priority work, in order

1. **Repair Browse's build, icon packaging and automation identity; establish green CI.** These are prerequisites for safely evaluating everything else.
2. **Address/persistence:** #592, #587, then the local unsaved-move and persistence-error findings.
3. **Extension maintenance and host reliability:** #589 and #483. Password managers are daily-use infrastructure.
4. **Window lifetime and launch behavior:** #549 with #431/#554, followed by real memory measurements.
5. **Imports and navigation:** #507 → #415, #557, #509; verify permissions, files, delayed popups and POST behavior.
6. **Extension compatibility:** #521 and #600 with focused regressions; #453 only after its unresolved worker cases are exercised.
7. **Native interaction fixes and bounded polish:** #467, #568, then the small enhancements below.

### Easiest useful work not covered by a dedicated open implementation

1. Browse's missing return and icon-generator repair: very small code fixes, followed by build/package checks.
2. Browse's bench path mismatch: small fix, with end-to-end isolation verification before broader UI tests.
3. [#524 alternate local-file handler](https://github.com/driceroland/Search/issues/524): closed #527 is a reference; adapt Browse metadata and test Finder Open With without changing default handlers.
4. [#570 roomier sidebar rows](https://github.com/driceroland/Search/issues/570): optional polish; preserve truncation, hit targets and accessibility.
5. [#598 activate tabs on mouse-down](https://github.com/driceroland/Search/issues/598): small implementation but real drag/modified-click validation required. It is separate from animation tuning.

The open-issue table additionally marks #460 and #498 available; both require coordination with existing per-tab emulation or shortcut plumbing. Available does not mean assigned to us or trivial.

### Best value relative to integration effort

| Rank | Candidate | Value | Acceptance before landing |
|---:|---|---|---|
| 1 | [#592](https://github.com/driceroland/Search/pull/592) | Small, targeted HTTPS correctness fix | Parser edge cases; retain actual local HTTP behavior |
| 2 | [#587](https://github.com/driceroland/Search/pull/587) | Prevents pin persistence loss | Move to unopened Space, pin tiers, multiwindow, relaunch |
| 3 | [#589](https://github.com/driceroland/Search/pull/589) | Keeps long-running browsers checking extension updates | Timer/throttle/in-flight behavior and lifecycle |
| 4 | [#483](https://github.com/driceroland/Search/pull/483) | Reliable password-manager native hosts | Fake hosts plus one real supported password manager |
| 5 | [#549](https://github.com/driceroland/Search/pull/549) | Fixes identifiable window retention | Repeated close/reopen and keyboard/window ownership |
| 6 | [#557](https://github.com/driceroland/Search/pull/557) | Useful local-file navigation without filesystem work while typing | File URLs, regular-file paths, nonexistent paths and drops |
| 7 | [#467](https://github.com/driceroland/Search/pull/467) | Honors native swipe preferences | Actual mouse/trackpad; scrolling spreadsheets/canvases |
| 8 | [#507](https://github.com/driceroland/Search/pull/507) → [#415](https://github.com/driceroland/Search/pull/415) | More trustworthy migration/import | Denied vs missing vs empty; picker scope, bounds, cancellation |

### Clusters to integrate deliberately

| Cluster | Preferred route | Avoid / account for |
|---|---|---|
| Pins | #587 first | #463 adds global pins; unnecessary for the bug fix. |
| Numeric domains / last tab / local text | #592; separately optional #538 | #603 duplicates HTTPS work, changes the last-tab default and overlaps #415 imports. Extract only distinctive local-text work, with bounded regular-file reads. |
| Windows | Coordinate #549 + #431 + #554; optionally #493 later | Closed #519 is superseded. Launch/key ownership, cleanup and title updates touch connected paths. |
| PiP | Keep native Browse implementation from #593 | #547 and #562 modify the older custom webview design. #584 is stacked on #547 and floats a whole meeting page; it needs adaptation, not a wholesale stack merge. |
| Imports | #507 then current #415 | Latest discussion addresses several older objections. #603's broad Full Disk Access message is a narrower alternative, not an extra fix to stack blindly. |
| Extension workers | Latest #453, with remaining cases verified | Closed #514 uses polling/replay. Issue #541 is failed startup, not proven solved by worker-replacement handling. |
| Popups | #509 | Closed #503 has weaker authorization. Permission to open a popup does not implement issue #552's sized-window UI. |
| Local paths | #557 | Closed #526 does filesystem work while typing. Missing paths still search; it does not establish a blanket path-disclosure policy. |
| Reader | #564 → #565 → #566 | Remove arbitrary figure iframe acceptance; add safe video preload; check split articles and live appearance. |
| Sidebar speed | Measure #585, then #586 with #599 | Timing, retained views and scrolling are different changes. With mounted chrome, scroll-to-active must also happen on peeking. |
| Toolbar | #567 + #571 | Shared toolbar hunks; test menu cancellation to avoid accidental navigation. |
| Small-window switcher | #480 → #495 | #495 includes its prerequisite; do not count or apply it twice. |
| Memory | #549 first; benchmark #604 separately | Allocator pressure relief is not a fix for live leaks or WebContent growth. Issue #569 has multiple possible causes. |
| Test infrastructure | #579 independent of #580 | Model-backed/paid test infrastructure is not required for deterministic download tests. |

## Useful feature and polish queue

After the foundation gate, the best native improvements are bookmark context menus **#439**, native PDF export **#461**, reload/history menus **#571/#567**, non-Latin shortcuts **#568**, and the small material-mask correction **#576** adapted to Browse's autocomplete. Sleep timing **#448** is useful configuration; it does not preserve live page state as requested in #520. Multi-selection **#454** is useful but needs split-pair and drag acceptance. Reader improvements are a good bounded feature batch after their safety corrections.

**#596 site-to-Space routing** is strategically useful for a future browser/email ecosystem: route a URL to the correct account context before the first request. It is larger policy work and belongs after navigation, store changes and private handling are stable. Define what an identity/profile means before promising account separation.

**#572 power-aware refresh** and the sidebar performance changes are worth measuring on real hardware. **#605 paused-media behavior** needs real Spotify/Music/media-key and native PiP testing; its author's external-app handoff check is outstanding.

Defer broad page recoloring **#450**, floating new-tab UI **#601**, translucent chrome **#602**, and additional small-window/peek behavior until they justify their compatibility and maintenance costs. Closed **#558 optional MRU switching** may still suit Browse even though it did not fit Search's direction; reevaluate it as a product choice, not a foundation fix.

## Hold or rework: privacy, permissions and unsupported APIs

- **[#536 private-tab extensions](https://github.com/driceroland/Search/pull/536):** unresolved per-extension default-off consent, reset behavior, tab filtering, mutation guards and private-state reporting. Do not adopt the current global-consent approach.
- **[#530 screen-capture permission gate](https://github.com/driceroland/Search/pull/530):** requires shared prompt arbitration, cancellation of pending requests and safe test-answer handling. It mitigates consent behavior; it does not fix the macOS picker freeze itself.
- **[#550 cookie-policy change](https://github.com/driceroland/Search/pull/550):** requires symmetric restoration when the setting is turned off again, at runtime and launch, across Spaces. The current one-way change is incomplete.
- **[#510 proxy](https://github.com/driceroland/Search/pull/510):** WebKit-store proxying does not cover URLSession traffic; keychain handling also needs correction. Do not advertise whole-browser privacy or VPN-extension support from this patch.
- **[#468 clipping fix](https://github.com/driceroland/Search/pull/468):** current comparisons did not reproduce its claimed improvement. Obtain a failing case before changing layout.

Some reports are engine/API gaps rather than available patches. VPN extensions need `chrome.proxy` (#533); screen-share audio (#540) is not supplied by the investigated path; the ChatGPT extension report (#273) involves unsupported debugger attachment. Return YouTube Dislike (#588) lacks a useful reproduction and should not be assumed fixed by the AdBlock-specific #600. Okta hardware-key crash #548 needs its attachment symbolicated and the flow reproduced; disabling Browse's passkey entitlement is not proof of eventual compatibility.

This is the central lightweight-browser tradeoff: each Chrome API emulated outside WebKit increases code, security review and compatibility testing. Publish a supported-extension/capability list instead of promising every Chrome extension.

## Historical work worth retaining or revisiting

Closed-without-merge is not equivalent to rejected. Maintainers often land adapted commits and close the originating PR. The inventory traces named landing commits into Browse ancestry where available; a reference proves ancestry, not that every original hunk or test was kept.

Examples already inherited include [#374 history identity](https://github.com/driceroland/Search/pull/374), [#375 bookmark replacement](https://github.com/driceroland/Search/pull/375), [#376 atomic extension replacement](https://github.com/driceroland/Search/pull/376), [#377 find](https://github.com/driceroland/Search/pull/377), [#378 download lifecycle](https://github.com/driceroland/Search/pull/378), [#380 background imports](https://github.com/driceroland/Search/pull/380), [#381 split views](https://github.com/driceroland/Search/pull/381), [#403 scripting](https://github.com/driceroland/Search/pull/403), [#405 SingleFile](https://github.com/driceroland/Search/pull/405), [#408 Bitwarden popup](https://github.com/driceroland/Search/pull/408), [#426 pin rows](https://github.com/driceroland/Search/pull/426) and [#582 Arc pins](https://github.com/driceroland/Search/pull/582). Preserve the current fixes. Where discussions say tests were omitted, salvage the useful regressions rather than reapply old implementation; #375, #323 and #343 are examples to revisit.

Further references:

- [#352 side panel](https://github.com/driceroland/Search/pull/352): potentially useful for a native assistant later. Current `sidePanel` shim opens an ordinary tab. An old branch must retain current permission/origin/path validation; it is not a safe drop-in replacement.
- [#265 Apple Translation](https://github.com/driceroland/Search/pull/265): a native feature candidate declined for product direction; revisit only when Browse chooses it.
- [#404 Apple Foundation Models](https://github.com/driceroland/Search/issues/404): research/idea input, not a finished integration.
- [#559 screen audio](https://github.com/driceroland/Search/pull/559): investigation, not a production fix.
- Avoid resurrecting the large obsolete #142 branch, the weaker popup #503, polling/replay #514 or typing-time filesystem #526 just because their code is available.

Keep original authorship and the repository's MIT notice when adapting upstream work. Use small attributed commits/PRs, noting source PR and exact reviewed revision. Preserve tests and newer security fixes when resolving conflicts.

## AI and the connected-product direction

AI is already present in the source but `AI.shipped` is false. Existing modules handle provider requests, key storage, extraction, streaming UI and an optional local engine. Page extraction is limited to visible main-frame text, excludes typed form content, caps context at 24,000 characters and removes URL query/fragment information. Provider networking uses an ephemeral session, avoids cookies/cache and restricts endpoints/redirect behavior. These are useful components to evaluate rather than automatically introducing a second provider stack.

The current extraction/prompt fences and answer checks are **not** a security boundary for an agent that can operate the browser or email. A web page or message is untrusted input. Before enabling actions, separate readable context from authority to send, delete, purchase, install or expose secrets, and make consequential actions concretely reviewable.

A sensible sequence is:

1. **Reliable browser:** safe persistence, stable windows/extensions, working release/update and reproducible validation.
2. **Read-only native AI:** explicit summarize/ask actions, clear context selection, cancellation, understandable local/provider behavior, and no private-tab extraction by default. Reevaluate the existing implementation and Jev proposal against this scope.
3. **Account-aware context:** explicit identities and scoped stores; no ambient sharing of browsing history, page contents or credentials across products.
4. **Email product:** share only proven needs—identity handling, credential storage conventions, provider configuration, permission/audit concepts and a few native UI primitives. Do not create a general ecosystem framework before a second product establishes a real shared requirement.
5. **Actions and sync:** separate milestones with explicit permissions, conflict/recovery behavior and data boundaries.

The ecosystem can feel connected through consistent identity and user-selected context without making all browser/email data automatically available to every AI tool. Keep the idle browser free of unnecessary model execution and background work.

## Readiness gates and fork housekeeping

A foundation release should require:

- Clean checkout builds, runs its tests and assembles Browse.app; test worlds are isolated from both Browse and Search production profiles.
- Pins, groups, split pairs, Spaces and multiple windows survive quit/relaunch; cancelled transfers preserve drafts; corrupt and unwritable files preserve recoverable state and report failures.
- Repeated window/tab cycles reach a stable resource plateau, measured with host and WebKit processes separately; compare idle CPU, launch, tab-switch latency, extension startup, background media and wake-from-sleep behavior.
- A small supported-extension set passes install, permissions, reload/update, worker restart, native messaging and uninstall. Include a blocker and the intended password managers.
- Native checks cover keyboard/IME, VoiceOver, multiple displays, real scrolling devices, popup login, uploads/downloads, capture permissions and PiP. Exercise the oldest supported macOS, extension-capable baseline and current OS; include Intel if shipping it.
- A disposable signed release installs, updates and handles a rejected/bad update safely with Browse's own Developer ID, feed and bundle identity. Passkey and local-engine enablement remain separate gates.

The fork currently has GitHub Issues disabled despite CONTRIBUTING directing people to open an issue. Enable a Browse-owned issue tracker when beginning implementation and keep upstream provenance in each item. ROADMAP still refers to the removed `./ideas` generator and upstream workflow; replace it with a maintained Browse plan. Reconcile already-landed open PRs and clarify disabled passkey/AI capabilities in user-facing documentation. These are small governance fixes, not a reason to redesign the repo.

**Recommended first implementation milestone:** repair the two build blockers and automation paths, establish the green test/package gate, then adapt #592, #587 and #589 as separate focused changes. Follow with #483 and the coordinated window fixes. That delivers a measurable improvement in trust before adding new product surfaces.

## Limits and material risk

No full GUI compatibility pass, long-running memory/battery soak, hardware-key login, signed/notarized release, Intel execution or supported-OS matrix was performed. The host was macOS 27.0.1 with Apple Swift 6.4; the single inherited test failure may depend on this newer WebKit. No claim is made that absent findings imply absence of vulnerabilities.

The current checkout is not buildable/packageable as audited. Most recommended upstream PRs require conflict resolution and Browse-specific validation, and some have unresolved security/privacy review. Treat this report as a concrete stabilization backlog—not a bulk-merge list or a release certification.
