# Connected search and new-tab composition

Tracks [#71](https://github.com/BryanZaneee/Browse/issues/71), requested October 15, 2026. Status: draft implementation; full-app acceptance pending build and isolation gates #9/#10. This request supplements the foundation/polish plan without claiming its blocked work.

- Home and the page overlay share one rounded surface around the field, divider and suggestions. Results grow down without moving the field.
- New Tab from a loaded page composes over that page. Return or a suggestion click creates the destination tab; Escape/click-away or Command-W cancels. Repeated New Tab resets the same composer.
- Ordinary current-address editing still navigates the current tab. Command-Return opens behind it; Shift-Command-Return opens in front. Private sources create private destination tabs. Approved extension new-tab overrides keep their existing route; an already blank page still uses the blank-tab behavior.
- Closing/clearing/internal replacement and the bench's `new` navigation fixture request an actual blank tab explicitly. No persistence migration, preference or dependency is added; this is the user-approved default entry flow.

Evidence and reproducible native component checks: [screenshots](../screenshots/README.md). Browser regressions: `Tests/SearchTests/NewTabTests.swift`; they cannot execute until the baseline build/isolation gates are resolved. Keep the PR draft, retain the original implementation-plan provenance when integrating its workflow PR, and do not mark later backlog work ready from this change.
