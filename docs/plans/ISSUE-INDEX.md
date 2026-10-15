# Browse implementation issue index

[Delivery board](https://github.com/BryanZaneee/Browse/issues/7) · [Setup PR](https://github.com/BryanZaneee/Browse/pull/6) · [Agent rules](../../AGENTS.md) · [Dispatch prompts](../AGENT-WORKFLOW.md)

63 scoped tasks across eight milestones. This is a dependency map, not a live status mirror. GitHub blockers, claims and linked PRs determine readiness.

Start after the workflow PR merges: **[build repair](https://github.com/BryanZaneee/Browse/issues/9) → [test isolation](https://github.com/BryanZaneee/Browse/issues/10) → [CI](https://github.com/BryanZaneee/Browse/issues/12)**. Do not dispatch the entire backlog in parallel.

Each task has scope, acceptance criteria, validation, exclusions and a handoff contract. Read the [implementation plan](BROWSE-IMPLEMENTATION-PLAN.md) for product decisions.

## 0. Agent workflow

| Task | Dependencies |
|---|---|
| [docs: define agent workflow](https://github.com/BryanZaneee/Browse/issues/8) | None |
| [chore: protect main after CI passes](https://github.com/BryanZaneee/Browse/issues/41) | [#12](https://github.com/BryanZaneee/Browse/issues/12) |

## 1. Reliable foundation

| Task | Dependencies |
|---|---|
| [fix: restore Browse builds](https://github.com/BryanZaneee/Browse/issues/9) | [#8](https://github.com/BryanZaneee/Browse/issues/8) |
| [fix: isolate Browse test runs](https://github.com/BryanZaneee/Browse/issues/10) | [#9](https://github.com/BryanZaneee/Browse/issues/9) |
| [ci: check builds and tests](https://github.com/BryanZaneee/Browse/issues/12) | [#10](https://github.com/BryanZaneee/Browse/issues/10) |
| [fix: use HTTPS for public hosts](https://github.com/BryanZaneee/Browse/issues/13) | [#12](https://github.com/BryanZaneee/Browse/issues/12) |
| [fix: preserve moved pins](https://github.com/BryanZaneee/Browse/issues/14) | [#12](https://github.com/BryanZaneee/Browse/issues/12) |
| [fix: keep bookmarks out of pins](https://github.com/BryanZaneee/Browse/issues/15) | [#12](https://github.com/BryanZaneee/Browse/issues/12) |
| [fix: refresh installed extensions](https://github.com/BryanZaneee/Browse/issues/16) | [#12](https://github.com/BryanZaneee/Browse/issues/12) |
| [fix: stabilize native messaging](https://github.com/BryanZaneee/Browse/issues/17) | [#12](https://github.com/BryanZaneee/Browse/issues/12) |
| [fix: release closed windows](https://github.com/BryanZaneee/Browse/issues/18) | [#12](https://github.com/BryanZaneee/Browse/issues/12) |
| [fix: report failed state saves](https://github.com/BryanZaneee/Browse/issues/19) | [#12](https://github.com/BryanZaneee/Browse/issues/12) |
| [fix: protect drafts during moves](https://github.com/BryanZaneee/Browse/issues/20) | [#12](https://github.com/BryanZaneee/Browse/issues/12) |
| [fix: honor passkey availability](https://github.com/BryanZaneee/Browse/issues/21) | [#12](https://github.com/BryanZaneee/Browse/issues/12) |
| [perf: measure memory and interaction baselines](https://github.com/BryanZaneee/Browse/issues/22) | [#12](https://github.com/BryanZaneee/Browse/issues/12) |
| [fix: improve import discovery and permission handling](https://github.com/BryanZaneee/Browse/issues/32) | [#12](https://github.com/BryanZaneee/Browse/issues/12) |
| [fix: preserve UTF-8 in extension scripts](https://github.com/BryanZaneee/Browse/issues/33) | [#12](https://github.com/BryanZaneee/Browse/issues/12) |
| [fix: handle unsupported extension request types](https://github.com/BryanZaneee/Browse/issues/34) | [#12](https://github.com/BryanZaneee/Browse/issues/12) |
| [fix: allow authorized delayed login popups](https://github.com/BryanZaneee/Browse/issues/38) | [#12](https://github.com/BryanZaneee/Browse/issues/12) |
| [fix: arbitrate screen-sharing consent](https://github.com/BryanZaneee/Browse/issues/39) | [#12](https://github.com/BryanZaneee/Browse/issues/12) |
| [fix: restore cross-site cookie policy symmetrically](https://github.com/BryanZaneee/Browse/issues/40) | [#12](https://github.com/BryanZaneee/Browse/issues/12) |
| [fix: recover extension worker connections safely](https://github.com/BryanZaneee/Browse/issues/49) | [#17](https://github.com/BryanZaneee/Browse/issues/17) |
| [perf: measure allocator release after rule compilation](https://github.com/BryanZaneee/Browse/issues/51) | [#22](https://github.com/BryanZaneee/Browse/issues/22), [#18](https://github.com/BryanZaneee/Browse/issues/18) |

## 2. Simplification and native polish

| Task | Dependencies |
|---|---|
| [feat: remove site-search modes](https://github.com/BryanZaneee/Browse/issues/23) | [#12](https://github.com/BryanZaneee/Browse/issues/12) |
| [fix: respect native swipe-navigation preferences](https://github.com/BryanZaneee/Browse/issues/24) | [#12](https://github.com/BryanZaneee/Browse/issues/12) |
| [fix: support shortcuts on non-Latin layouts](https://github.com/BryanZaneee/Browse/issues/25) | [#12](https://github.com/BryanZaneee/Browse/issues/12) |
| [feat: add bookmark-bar context menus](https://github.com/BryanZaneee/Browse/issues/26) | [#12](https://github.com/BryanZaneee/Browse/issues/12) |
| [feat: add back and forward history menus](https://github.com/BryanZaneee/Browse/issues/27) | [#12](https://github.com/BryanZaneee/Browse/issues/12) |
| [feat: add reload-from-origin context action](https://github.com/BryanZaneee/Browse/issues/28) | [#12](https://github.com/BryanZaneee/Browse/issues/12) |
| [fix: fix address-card material clipping](https://github.com/BryanZaneee/Browse/issues/29) | [#12](https://github.com/BryanZaneee/Browse/issues/12) |
| [feat: offer a blank tab after closing the last tab](https://github.com/BryanZaneee/Browse/issues/35) (deferred) | [#12](https://github.com/BryanZaneee/Browse/issues/12) |
| [fix: preserve extension home-page choices](https://github.com/BryanZaneee/Browse/issues/37) | [#12](https://github.com/BryanZaneee/Browse/issues/12) |
| [feat: remove address commands](https://github.com/BryanZaneee/Browse/issues/42) | [#23](https://github.com/BryanZaneee/Browse/issues/23) |
| [feat: enable high refresh by default](https://github.com/BryanZaneee/Browse/issues/43) | [#22](https://github.com/BryanZaneee/Browse/issues/22) |
| [feat: clarify small-window behavior](https://github.com/BryanZaneee/Browse/issues/44) | [#18](https://github.com/BryanZaneee/Browse/issues/18) |
| [perf: smooth sidebar animations](https://github.com/BryanZaneee/Browse/issues/45) | [#22](https://github.com/BryanZaneee/Browse/issues/22), [#18](https://github.com/BryanZaneee/Browse/issues/18) |
| [feat: open submitted local-file paths](https://github.com/BryanZaneee/Browse/issues/48) | [#13](https://github.com/BryanZaneee/Browse/issues/13) |
| [fix: return media keys after paused video](https://github.com/BryanZaneee/Browse/issues/50) | [#18](https://github.com/BryanZaneee/Browse/issues/18) |
| [feat: offer roomier sidebar tabs](https://github.com/BryanZaneee/Browse/issues/58) | [#55](https://github.com/BryanZaneee/Browse/issues/55) |

## 3. Tab organization

| Task | Dependencies |
|---|---|
| [feat: polish tab groups](https://github.com/BryanZaneee/Browse/issues/55) | [#45](https://github.com/BryanZaneee/Browse/issues/45) |
| [feat: improve group actions](https://github.com/BryanZaneee/Browse/issues/59) | [#55](https://github.com/BryanZaneee/Browse/issues/55), [#20](https://github.com/BryanZaneee/Browse/issues/20) |
| [feat: save closed tab groups](https://github.com/BryanZaneee/Browse/issues/61) | [#59](https://github.com/BryanZaneee/Browse/issues/59), [#19](https://github.com/BryanZaneee/Browse/issues/19) |
| [feat: select multiple tabs](https://github.com/BryanZaneee/Browse/issues/62) | [#59](https://github.com/BryanZaneee/Browse/issues/59) |
| [feat: pin saved groups to the bar](https://github.com/BryanZaneee/Browse/issues/63) | [#61](https://github.com/BryanZaneee/Browse/issues/61) |
| [feat: close duplicate tabs](https://github.com/BryanZaneee/Browse/issues/64) | [#62](https://github.com/BryanZaneee/Browse/issues/62), [#20](https://github.com/BryanZaneee/Browse/issues/20) |

## 4. Reading workflow

| Task | Dependencies |
|---|---|
| [feat: register Browse as an alternate file handler](https://github.com/BryanZaneee/Browse/issues/11) | [#9](https://github.com/BryanZaneee/Browse/issues/9), [#12](https://github.com/BryanZaneee/Browse/issues/12) |
| [feat: improve reader presentation](https://github.com/BryanZaneee/Browse/issues/30) | [#12](https://github.com/BryanZaneee/Browse/issues/12) |
| [feat: export pages as PDF](https://github.com/BryanZaneee/Browse/issues/31) | [#12](https://github.com/BryanZaneee/Browse/issues/12) |
| [feat: add authenticated bulk password removal](https://github.com/BryanZaneee/Browse/issues/36) | [#12](https://github.com/BryanZaneee/Browse/issues/12) |
| [feat: add read later](https://github.com/BryanZaneee/Browse/issues/46) | [#30](https://github.com/BryanZaneee/Browse/issues/30), [#19](https://github.com/BryanZaneee/Browse/issues/19) |
| [feat: copy clean links](https://github.com/BryanZaneee/Browse/issues/47) | [#13](https://github.com/BryanZaneee/Browse/issues/13) |
| [feat: save a reading position](https://github.com/BryanZaneee/Browse/issues/56) | [#46](https://github.com/BryanZaneee/Browse/issues/46) |
| [feat: preview local text files safely](https://github.com/BryanZaneee/Browse/issues/57) | [#48](https://github.com/BryanZaneee/Browse/issues/48) |

## 5. Browser profiles

| Task | Dependencies |
|---|---|
| [feat: scope browsing data to profiles](https://github.com/BryanZaneee/Browse/issues/65) | [#63](https://github.com/BryanZaneee/Browse/issues/63), [#56](https://github.com/BryanZaneee/Browse/issues/56) |
| [feat: isolate profile web sessions](https://github.com/BryanZaneee/Browse/issues/66) | [#65](https://github.com/BryanZaneee/Browse/issues/65), [#17](https://github.com/BryanZaneee/Browse/issues/17) |
| [feat: add Browser profiles](https://github.com/BryanZaneee/Browse/issues/67) | [#66](https://github.com/BryanZaneee/Browse/issues/66) |
| [feat: route sites to spaces](https://github.com/BryanZaneee/Browse/issues/68) | [#67](https://github.com/BryanZaneee/Browse/issues/67) |

## 6. Native enhancements and feasibility

| Task | Dependencies |
|---|---|
| [feat: add optional dark webpage rendering](https://github.com/BryanZaneee/Browse/issues/52) | [#30](https://github.com/BryanZaneee/Browse/issues/30), [#22](https://github.com/BryanZaneee/Browse/issues/22) |
| [chore: investigate native Apple Passwords suggestions](https://github.com/BryanZaneee/Browse/issues/53) | [#17](https://github.com/BryanZaneee/Browse/issues/17), [#21](https://github.com/BryanZaneee/Browse/issues/21) |
| [chore: prototype screen sharing with audio in web calls](https://github.com/BryanZaneee/Browse/issues/54) | [#39](https://github.com/BryanZaneee/Browse/issues/39), [#18](https://github.com/BryanZaneee/Browse/issues/18) |
| [feat: add on-device text translation](https://github.com/BryanZaneee/Browse/issues/60) | [#56](https://github.com/BryanZaneee/Browse/issues/56) |
| [chore: define Browser proxy support](https://github.com/BryanZaneee/Browse/issues/69) (deferred) | [#67](https://github.com/BryanZaneee/Browse/issues/67) |

## 7. Foundation release acceptance

| Task | Dependencies |
|---|---|
| [test: validate the foundation release candidate](https://github.com/BryanZaneee/Browse/issues/70) | [#18](https://github.com/BryanZaneee/Browse/issues/18), [#19](https://github.com/BryanZaneee/Browse/issues/19), [#20](https://github.com/BryanZaneee/Browse/issues/20), [#21](https://github.com/BryanZaneee/Browse/issues/21), [#63](https://github.com/BryanZaneee/Browse/issues/63), [#64](https://github.com/BryanZaneee/Browse/issues/64), [#56](https://github.com/BryanZaneee/Browse/issues/56), [#31](https://github.com/BryanZaneee/Browse/issues/31), [#67](https://github.com/BryanZaneee/Browse/issues/67), [#42](https://github.com/BryanZaneee/Browse/issues/42), [#43](https://github.com/BryanZaneee/Browse/issues/43), [#45](https://github.com/BryanZaneee/Browse/issues/45), [#32](https://github.com/BryanZaneee/Browse/issues/32), [#49](https://github.com/BryanZaneee/Browse/issues/49), [#34](https://github.com/BryanZaneee/Browse/issues/34), [#38](https://github.com/BryanZaneee/Browse/issues/38), [#40](https://github.com/BryanZaneee/Browse/issues/40), [#13](https://github.com/BryanZaneee/Browse/issues/13), [#14](https://github.com/BryanZaneee/Browse/issues/14), [#15](https://github.com/BryanZaneee/Browse/issues/15), [#16](https://github.com/BryanZaneee/Browse/issues/16), [#22](https://github.com/BryanZaneee/Browse/issues/22), [#33](https://github.com/BryanZaneee/Browse/issues/33), [#39](https://github.com/BryanZaneee/Browse/issues/39) |
