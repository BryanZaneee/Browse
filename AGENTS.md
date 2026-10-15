# Browse screenshot recommendations

- Follow [CONTRIBUTING.md](CONTRIBUTING.md) and the issue's acceptance criteria. Keep UI changes native and use existing SwiftUI/AppKit components.
- For UI PRs, commit reproducible native screenshots in `docs/screenshots/`, including before/after states and paired light/dark captures. Preserve earlier evidence until replacements exist.
- Use synthetic history, bookmarks and documents in an owned disposable world. Never capture a real browsing profile, account, password, private page, clipboard or keychain content. Do not drive `bench` until its isolation gate is satisfied.
- Prefer 1440–1600 px wide PNG/WebP files under 300 KB. Keep text legible; document any native Retina exception up to 1 MiB. Use neutral filenames without hostnames or IP addresses.
- Show the empty field, expanded suggestions and keyboard-selected result. For overlays, also show enough of the source page to demonstrate that it stays visible. Include narrow/split layouts when affected.
- Capture real native animation frames when motion changes; check the field stays anchored and Reduce Motion remains respected. Pair screenshots with keyboard and accessibility checks; screenshots alone do not verify behavior.
- Label storage-free component fixtures and synthetic page backgrounds explicitly. They prove component layout, not end-to-end browser behavior. Do not manufacture a working-app screenshot when the app cannot build.
- Record the fixture command, source revision, macOS version, image dimensions and limitations next to the images. Review every committed frame for privacy and rendering errors.

The connected search fixture is documented in [docs/screenshots/README.md](docs/screenshots/README.md). Its command is `Tests/OmniboxFixture/run.sh`; it compiles the production search view without starting Browse, WebKit or a profile.
