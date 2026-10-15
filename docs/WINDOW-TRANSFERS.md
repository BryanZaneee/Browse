# Moving tabs between windows

A tab moving into different Space sign-ins asks before replacing a page with
unsaved form input. Cancel changes neither window, including pending address
drafts and split partners. Same-store and private moves keep their live web view.
“Open in Browse” from a compact window uses the same check.

While the decision is pending, a changed source/destination window, Space, store,
address draft or page invalidates the move. A load-state revision catches same-URL
navigation as well as URL changes. A page still loading cannot move across stores;
retry after it finishes. The inherited unsaved detector's PDF/error behavior is
unchanged.

Run `python3 Tests/run-unit-tests.py --filter WindowTransferTests` in the isolated
runner. Nine tests cover cancel/approve, both composers, split partners, live
same-store/private transfers, drag dispatch, navigation and ownership races, and
compact-window cancel/close/approve. Tests use a real WK textarea with a synthetic
dirty report and an injected confirmation decision; the native alert test separately checks Escape cancellation in light and dark
appearances. Trusted WebKit typing and VoiceOver remain manual checks.

Manual review in an owned visible world (`./fresh.sh --visible --world moves`):

1. Enable Spaces and make a second Space with separate sign-ins. Open one window
   in each Space. Type into a local fixture textarea; keep a split partner and an
   unfinished New Tab address in the source window.
2. From the page's tab menu choose Move to Window and the other window. Cancel.
   Confirm the form, split and address draft remain intact in both windows.
3. Repeat with Move. Only that tab transfers and reopens using the destination's
   sign-ins; the split partner stays behind. Repeat via dragging to the window.
4. While confirmation is pending, change or close the destination window, or
   navigate the source page. Approve: the stale move must not occur.
5. Repeat with a compact window's Open in Browse. Cancel keeps it open; approval
   closes it only after transfer. Quit only this owned copy, then run
   `./fresh.sh wipe --world moves`.

[Native alert captures](screenshots/window-transfers/README.md) show both appearances.
No visual styling changed. VoiceOver and trusted WebKit typing remain manual;
no real browsing profile is needed for these checks.
