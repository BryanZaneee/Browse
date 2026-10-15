# Native messaging validation

The #17 change registers listeners before messages can arrive, drains host output
before disconnecting, and rejects inbound frames larger than 1 MiB. Exit grace is
1.5 seconds when a child inherits stdout; a host that ignores termination is
killed after 2 seconds. Explicit disconnect finishes waiters immediately, including
a failed launch. Existing nativeMessaging permission and allowed-origin checks
remain in place.

Adapted from [Search #483](https://github.com/driceroland/Search/pull/483), reviewed
head `b938e8f6f41ae8c781e94fc5098aa530cb47ef82`, by AllDaGearNoIdea.

## Automated fixtures

Run `python3 Tests/run-unit-tests.py --filter HostPipeTests` with #74's isolation.
Fake Python hosts live in the owned XCTest directory, use synthetic JSON and have
15-second watchdogs. Teardown stops retained host objects, checks process exit,
and never sends signals based on stale PID files. The inherited-output child
exits on its own after four seconds.

The 16 cases cover large/final replies, busy readers, fast requests, persistent
ports, repeated stop, silent exit, inherited stdout, ignored termination, oversized
and exactly-at-limit frames, post-exit calls, failed launch/request cleanup, allowed
origins and denial of executables outside the fixture world.

## Deferred real integration

On 2026-10-15 the user authorized preparing the PR and deferring real password-manager
validation. This issue acceptance criterion remains outstanding: fake hosts do not
prove a supported manager can unlock or fill. Do not close #17 on fixture evidence
alone. #12's build/test gate remains a prerequisite for merging this dependent work.

Use a separate controlled macOS account or VM and a synthetic password vault for
that acceptance. Verify connect/unlock/fill, idle longer than two minutes and fill
again, extension reload/disable, browser quit, and absence of owned helper processes.
Record manager/extension versions, macOS, exact Browse SHA and signing configuration.
Upstream reports iCloud Passwords helper launch constraints requiring an entitled,
provisioned browser; an ad-hoc launch failure is not evidence about pipe handling.
Never bypass the test-world host confinement or use a real browsing profile/vault.
