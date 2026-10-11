# Native picture-in-picture fixtures

`index.html` supplies a normal article, links and an editable form beside a video. Query variants cover landscape, portrait, cross-origin iframe, disabled PiP and no video. The videos contain generated test patterns and **no audio track**. They are test resources only; the app does not bundle them.

Run from the repository root on macOS:

```sh
./build.sh debug
python3 Tests/float_video.py
python3 Tests/float_video.py --screenshots docs/pr-evidence/picture-in-picture
```

The suite uses the existing isolated Search probe harness. It briefly opens the system PiP window, keeps the source browser offscreen, and cleans up its own profile. It does not touch the regular Search profile. The screenshot option captures Search's own drawing and WebKit snapshots through `bench picture`; it is not a desktop recording. The first capture warms the offscreen renderer. Entry and return captures then use `page: false` to avoid lending the page to the bench's snapshot window during PiP.

Regenerate the committed clips with FFmpeg (a fixture authoring tool, not an app or test runtime dependency):

```sh
ffmpeg -f lavfi -i 'testsrc2=size=640x360:rate=12' -t 2 -an -c:v libx264 -crf 30 -pix_fmt yuv420p -movflags +faststart Tests/Fixtures/PictureInPicture/landscape.mp4
ffmpeg -f lavfi -i 'testsrc2=size=360x640:rate=12' -t 2 -an -c:v libx264 -crf 30 -pix_fmt yuv420p -movflags +faststart Tests/Fixtures/PictureInPicture/portrait.mp4
```

Native window dragging, resizing, restore/close controls and presentation on older macOS releases need a manual pass. A DOM presentation-mode assertion cannot establish that every native compositor frame painted correctly.
