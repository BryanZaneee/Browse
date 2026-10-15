# Disposable Browse tests

Build with `./build.sh debug`, then use `./fresh.sh`. The default hidden world is addressed by `./bench --test`; `./fresh.sh again --world NAME` retains a named world, addressed by `./bench --world NAME`. Add `--visible` for manual review with bench disabled. Quit the exact copy before `./fresh.sh wipe --world NAME`.

The launcher derives an identity from the checkout's canonical path and world name. It records ownership under `/tmp/browse-tests-<uid>/<digest>/`, copies and ad-hoc signs the bundle, and gives it a separate defaults/WebKit identity. Intel bundles come from `build/intel/`. A process or runner already owning that world blocks preparation and cleanup. Direct unprepared development launches refuse to proceed.

Cleanup only removes the recorded directory and exact owned bundle namespaces, including the separate HTTP cookie file. It never uses Space IDs from fixture JSON to construct cleanup targets. Symlinked world resources are rejected. Lock files remain as harmless coordination files. Older `Browse (test)` / `Search (test)` worlds are not migrated or erased.

Test credentials and bench consent live only in memory; recreate synthetic credentials after restart. Test native messaging resolves only executable fixtures inside the world's data directory. Clipboard access uses named test boards, including native editing and WebKit's UI-process clipboard requests. Its private AppKit factory must exist or the test process fails closed. Installed browser behavior is unchanged.

XCTest uses a process-unique temporary directory/defaults suite and a randomly identified persistent WebKit store (resume-data tests require persistence). `python3 Tests/run-unit-tests.py` runs serial `swift test` (parallel workers are rejected) and removes only its recorded UUID store after the test process exits. Raw `swift test` remains isolated but leaves its WebKit ownership marker/store for explicit cleanup; prefer the runner. It never uses production app defaults, credentials or WebKit stores. Real password-manager/keychain integration requires a separate controlled acceptance test; these seams do not prove it.

## CI gate

`python3 Tests/run-ci-tests.py` runs the suite and each of the seven download journeys in a fresh process, through the owned-store cleanup runner. No download retries or skips are used. The callback/delegate timing and held cancellation response adapt [Search #579](https://github.com/driceroland/Search/pull/579), by quanru (Leyang), at `f831297ee22a1585100c4583e6dd13e0918bbf4d`.

The PR workflow runs build, Swift tests, history regression, extension-file rules and development bundle assembly on `macos-15-intel` and `macos-26` (Apple Silicon). It has read-only repository permissions and receives no release credentials. Bundle assembly uses ad-hoc signing; it does not notarize or publish. Native screenshot capture remains opt-in.

Web-extension tests require macOS 15.4+; the standalone extension-file rules also cover code without that API. macOS 14 runtime compatibility remains a separate manual gate: its hosted image is [being retired](https://github.com/actions/runner-images/issues/13518), and building with a 14.0 deployment target is not runtime validation. The file-access test keeps its positive grant control on newer WebKit by enabling its private file gate only on an unloaded synthetic context; the original app-like denial checks remain unchanged. See [WebKit’s gate change](https://github.com/WebKit/WebKit/commit/51ea20f9818ed956dee01fc46a8b36dfcb94797c).

## Checks

- `python3 Tests/test_world.py`: identities, competing owners, live-process refusal, symlinks and foreign Space IDs.
- `python3 Tests/test_world_native.py`: two simultaneous local-fixture worlds; credentials, cookies/local storage, relaunch, wiping one while the other remains usable, unchanged production metadata. It never reads production page contents.
- `python3 Tests/ClipboardRegression/run.py`: production clipboard seam, native editing and DOM writes; system clipboard change count unchanged.
- `python3 Tests/run-unit-tests.py --filter TestIsolationTests`: synthetic credentials/consent and native clipboard isolation.
- `python3 Tests/split_view.py` and `python3 Tests/text_replacement.py`: existing native harnesses using the same ownership contract. Text replacement assertions never print the Mac’s replacement phrase.

Run the normal build/test gates as described in [AGENTS.md](../AGENTS.md). Only owned disposable fixtures may be used; never restore the system clipboard after a test as a substitute for isolation.

The naming problem was reviewed against [Search #497](https://github.com/driceroland/Search/pull/497) at `96af37714b1d5714d69ecd38aa47ce986a1a0ff1` and [#475](https://github.com/driceroland/Search/pull/475) at `4db50d869502f4ac0fd443af8a7271db7858911a`; this implementation owns entire bundle namespaces instead of adopting their shared-container cleanup. The clipboard interception point follows [WebKitTestRunner's macOS test pasteboard](https://github.com/WebKit/WebKit/blob/main/Tools/WebKitTestRunner/mac/WebKitTestRunnerPasteboard.mm); no upstream implementation is copied.
