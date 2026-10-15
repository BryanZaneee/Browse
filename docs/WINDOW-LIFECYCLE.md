# Closed-window lifecycle

A window retired while another remains open releases its native window, Browser,
keyboard monitor and traffic-light callbacks. The last window deliberately keeps
its browser and tabs for New Window; reopening a retired window uses saved metadata.

Adapted from [Search #549](https://github.com/driceroland/Search/pull/549), reviewed
at `1d9c103ffd9f669f857e209055b7f1309c39c94d` (Aaditya Gaur). Browse additionally
removes Lights callbacks immediately on retirement rather than waiting for the
next window. Delayed window setup checks that its browser is still registered
or is the current refreshed scene, so a callback queued before closure cannot
reinstall traffic-light ownership after retirement. Separate upstream focus/title changes #431/#554 are not included.

Validation on Apple Silicon, macOS 27.0.1, Swift 6.4:

- `python3 Tests/run-unit-tests.py --filter ClosedWindowTests` checks five real
  window cycles using weak references to both NSWindow and Browser, plus keyboard
  hook removal. All 15 lifetime assertions failed on base `7c45c53`; the fix passes.
  A second five-cycle test closes immediately before queued setup; all five Browser
  release assertions failed before the delayed-setup guard and pass with it.
  A refreshed-scene fixture confirms styling before registration; it fails without
  the current-scene exception and passes with it.
- After `./build.sh debug`, `python3 Tests/closed_windows.py` uses an owned hidden
  world to check 20 close/open cycles, traffic-light alignment, background-window
  Command-L, restored page URLs, and retained last-window behavior. All six checks
  pass; NSApp.windows stays at 3 after each close in all 20 cycles.
- `python3 Tests/run-ci-tests.py`: 124 tests (one opt-in screenshot skipped) plus
  all seven isolated download cases pass. Debug bundle, history regression and
  all five extension-file cases also pass.

These are object-lifetime and window-count checks, not RAM, CPU or battery
measurements. Hosted Intel macOS 15 exposed the late-setup race (matching retired Browser identity
in diagnostic output); final hosted validation remains pending. Earlier macOS
versions remain untested. Native fixtures
use [test isolation](TEST-ISOLATION.md) and remove only their owned world.
