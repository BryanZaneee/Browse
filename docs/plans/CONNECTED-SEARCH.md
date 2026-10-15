# Connected search and new-tab composition

Tracks [#71](https://github.com/BryanZaneee/Browse/issues/71), requested October 15, 2026. Status: draft implementation; full-app acceptance pending build and isolation gates #9/#10. This request supplements the foundation/polish plan without claiming its blocked work.

- Home and the page overlay share one rounded surface around the field, divider and suggestions. Results grow down without moving the field.
- New Tab appends its own lightweight draft tab and opens that tab's native address field/dropdown. The current page and its tab remain in place; Home's centered field is hidden. Return or a suggestion click loads the destination in that same draft tab. Escape, click-away or Command-W removes only the unsubmitted draft. Repeated New Tab resets the same draft.
- Ordinary current-address editing still navigates the current tab. Command-Return submits behind the source; Shift-Command-Return goes to it. Private drafts have their own ephemeral store. Approved extension new-tab overrides keep their existing route. Existing blank tabs and unsent Home address drafts remain untouched.
- Closing/clearing/internal replacement and the bench's `new` navigation fixture request an actual blank tab explicitly. No persistence migration, preference or dependency is added; this is the user-approved default entry flow.

The initial centered New Tab composer was superseded by the user's October 15 correction: use the existing tab dropdown, in the newly appearing tab rather than the leftmost/source tab. Earlier screenshots remain historical evidence.

Evidence and reproducible native fixture checks: [screenshots](../screenshots/README.md). Browser/tab-field regressions pass in an owned disposable preview copy with the known Store return repaired locally; the PR's unmodified build still fails that baseline error. Keep the PR draft until the build/isolation gates and remaining full-app checks pass. Retain the original implementation-plan provenance when integrating its workflow PR.
