# Performance baseline

Run from a clean committed checkout on an otherwise quiet Mac:

```sh
python3 Tests/Performance/run.py --configuration release --output /tmp/browse-baseline.json
python3 -m unittest discover -s Tests/Performance -p 'test_*.py'
```

The runner uses only owned disposable bundles and synthetic `about:blank` sessions. It refuses fewer than three repetitions. Each restored 1/20/100-tab workload starts a fresh app, waits 60 seconds, then samples a five-second idle interval. Bundle copying and signing happen before launch timing. Later workloads settle for ten seconds before each five-second sample; this is distinct from the 60-second fresh-launch idle wait. The command takes at least fifteen minutes. It leaves a world intact if its app cannot quit; it never kills unrelated processes or cleans production storage.

The JSON records the source revision, executable hash, declared build configuration, Mac model, RAM, CPU count, architecture and OS. The runner builds the requested configuration from the recorded clean revision before timing, hashes the executable, and checks that the source remains unchanged. Build and signing time are excluded. App bytes are logical disk size, not RAM. Compare the same workload, configuration, Mac, OS, power setting and background activity; repeat after changes and compare medians and min/max spread. Three observations provide only a coarse spread, not confidence intervals.

Darwin `proc_pid_rusage` supplies physical footprint and cumulative user/system CPU nanoseconds. CPU percent uses a monotonic elapsed interval; 100% means one fully occupied CPU core. The host is identified by the owned executable; content PIDs come only from the app's tab descriptions and are deduplicated. GPU/network processes remain unattributed. Exited/reused PIDs, accounting failures and changed content membership produce an unavailable result, never a fabricated zero. Footprint sums can include shared mappings and are not whole-system memory deltas.

Launch time ends at the test socket, not the first displayed frame; filesystem caches are uncontrolled. Native typing reports insertion and run-loop-rest timing, separately from rendered frames. Window cycles include fixed bench response delays. Hidden windows and `SEARCH_MEASURE=1` remove test App Nap/WebKit throttling overrides but cannot establish visible rendering, battery life, or high-refresh performance.

## Workload coverage

| Workload | Status |
| --- | --- |
| Launch, settled idle, 1/20/100 restored tabs | Implemented; synthetic blank pages measure lazy restoration |
| Native typing and 20 window cycles | Implemented; callback/command timings only |
| Heavy page | 5,000-card local fixture, hidden; no visible rendering claim |
| Video/PiP, high-refresh comparison | Not measured by hidden runner; requires visible fixture and recorded display capability |
| Group collapse versus close | Implemented with hidden heavy page; durable save/reopen awaits prerequisites |
| Extensions off/on and suspend/resume | Implemented with a permission-free local extension and heavy page |
| Three profiles, one active; translation completion | Features unavailable in this baseline |

No measurements are committed yet. Issue #22 remains in progress until the applicable workloads and a reviewed report are recorded. No claim is made about other devices/OS versions, rendering latency or battery life.
