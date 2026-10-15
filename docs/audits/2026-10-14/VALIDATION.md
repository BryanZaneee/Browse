# Audit validation record

Date: 2026-10-14. Browse `3241006e72b8b4c4212095552eaed8f9d99f226a`; Search `615bbca0ecdda876973b325476587d3d8b4c2bb9`.

Host: macOS 27.0.1 (26A434), Apple Swift 6.4, arm64. Results apply to this host and these revisions. No real browser profile was intentionally modified or driven.

| Check | Result | Interpretation |
|---|---|---|
| Git ancestry | Browse 25 ahead / 0 behind upstream main | All upstream main commits are inherited; outstanding PRs require separate evaluation. |
| `swift test` in checkout | **Compile failure** | Store.swift:111 lacks return in its multi-statement URL-producing closure. |
| `swift test --package-path <temporary-copy>` with only that return added | **82 tests; 81 passed, 1 failed** | Build completes. ExtensionFileAccessTests.swift:40 fails; see below. Not a clean pass. |
| Pristine upstream `swift test --filter ExtensionFileAccessTests` | **2 tests; 1 failed**, same assertion | The observed file-access fixture behavior is inherited, not caused by Browse rebranding. |
| `./build.sh debug` in the one-line-fixed disposable copy | **Failed** | Icon/icon.swift:98–101 refers to undefined canvas and markData. Swift-package success does not prove app packaging. |
| `Tests/HistoryRegression/run.sh` | **Passed** | Existing focused history regression. |
| `Tests/run-extension-files-tests.sh` | **5 passed** | Fresh install, atomic replacement, two immutable-failure preservation cases and retry behavior. |
| Standalone current Address.swift probe | **Misclassification reproduced** | 10.io, 192.168.1.1.example.com and 172.16.foo.com get HTTP. 10.0.0.1 gets HTTP as intended. No network request needed. |
| AST-extracted pure `bench.folder` function | **Wrong app path confirmed** | Computes Search / Search (audit), while current Store uses Browse. No socket contacted. |
| GitHub inventory assertions | **604 unique records; 44/62 open dispositions** | Complete collection/index coverage, not complete behavioral reproduction. |
| Explicit maintainer landing references | Ancestry checked | A landed adapted patch is not necessarily identical to the original PR or inclusive of its tests. |

The temporary experiments were created from `git archive HEAD` under `/tmp/browse-audit-20261014/validation`; pristine upstream was separately extracted under `upstream-validation`. The only application-source edit to the Browse experiment was the missing `return`. Neither experiment changed the source in the working checkout. The temporary directories and raw logs are local diagnostic artifacts, not durable report dependencies.

## The failing test

`ExtensionFileAccessTests.testFilesAreNeverGrantedButSitesAre` fails at line 40, where it expects a manually granted file pattern to be reported as granted. On this WebKit the result is false. Earlier assertions checking file-access denial pass. Therefore the observed failure does **not** demonstrate that the browser grants forbidden file access. Review the test's positive-control assumption against the supported OS matrix while retaining real denial checks.

XCTest's final result is 82 tests with one failure. The subsequent Swift Testing runner reports zero tests, which is normal for that separate runner and must not be confused with the suite passing.

## Not executed

- All 62 PR test suites or every contributor's linked external CI workflow.
- Native UI/VoiceOver/IME/device interaction, production login or password flows, real permission prompts, hardware-key crash reproduction.
- Long-running app/WebContent memory or battery measurements.
- Signed/notarized release, appcast trust/update/rollback end to end, or installation of release artifacts.
- Intel, macOS 14 or macOS 15.4 execution.
- Reproduction of every issue, exhaustive historical patch review or comprehensive security penetration testing.

The main report distinguishes direct execution, source-confirmed paths and upstream-reported evidence. No passing subset is presented as a fully green baseline.
