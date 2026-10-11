# Native picture-in-picture fixtures

`index.html` supplies a normal article, links and an editable form beside a video. Query variants cover landscape, portrait, cross-origin iframe, disabled PiP and no video. The videos contain generated test patterns and **no audio track**. They are test resources only; the app does not bundle them.

Run from the repository root on macOS:

```sh
./build.sh debug
python3 Tests/float_video.py
python3 Tests/float_video.py --screenshots /tmp/search-pip-evidence
```

The suite uses the existing isolated Search probe harness. It briefly opens the system PiP window, keeps the source browser offscreen, and cleans up its own profile. It does not touch the regular Search profile. The screenshot option captures Search's own drawing and WebKit snapshots through `bench picture`; it is not a desktop recording. The first capture warms the offscreen renderer. Entry and return captures then use `page: false` to avoid lending the page to the bench's snapshot window during PiP.

Regenerate the committed clips with FFmpeg (a fixture authoring tool, not an app or test runtime dependency):

```sh
ffmpeg -f lavfi -i 'testsrc2=size=640x360:rate=12' -t 2 -an -c:v libx264 -crf 30 -pix_fmt yuv420p -movflags +faststart Tests/Fixtures/PictureInPicture/landscape.mp4
ffmpeg -f lavfi -i 'testsrc2=size=360x640:rate=12' -t 2 -an -c:v libx264 -crf 30 -pix_fmt yuv420p -movflags +faststart Tests/Fixtures/PictureInPicture/portrait.mp4
```

Native window dragging, resizing, restore/close controls and presentation on older macOS releases need a manual pass. A DOM presentation-mode assertion cannot establish that every native compositor frame painted correctly.

## Coverage and end-to-end checks

`float_video.py` is an integration/regression suite against the built app and real WKWebView, rather than a mock of the presentation API. It covers document/form retention, cross-origin frames, native presentation state, entry/return, playback preservation, automatic/manual transitions, source/window closure, cancellation, video replacement and dynamic site restrictions. `split_view.py` covers the unchanged pane/window behavior. Run the suites sequentially because native PiP is a system-wide resource; the PiP suite can return another floating video to its page.

For the visible end-to-end pass, use the actual toolbar/menu and macOS controls. Record the build commit, OS and architecture, and distinguish operator reports from automated results. These steps are intentionally manual: bench calls do not drive the system window's pointer gestures or prove protected playback.

| Flow | Expected result |
| --- | --- |
| Enable the optional button, then open a video and click it | Button immediately before Bookmarks opens native PiP; the page stays visible. |
| Edit a form, scroll, follow an in-page link and switch tabs while floating | Website content remains usable; returning preserves the page and draft. |
| Drag a corner with landscape and portrait media | The native window resizes with the video's proportions; no clipping. |
| Drag normally, then hold Command while dragging to the middle of the display; release mouse before Command | Normal drag snaps to corners; Command-drag leaves the window at the chosen position. |
| Use native Pause, Play, Restore and Close | Controls affect the existing video; Restore continues playback, Close pauses; the page renders without a resize. |
| Restore after switching tabs or minimizing the source window | The source tab/window returns in a normal interactive build; automation profiles suppress window activation and cannot validate the minimized-window step. |
| Play an authorized DRM stream inline, then enter PiP and return | Content the browser/service permits continues in the same media session. Record the service/content privately; a clear-video fixture is not DRM coverage. |
| Try a site/player that disallows PiP | Search respects the restriction and leaves the page usable. |
