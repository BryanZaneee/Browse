# Native home-screen quick tools

Enable **Quick tools on the home screen** in Settings → AI. Type a request on an ordinary blank tab: `timer 5 minutes`, `18% of 3450`, `100 USD to EUR`, `make a shopping list with milk, eggs and bread`, or `note Call Sam`.

A tool replaces the suggestion rows while visible. Return searches the exact input using the configured search engine. Use the card’s controls to act on the tool. There is no component dropdown. Saved notes appear as small cards beneath the empty field; click one to edit it. Other saved cards remain in the Saved menu. Save explicitly: drafts are not retained after changing input, tabs or quitting.

For flexible wording, separately enable **Understand natural wording with Jev**, choose TypeSafe or OpenRouter, and enter that provider’s key. Try `For dinner I need to pick up tomatoes, pasta and basil`. Eligible input is sent after a 250 ms pause. Jev selects the component, content boundaries and an email recipient from source candidates; native code copies the validated text. Uncertain detail selections retain editable source input. Detail extraction is bounded to 80 words. The request batches independent general-content, checklist and recipient questions, consuming only those relevant to the selected component.

See the [PR write-up](pr-native-quick-tools.md) for the full 17-entry catalog, use cases and screenshots. Bill splitting, events, habits, goals and polls are unavailable. Their enum values remain readable for saved-data compatibility and act as internal rejection labels in Jev routing; none can render a component. Unrelated saved notes are preserved.

## Boundaries

- Off by default, separate from page AI; no new dependencies.
- Only ordinary home-screen input is eligible. Private tabs, page overlays, site-search and command modes are excluded. URL/path input is excluded; explicit contact, bookmark and email commands can resolve locally.
- Jev receives eligible input only, not history, cookies, page contents or other tabs. HTTPS requests use the selected provider’s host, refuse redirects and use an ephemeral session. Replies have a size limit, probability validation, cancellation and generation checks. No request text or provider error body is logged.
- Explicit timers, arithmetic, unit conversion, lists, notes and email drafts work without AI. Natural-language recognition is probabilistic and is not a general text-generation system.
- One timer/stopwatch per window. Timers do not survive quitting and do not notify. Reminders/trips are local planning cards. Contacts and bookmarks do not synchronize with external apps. Dice are limited to 20 rolls and 100,000 sides. Dates use Foundation and remain editable.
- Currency conversions request only currency codes from [Frankfurter](https://frankfurter.dev/). Amounts remain local and use Decimal. Rates are daily references, cached for one hour; future dates and quotes older than ten days are rejected. `$` means USD, explicitly labeled. Crypto, forecasts and historical rates are unsupported. Same-currency conversion is local.
- Up to 100 explicitly saved cards per local profile. Saved notes have no title field or Copy action; they are text with Save and, when editing a saved note, Delete.
- Email composers hand an encoded draft to the default mail app. A recipient name is never guessed into an address. Nothing is sent automatically. Draft-field edits stay local. The inbox entry is unconnected; provider OAuth, live reading and in-app sending remain unimplemented.

## Demo and checks

`SEARCH_PROBE=jev-intent-demo ./fresh.sh again` opens the existing isolated demo profile without wiping it. Quit the old demo first when loading a rebuilt binary. Test profiles keep API keys only until the process quits. A demo may receive `SEARCH_JEV_DEMO_KEY` through process environment; the app copies it into its in-memory key store and removes the environment variable during initialization. Never place keys in source, launcher arguments or saved files.

```sh
SEARCH_PROBE=jev-tests swift test -c release --arch arm64 -Xswiftc -Osize \
  --filter 'JevTests|HomeToolsIntegrationTests|IntentToolsTests'
```

Native previews are written to `/private/tmp/search-jev-previews` and `/private/tmp/searchbar-*.png`. Live checks opt in with `SEARCH_JEV_LIVE_KEY` and, for currency, `SEARCH_CURRENCY_LIVE=1`. Ordinary test runs skip live checks.

API contracts: [TypeSafe HTTP API](https://docs.typesafe.ai/api), [source-value selection](https://docs.typesafe.ai/cookbooks/pre_parsed_value_extraction_cookbook), and [OpenRouter compatibility](https://openrouter.ai/docs/guides/community/typesafe-sdk). Confidence/probability thresholds of 0.7 are conservative experiment settings, not measured accuracy guarantees.
