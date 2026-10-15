# Saved-data failures

Browse reports failed saves instead of silently discarding them. Changes stay in memory, and the latest failed snapshots are retried before quitting. If saving still fails, **Keep Working** cancels quitting; **Quit Anyway** explicitly leaves unsaved changes behind. Pending history updates are included before that decision.

Malformed JSON is moved to a unique `*.unreadable-<UUID>.json` sibling before a replacement can be saved. Keep these files for recovery. If reading or preserving the original fails, that path is protected against further saves for the rest of the process. Fix folder access/free space, preserve the original, then restart. No automatic merging of corrupted data is attempted.

Warnings show store filenames, never their contents or raw error descriptions. Repeated failures in one episode share a notice; a later save failure after recovery gets a new notice. The data-folder button opens the current profile's folder (the owned fixture folder during tests).

The shared boundary covers windows, pins, sessions, history, bookmarks, spaces, download history and learned site-search data. Formats stay unchanged. Atomic replacement and newest-save ordering remain in place. This does not promise recovery from disk hardware failure or extend to WebKit's own database/keychain storage.

## Verification

`python3 Tests/run-unit-tests.py --filter PersistenceTests` covers malformed bytes, unique backups, failed preservation, unreadable destinations, failed atomic replacement, encoding interruption, overtaken writes, retry and quit cancellation. `Tests/HistoryRegression/run.sh` also verifies that a pending visit is flushed before the debounce expires.

`Tests/PersistenceFixture/run.sh` captures native warning/recovery/quit dialogs in light and dark appearance using synthetic filenames. [Screenshots](screenshots/README.md#saved-data-notices) use the real alert content with its transparent material flattened onto the native window background; they are component evidence, not a full-app disk-failure demonstration.
