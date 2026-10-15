# Reading mode

Reading mode keeps an article's main text, heading, byline, opening photo and captions. The appearance buttons in each article choose light, dark or the window's appearance. The choice becomes the default for future tabs; other open articles keep their own choice. Window appearance follows live system changes. The controls introduce no animation.

Entering reading mode asks before discarding unsaved form entries. Cancel preserves the original document, and a stale approval cannot transform a newly navigated page. The original page URL and links remain intact. Find searches the extracted article. Leaving reading mode reloads the original page; navigation clears the reader state. Reading mode stores no article archive and creates no background web view.

Only explicit HTTPS embed endpoints on known video/chart providers survive. A provider name inside an unrelated URL, arbitrary frame inside a figure, credential-bearing URL or `srcdoc` does not qualify. Embeds are lazy, capped at eight and denied autoplay. HTML image elements are lazy and capped at 128; native media is capped at 16 with controls, no autoplay/loop and `preload=none`. A provider may require interaction or refuse the restricted embed. SVG and style resources are not globally capped. Reading mode is not an offline or network-isolation feature.

## Validation

`ReaderTests` uses synthetic local HTML with a Content Security Policy that blocks external resources. It checks deceptive embed URLs, media limits, original URL/links, Find and independent themes. Native window appearance, split-tab independence and dirty-entry cancellation/navigation races are covered by focused fixtures. It also checks real link/back/forward navigation, exiting by reload, and retained original media. [Native fixture captures](screenshots/reader/README.md) show the article and appearance controls. Keyboard/VoiceOver review uses the owned visible preview. No live article content is used in fixtures.

Adapted from dima237's Search PRs [564](https://github.com/driceroland/Search/pull/564) (`7df9784b10e195d21356cd734405f92a09441372`), [565](https://github.com/driceroland/Search/pull/565) (`c5925a1a3529ed83cfaf5754c8fd2691b3819387`) and [566](https://github.com/driceroland/Search/pull/566) (`d8298771c4579e1229a2aa1d820794469a88cec5`). Browse replaces their permissive frame matching and eager media behavior.
