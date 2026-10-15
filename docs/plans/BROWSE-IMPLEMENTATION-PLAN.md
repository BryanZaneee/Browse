# Browse implementation plan

Prepared October 15, 2026 from Bryan's feature-guide feedback, the [October 14 audit](../audits/2026-10-14/REPORT.md), current source and a fresh upstream check. This is an implementation plan, not a record of completed features or passing release checks.

## Direction and decisions

Build a polished native browser with a low idle footprint before enabling AI. Keep features inexpensive when unused, preserve user data, and make common interactions consistent. Do not solve memory pressure by silently discarding drafts or breaking calls.

| Feedback | Decision | Delivery |
|---|---|---|
| Site-search shortcuts feel redundant | Remove custom keyword searches and learned Tab-to-search from the product, while retaining ordinary search, bookmarks and history/open-tab autocomplete. They are distinct capabilities, so describe this as intentional simplification. | Phase 2 |
| Address-bar commands feel redundant | Remove command interpretation and its settings. Words such as `settings` become ordinary searches; menus and keyboard shortcuts remain. | Phase 2 |
| Tab groups look rough and animate badly | Make group membership visible, improve transitions and dragging, then add durable saved groups and the requested actions. | Phase 3 |
| Small external-link windows are confusing | Keep optional and off by default. Improve the explanation, focus behavior and Open in Browse escape route; defer extra switcher/swipe features. | Phases 1-2 |
| 120 Hz should be on by default | Enable the existing high-refresh preference for new/unset preferences on capable systems. Respect an explicit existing off choice and preserve safe fallback when the WebKit flag is unavailable. | Phase 2 |
| Reading mode, Read Later and Save My Place belong together | Present one reading workflow, but store reading-list metadata independently of transient reader HTML. Save either an ordinary page or a reader article under its original URL. | Phase 4 |
| Home-screen quick tools are interesting | Keep deferred with other AI work. Do not add runtime/background costs now. | After foundation acceptance |
| Cleanup should remove duplicates | Add user-invoked duplicate cleanup, not automatic age-based closure. | Phase 3 |
| Multiple selection and PDF export | Adopt focused upstream work with Browse-specific checks. | Phases 3-4 |
| Full browser profiles | Commit to a separate isolation milestone, not a rename of Spaces. | Phase 5 |
| Optional forced dark webpages | Start with reader themes; then test an explicitly enabled page-darkening feature with per-site escape and bounded work. | Phase 6 |
| Apple Passwords suggestions | Research a supportable native route; keep existing password-manager paths reliable first. | Phase 6 |
| Screen sharing with audio | Feasibility milestone with an actual website-call prototype before promising delivery. | Phase 6 |
| On-device translation | Start with selected text/reader text using Apple's framework, then reversible whole-page translation. | Phase 6 |
| AI after polish | Keep page AI, Jev tools, model downloads and ecosystem integration disabled/deferred. | Final gate |

## Updated starting point

Browse is still at `3241006e72b8b4c4212095552eaed8f9d99f226a`. The earlier build findings have not been repaired by this planning work or rerun here.

Search main advanced from the audited `615bbca` to `c9f283bc3f3516b034c69d2d8e52c34963513434`. Its one additional commit prevents opening a bookmark from replacing a pin. Browse now lacks that upstream commit. There are 64 open upstream PRs, up from 62 in the PDF snapshot; the original audit remains a dated record.

Fresh changes relevant to this plan:

- [#609 roomier sidebar tabs](https://github.com/driceroland/Search/pull/609) adds an optional larger row/title size; consider it alongside group layout, not as a substitute for fixing grouping.
- [#608 passkey availability](https://github.com/driceroland/Search/pull/608) corrects stale settings when switching between entitled and unentitled builds. Review its migration so user choices are not repeatedly reset.
- [#550 cookie policy](https://github.com/driceroland/Search/pull/550) now restores the policy and includes a restart regression. The earlier audit's specific one-way-policy objection has been addressed in the current diff; private-store, runtime-toggle and supported-OS validation are still required.
- Heads also changed for #415, #453, #454, #468, #507, #509, #549 and #602. Re-review the current revisions at adoption rather than treating old comments as current verdicts.

The fork has no PR template and GitHub Issues remains disabled. These are setup tasks in the plan, not settings changed in this session.

## Implementation sequence

Each row is a bounded delivery unit. Where several upstream PRs are listed, adopt them individually unless they are inseparable parts of the same behavior. Every candidate must be read at its current revision, preserve attribution/tests, and pass Browse's own checks after conflict resolution.

### Phase 0: contribution workflow

**D01: Establish the Browse workflow.** Add the PR template below and a short branch/commit section to CONTRIBUTING. Make this plan the current Browse planning reference while preserving the inherited roadmap as historical provenance; replace obsolete `./ideas` instructions rather than running a missing generator. Enable Browse's issue tracker when executing repository setup, then create issues per delivery unit and link upstream sources. Existing user decisions in this document already supply scope agreement; do not ask for the same decisions again.

Keep short-lived branches into `main`, with no extra develop branch or automation framework. The first UI implementation PR should establish reproducible native fixture screenshots under `docs/screenshots/`; use the existing native bench/test environment after its isolation fix. Do not manufacture screenshots of an unbuildable app or substitute browser automation for native AppKit behavior.

**Exit:** local workflow documentation matches the intended process; any hosted setup is read back and reported separately. Require CI checks only after their actual names and successful runs exist.

### Phase 1: buildable, testable and safe

| Unit / suggested commit title | Scope and candidate | Required evidence |
|---|---|---|
| F01 `fix: restore Browse builds` | Missing Store return and leftover icon-generator references. Repair merged in [#73](https://github.com/BryanZaneee/Browse/pull/73), with build/icon validation and independent review. | Clean Swift build and unsigned `build.sh debug`; inspect generated Browse icons. |
| F02 `fix: isolate Browse test runs` | Owned bundle worlds, test seams and cleanup implemented for #10; validation/review precede merge. Preserve #497/#475 provenance in [test isolation](../TEST-ISOLATION.md). | Two test worlds coexist without changing Browse or Search production files, settings, cookies, credentials or clipboard. |
| F03 `ci: check builds and tests` | PR build/tests/package gate and #579 download fixtures prepared in #12; file-access control accounts for WebKit’s additional gate without weakening denial assertions. User-authorized review stack on #74; merge #74 first, then validate CI before merge. | Green Swift suite, history and extension-file checks, unsigned bundle assembly; distinguish OS-specific tests. |
| F04 `fix: use HTTPS for public hosts` | Focused #592, not duplicate #603 work. | Real private IPv4, public numeric-prefix names, ports, IPv6 and existing explicit schemes. |
| F05 `fix: preserve moved pins` | #587 destination pin persistence. | Unvisited destination Space, row/square tier, multiwindow and restart. |
| F06 `fix: keep bookmarks out of pins` | Adapt upstream `c9f283b` across bar/menu/list. Preserve extension search.query behavior. | Bookmark opened from pin, blank tab reuse and background open. |
| F07 `fix: refresh installed extensions` | #589 timer and in-flight guard. | Long-running browser, throttle, concurrent triggers, disable/remove and sleep/wake. |
| F08 `fix: stabilize native messaging` | #483 waiter/callback ordering, EOF lifetime and bounded frames implemented for #17 review; real password-manager validation explicitly deferred by the user. See [validation](../NATIVE-MESSAGING.md). | Fake-host regressions plus real supported password-manager acceptance. |
| F09 `fix: release closed windows` | Current #549, coordinated with separate #431 focus and #554 title changes. | Repeated open/close, reopen, last-window semantics, keyboard focus and resource plateau. |
| F10 `fix: report failed state saves` | Failure notices, retry/quit handling and protected malformed-data recovery implemented for #19; validation/review precede merge. See [recovery behavior](../PERSISTENCE-RECOVERY.md). | Unwritable destination, malformed JSON, interrupted save; no silent loss or overwrite of recoverable bytes. |
| F11 `fix: protect drafts during moves` | Apply the existing unsaved decision before cross-store window transfer. | Cancel leaves both windows intact; menu/drag paths, split partners and navigation races. |
| F12 `fix: honor passkey availability` | Review #608 against Browse's entitlement state and stored preference. | First launch, upgrade/downgrade of capability and explicit user choices. No claim that this enables passkeys. |

Run the performance baseline once F01-F03 make it trustworthy, then compare later changes against it. F10/F11 must land before durable group closure, bulk cleanup or cross-profile movement.

**Exit:** green reproducible build/package/tests, no known unhandled draft/pin persistence paths in these operations, stable repeated window ownership, and recorded baseline measurements. A fully signed release remains a separate acceptance gate.

### Phase 2: simplify and polish everyday interaction

**U01: Remove site-search modes.** Reach `Keyword.swift`, `SiteSearch.swift`, Preferences, Settings, Browser navigation/suggestions, address field Tab handling, History suggestion types as applicable, welcome/What's New, bench commands, docs and affected tests. Remove background discovery as well as its switch. Keep existing saved configuration inert for rollback rather than deleting user data during this removal. Verify literal search, URLs, autocomplete, IME, Tab focus, pasting, drops and private navigation.

**U02: Remove address commands.** Reach `AddressCommands.swift`, Browser suggestion dispatch, History suggestion cases, Settings/Preferences, bench/test stubs and editor regressions. Remove unused paths completely. Verify `settings` and `new tab` search literally, while ordinary app menu shortcuts remain functional.

**U03: Default high refresh on.** Change the unset preference fallback; do not overwrite a stored false value. Keep the capability guard and avoid reloading open pages to apply a setting, which can destroy drafts. Validate a 60 Hz screen, high-refresh screen, mixed displays, battery operation, Low Power Mode, hidden tabs, video and PiP. Review #572 as a later power-policy enhancement; do not silently replace the requested default with AC-only behavior. If OS power policy caps the actual rate, label the setting honestly as “up to 120 Hz.”

**U04: Small-window clarity.** Explain “links from other apps open in a temporary window”; keep it off by default. Preserve Open in Browse, Escape/close behavior where supported, and correct keyboard ownership. Defer #474/#480/#495 until users demonstrate a need for their additional behavior.

**U05: Native low-cost polish.** Prefer #467 swipe preference, #568 non-Latin shortcuts, #439 bookmark context menus, #567 history menus, #571 reload menu, and #576 address-card masking. Small PR per behavior. Add #609 only after checking group/drag geometry at both row sizes. Inspect pending #468 evidence rather than accepting an unproven layout change.

**U06: Sidebar animation.** Measure #585 first; evaluate #586's retained view hierarchy only if it improves frame time without unacceptable memory/accessibility costs. Coordinate #599 so opening/peeking shows the active tab. Respect Reduce Motion; fix expensive work on the main thread rather than masking it with a different spring.

**Exit:** simpler address input; native keyboard and pointer behavior; no obvious animation hitch in reproducible group/sidebar fixtures; high-refresh preference with measured resource tradeoff.

### Phase 3: complete tab organization

The existing group model contains only `id`, `name`, `collapsed`. The current group menu has Rename, Expand/Collapse, Ungroup and Close; closing feeds recent-close recovery, not a durable saved-group library. There is already group-aware reorder/drop plumbing, so extend it rather than build another drag system.

#### Agreed group behavior

| Action | Intended result |
|---|---|
| Expand / collapse | Change visibility only; preserve membership, order and current page. Clear chevron/count plus a subtle boundary/rail identify the group; color is never the only cue. |
| Rename / color | Update metadata across the heading, saved entry and bar reference; choose accessible native palette colors. |
| New tab in group | Add and focus a blank member in that group, using the same Space/profile. Keep intentionally created empty groups long enough to accept their first tab. |
| Drag into / out of group | Show an insertion/drop target, preserve order, support collapsed groups and the ungrouped region. Split pairs move together unless the user explicitly separates them. |
| Move to new window | Transfer the group into a window using the same Space/profile without unnecessary reload. Cross-store moves require the existing draft/account safeguards. |
| Close and save group | Persist a restorable snapshot successfully, then close member tabs and release their web views. Keep a saved-group entry across relaunches. |
| Reopen group | Restore name, color, ordered URLs and valid split layout into its original profile/Space by default. Create lazy tabs; loading every saved page immediately defeats the memory goal. |
| Pin to bookmarks bar | Show a launcher referencing the saved group, not a second independently editable URL snapshot. An already-open group focuses its existing owner rather than spawning duplicates by default. |
| Ungroup | Keep open tabs, remove their grouping; if this is a saved group, remove its saved definition/bar reference as part of that explicitly described action. Ordinary bookmarks remain unchanged. |
| Delete group | For a closed group, delete its saved definition and bar launcher. For an open group, explicitly confirm deletion and closure, respecting unsaved/capture safeguards; offer undo where safe. |

“Collapsed,” “closed and saved,” and “deleted” must look and behave differently. Saving captures URLs/layout and reading metadata, not arbitrary form contents or an offline copy of the page. If state cannot be persisted, leave tabs open and report failure. Do not promise an undo can recreate unsaved form input.

Recommended PR split:

1. **G01 `feat: polish tab groups`:** backward-compatible optional color, visible membership/count, focus/hover/drop states, stable view identity and measured animation. Reach TabGroup, TabGroups, TabBar/Side, design metrics and group fixtures. Preserve older sessions.
2. **G02 `feat: improve group actions`:** New Tab, dependable drag in/out and whole-group window transfer. Reach Browser, window transfer, split/group ordering, context menus and extension group/tab events. Do not temporarily dissolve split pairs or silently change sign-ins.
3. **G03 `feat: save closed tab groups`:** persist metadata plus existing session-like entries; make Close and Save transactional and restore lazily. Use a focused saved-group store and existing Disk/session primitives, not a generic workspace framework. Test failed writes, relaunch, crash boundaries and invalid saved URLs.
4. **G04 `feat: pin saved groups to the bar`:** group references in the bar, reopen/focus, rename/delete propagation and safe migration. Browser-bookmark exports and extension bookmark APIs need an explicit mapping: exported snapshots may be ordinary URL folders, but must not expose internal pseudo-URLs or mutate live group membership unexpectedly. This is separate from ordinary bookmarking.
5. **G05 `feat: select multiple tabs`:** adapt latest #454 after group semantics settle. Use existing move/close/pin/group/copy actions; test modified dragging, keyboard selection, split pairs, hidden group members and selection after closure.
6. **G06 `feat: close duplicate tabs`:** user-invoked, previewed batch close with a clear survivor. Initially current window/current Space only; never combine private and normal contexts or cross profiles. Compare exact full HTTP(S) URL including query and fragment; do not strip tracking parameters or equate similar URLs. Skip pins, split members, active capture/download/media, unknown/unsafe state and drafts; keep the active eligible duplicate, otherwise the most recently used. Never create/wake a page just to inspect a duplicate. Show skipped reasons and use existing grouped reopen where appropriate.

**Exit:** every requested group action works in both layouts, colors survive restart, drag/cancel is reliable, saved closed groups retain no live web views, and ordinary bookmarks/extensions/split behavior still pass. Include light/dark screenshots, keyboard/VoiceOver acceptance and a real animation recording.

### Phase 4: a cohesive reading workflow

- **R01 `feat: improve reader presentation`:** adapt #564 -> #565 -> #566 in order, correcting arbitrary iframe acceptance and media preload. Preserve original URL, Find, navigation and split-reader independence; support light/dark/system and Reduce Motion.
- **R02 `feat: add Read Later`:** implement Browse planning PR #3's core list using the existing Bookmarks surface. Store original URL, title, save date, read/unread state and preferred reader presentation; opening does not mark read. Normal and reader pages can both be saved. No automatic downloads, offline archive, background refresh or retained reader web view.
- **R03 `feat: save a reading position`:** store an explicit selected quote with small surrounding context, not just a scroll percentage. Exclude private tabs, editable fields, frames and PDFs initially. Re-anchor carefully in ordinary and reader text; on ambiguity/changed text keep the quote and explain failure, and stop restoration when the user scrolls. Bound/cancel DOM work and test redirects, repeated quotes and reader toggles.
- **R04 `feat: export pages as PDF`:** adapt #461 for an explicit native save action. Test cancellation, write failures, long pages, private downloads, filenames and current pane. Later use the same action to export the current reader presentation when supported.
- **R05 `feat: copy clean links`:** carry forward Browse #5 as useful bounded polish. Conservative known-parameter removal only, preserving signed and functional URLs; independent from duplicate matching.

All new saved data starts in the existing default context and must be included in the profile migration below. Do not invent a generalized account system solely for these files.

**Exit:** reading list/place state survives relaunch, is lightweight when unused and never silently saves private/form content; PDF exports the intended page with usable output.

### Phase 5: real profiles

This is the largest architectural change. `Shared` owns preferences, bookmarks, history and other services; Extensions and several helpers are global singletons. A second cookie store alone is not a profile implementation.

**Boundary:** a Profile owns browsing history, bookmarks, credentials' Browse namespace, cookies/cache, permissions, extensions/settings, sessions/Spaces, pins, saved groups, reading list, download history and hidden-element rules. App updates, app identity and suitable global UI defaults may remain app-wide. Spaces stay nested within a profile and may share or isolate website sign-ins inside that profile. Independent profile settings do not establish an OS security boundary against another local process.

1. **P01 `refactor: scope browsing data to profiles`:** introduce the smallest explicit owning context and convert actual shared consumers. Existing data becomes the Default profile without sign-outs or overwrites; retain recoverable migration backups. Include current window ownership and every new saved store. No feature advertised yet.
2. **P02 `feat: isolate profile web sessions`:** distinct normal/private/extension stores and permission contexts; ensure all creation, popup, import, network, keychain and extension API paths carry the correct profile. Validate worker/controller isolation on supported OS versions before exposing profiles.
3. **P03 `feat: add browser profiles`:** create, rename, select and delete profiles with persistent window ownership. Do not initialize inactive profiles' extension engines or web views. No live tab transfer between profiles in v1; an explicit open-URL-in-another-profile creates a fresh navigation and never carries session/form data. Downloads already saved to Finder are not silently deleted with a profile.
4. **P04 `feat: route sites to Spaces`:** re-evaluate #596 once the profile/Space contract is stable. Route before first request; avoid POST replay, redirect loops and private-to-normal leakage. Initially scope rules to a profile, with explicit external-link destination selection.

**Validation:** two profiles simultaneously signed into different synthetic accounts; no history/bookmark/extension/credential suggestions crossing boundaries; isolated imports, private tabs, downloads and permission choices; relaunch and failed migration recovery. Where a system password provider is shared by macOS, disclose that boundary instead of promising its vault is profile-isolated.

**Exit:** every claimed profile boundary has a test; inactive profiles have no resident browsing engines; migration and deletion are reversible/recoverable within the documented limits.

### Phase 6: native enhancements with feasibility gates

| Feature | Smallest useful implementation | Gate / reason not to promise an immediate merge |
|---|---|---|
| On-device translation | Selected text and reader text first, then reversible whole-page text translation. Use Apple's shared language models on demand; cancel work on navigation and release sessions. | Verify language/hardware/OS availability. Language downloads require consent; page inputs/code must not be modified. Historical #265 is a reference, not a branch to merge wholesale. |
| Forced dark webpages | Optional settings switch plus per-site override, preserve images/video and sites that already support dark appearance. Start disabled. | #450 adds extensive page observers/recoloring. Demonstrate bounded work on dynamic sites and clean teardown when off; add no permanent worker. |
| Native Apple Passwords | A bounded feasibility prototype using supported system integration where available. Existing extension and Browse-password paths remain fallback. | #425's undocumented helper exploration is not a production commitment; verify entitlement, platform and security constraints. No scraping/decrypting the user's Passwords database. |
| Screen sharing with audio | Consent-first native capture prototype feeding a real web-call MediaStream with audio/video, cancellation and visible capture state. | Native ScreenCaptureKit audio exists, but delivery into WKWebView/WebRTC is separate work. Demonstrate actual calls, echo handling, device changes and stop-on-close before proceeding. #559 is investigation, not a ready feature. |
| Proxy settings | Defer until a concrete network use case justifies them. A future version must clearly define all covered routes and credential handling. | #510 currently configures WebKit stores, not every URLSession/service route. Audit DNS, redirects, authentication, failures, WebRTC and private/profile behavior; never silently fall back direct if privacy is promised. |

**No AI milestone starts merely because features exist.** Require foundation acceptance below first. Home tools and page AI then get their own resource/privacy/design review.

## Disposition of remaining “changes to current features”

| Change | Decision |
|---|---|
| Local paths #557; local text #603/#529; Finder handling #524/#527 | Adopt #557 early after address fixes; bounded regular-file text preview and Finder registration as separate polish. No synchronous filesystem work while typing and no unbounded file reads. |
| Imports #507 -> #415 | Adopt after core safety; re-review refreshed heads. Verify denied/missing/empty sources, session-scoped picker, bounded reads and cancellation. |
| Worker recovery #453, UTF-8 #521, AdBlock #600 | Prioritize compatibility with a defined supported-extension set. Keep #453's unknown startup cases separate from confirmed worker replacement; add missing regression cases for #600. |
| Last-unpinned-tab behavior #538 | Optional later preference; preserve current default unless usability testing warrants a change. Do not import #603's different default accidentally. |
| Bulk password removal #471 | Useful after authentication/error-handling baseline; clear scope, confirmation, cancellation and verified counts. |
| Home-page extension choice #472 | Useful low-cost correctness improvement; preserve the user's prior choice. |
| Async login popup #509 | High-value compatibility fix after re-review; maintain frame/gesture authorization and POST semantics. |
| Screen permission gate #530 | Useful only after prompt arbitration/cancellation defects are addressed; does not cure an OS picker freeze. |
| Cookie policy #550 | Re-evaluate positively now restoration is present; test both directions at runtime/relaunch across isolated stores and private browsing. |
| Media keys #605 | Useful, but require real media-key handoff to Music/Spotify and native PiP acceptance before landing script interposition. |
| Allocator release #604 | Benchmark-only candidate until it measurably reduces retained memory without latency/CPU regressions; window leaks first. |
| Global pins, cross-site Peek, floating new-tab field, translucent chrome, extra small-window switcher features | Defer. They add modes/compositing/interaction complexity ahead of demonstrated need. |
| Auto-close old tabs #429 and preserved-live-state sleep #520 | Do not prioritize. Duplicate cleanup and durable closed groups address clutter with clearer control and lower memory cost. |
| Existing native PiP #593 and autocomplete #597 | Already in Browse; validate, do not merge twice. |

## Keeping the browser small and responsive

Measure the host app and its WebKit content/network/GPU processes separately and report combined attributable footprint with shared-process caveats. App binary size and compressed downloads are separate metrics. No “tiny RAM” claim until the repaired build has a reproducible baseline.

Use one named disposable fixture profile, stable local test pages and the same Mac/OS/build configuration. Record cold launch; 60-second settled idle; 1/20/100 restored tabs; visible heavy page; 20 window close/reopen cycles; group collapse versus close/save/reopen; extensions off/on; three profiles with one active; video/PiP; translation completion; and suspend/resume. Record repeated-run median and spread for physical footprint, CPU, startup and p95 interaction/frame time. Energy/battery claims need actual comparable power measurements, not CPU percentages alone.

Proposed engineering gates, to calibrate against baseline noise:

- Disabled features add no background polling, page observers, model process or hidden web view. Extension update timing reuses the existing throttle; it is not a per-tab timer.
- Saved groups and Read Later retain metadata, not live pages. Reopening creates lazy tabs; an inactive profile does not initialize its browser engines just to appear in a menu.
- Repeated close cycles settle without monotonic retained-object growth. WebKit caches need time and separate analysis; do not demand that every process instantly returns to its original RSS.
- Any idle-memory increase above the larger of 10 MiB or 5% of the paired baseline triggers investigation and explicit review. This is a provisional regression-review threshold, not a measured guarantee or permission to add costs under the threshold.
- At 120 Hz the nominal frame interval is about 8.3 ms. Measure missed frames and main-thread work on high-refresh hardware; 120 Hz does not fix layout stalls and is primarily a rendering/energy tradeoff, not a RAM optimization.
- Apply bounded batch work for imports, translation and page styling. Release observers, tasks and native hosts on close/cancel. Never force-sleep a draft/call to improve a benchmark.

Final foundation acceptance: green CI and signed/notarized install-update-rollback exercise; safe persistence and profile migration; stable memory cycles; real keyboard/IME/VoiceOver/drag checks; core login/password-manager/upload/download/capture/PiP flows; macOS 14 fallback, extension-capable baseline and current OS coverage, plus Intel validation if Intel remains a release target. Do not claim an untested target is supported merely because it compiles.

## Commits and pull requests

Use the existing repository and `main` as the destination: `BryanZaneee/Browse`, never inherited Search by accident. Keep each PR to one user-visible outcome with its tests/docs; dependent PRs explicitly name their prerequisite and remain individually reviewable. Prefer one or a few coherent commits, not a giant feature dump or a commit per file. Do not publish features as part of this planning pass.

Commit subjects use short imperative descriptions, generally under 60 characters:

- `fix: preserve moved pins`
- `feat: save closed tab groups`
- `perf: reduce sidebar layout work`
- `refactor: scope history to profiles`
- `ci: check app bundles`
- `docs: document Browse workflow`

Upstream adaptations record the source PR and reviewed SHA in the commit body/PR, preserving original author credit and license. Re-check source/main overlap before every adoption. Do not squash away contributor attribution.

Proposed `.github/pull_request_template.md`, adapted from the repo-conventions skill to the requested format:

```markdown
## Issue or feature

<!-- Link the issue. State the trigger and resulting user behavior. -->

## Code changes

<!-- Briefly explain the files/logic changed and any data migration. -->

## Validation

<!-- Exact checks actually run and outcomes. Add fixture screenshots/video
for UI changes, and comparable measurements for performance claims. -->

## Remaining limitations

<!-- Untested platforms, pending checks, resource tradeoffs or migration risks. -->
```

A PR description must explain the final change to someone who never read this conversation. For example, F05's issue is “Moving a pin into an unopened Space can lose it after restart”; its code section explains the destination pin-store update; validation names the real relaunch regression and its result. Never fill the validation section with a proposed test and label it passed.

Every user-facing change updates Unreleased, the relevant help/PDF source documentation when maintained, and the plan's status while retaining provenance. UI evidence must use reproducible synthetic fixtures in `docs/screenshots/`; include light/dark and Reduce Motion where relevant. Native Retina images may exceed the usual size target only when documented for legibility. Existing README/screenshots should be preserved until replacements are actually captured.

Before pushing: inspect only the intended diff, run the appropriate gate, check staged files for secrets/private profile data, and keep scratch builds/logs outside tracked changes. Before merge: review latest CI on that commit, dependencies and remaining limitations. Register created/worked-on PRs with the thread's PR-linking tool. Do not auto-merge or release as an implied part of opening a PR.

## Questions and explanations

### Are site-search shortcuts the same as autocomplete or bookmarks?

No. Autocomplete helps find an existing destination; `yt cats` submits a new search directly to YouTube, and a bookmark usually opens a fixed URL. We can still remove site-search modes because you prefer simpler input; the tradeoff is losing direct site queries, not losing ordinary autocomplete.

### When would a small window be useful?

You click a link in Mail or Slack, read it quickly, then close it without disturbing your main workspace. It is a temporary browsing window, not a separate profile or stronger privacy boundary. Keep it off by default with a clear “Open in Browse” action; it is optional convenience, not core organization.

### What is a passkey here?

A passkey replaces a website password with a cryptographic credential. You approve sign-in using Touch ID or another authenticator; the website verifies a signature instead of receiving a reusable password. Browse's role is to connect the site's request to macOS or a supported provider. It is different from Apple Passwords suggesting a stored password, and Browse still needs its own entitlement/setup before its passkey path can be considered ready. [Apple: passkey security](https://support.apple.com/en-ie/102195).

### What does browser proxy configuration mean?

It sends covered browser requests through an intermediary server instead of connecting directly to the destination. This is useful for company networks, testing or a deliberately chosen network route; it can introduce latency, authentication failures and a new party handling connection metadata. It is not automatically a VPN or anonymity feature. The current upstream patch does not cover every browser service, so it is not a priority until its scope and a real use case are clear. [Apple: proxy setup](https://support.apple.com/guide/safari/set-up-a-proxy-server-ibrw1053/mac), [Apple: proxy options](https://support.apple.com/en-gb/guide/mac-help/mchlp2591/mac).

### Can we have 120 Hz and a tiny footprint?

Yes, but smooth animation, memory and battery are separate measurements. Default high refresh on as requested, keep hidden pages throttled, avoid unnecessary layout work and preserve the user's explicit off choice. A page animating faster can use more energy; no fixed refresh setting makes an expensive website cheap.

### Can translation stay native and on-device?

Apple provides a Translation API using shared on-device language models, with permission to download missing languages. That fits a small app better than bundling our own model, but translations still have temporary memory/compute costs and availability must be checked. Start on explicit user request, and verify the selected framework strategy rather than assuming every future API mode is local. [Apple: Translation API](https://developer.apple.com/videos/play/wwdc2024/10117/), [TranslationSession](https://developer.apple.com/documentation/translation/translationsession).

### Why is screen sharing with audio not a quick merge?

Apple's ScreenCaptureKit can capture audio/video, but a native capture buffer is not automatically a website's WebRTC stream. Browse must bridge it correctly into calls while preserving consent, synchronization, cancellation and resource cleanup. The prototype must prove this end to end before we commit to shipping it. [Apple: ScreenCaptureKit](https://developer.apple.com/documentation/screencapturekit).
