# Browse agent instructions

## Product and authority

- Work in `BryanZaneee/Browse`; the default branch is `main`. Search is upstream reference, not a publishing destination.
- Read the assigned issue, linked dependencies, relevant source and tests, [implementation plan](docs/plans/BROWSE-IMPLEMENTATION-PLAN.md), and [CONTRIBUTING.md](CONTRIBUTING.md) before editing.
- Keep Browse native, responsive and inexpensive when idle. Prefer existing SwiftUI/AppKit/WebKit code over dependencies or frameworks.
- AI remains deferred. User-approved changes include removing site-search/address commands and enabling high refresh by default for unset preferences, while preserving explicit choices. Do not generalize “optional features off” into reversing those decisions.
- Issue scope and acceptance criteria define the job. Report stale assumptions and propose a smaller complete fix; do not silently expand scope or weaken safeguards.

## Claim, isolate and coordinate

- Consult [the issue index](docs/plans/ISSUE-INDEX.md). Only implement work whose dependencies are merged and acceptance is satisfied; a closed issue alone is not proof.
- Re-read the issue, assignee, claims and open linked PRs before claiming it. One implementation owner per issue. Record your agent/session identifier, branch/worktree and scope in a short claim comment, then re-read for competing claims. An assignee account alone cannot distinguish agents sharing credentials.
- Use a separate git worktree and branch per implementation agent: `fix/<issue>-short-name`, `feat/<issue>-short-name`, or `chore/<issue>-short-name`. Never have agents edit the same checkout concurrently. Do not reset, clean, stash or overwrite another agent's work.
- Use only owned disposable test worlds. Until the isolation issue is fixed, do not drive `bench` against real Browse/Search profiles. Profile isolation does not isolate the system clipboard or keychain; use fixtures and existing test seams.
- Parallelize only issues without unresolved dependencies or overlapping ownership of shared files. Browser.swift, TabBar.swift, Prefs.swift, Store.swift and extension globals often conflict. A coordinator schedules those changes serially or explicitly assigns distinct scopes.
- Do not automatically launch a swarm. A user/coordinator assigns work; agents may request independent review. Avoid recursive delegation and duplicate PRs.
- Use milestones for grouping, native blockers for prerequisites, and claims/linked PRs for ownership and progress. State deferred work explicitly in its issue. Do not add priority or workflow-state labels.

## Implement the smallest complete change

- Trace callers, persistence, menus, preferences, imports/exports, extensions and tests before changing shared behavior.
- Keep one user-visible outcome per PR. Preserve error handling, accessibility, private-mode boundaries, draft protection and attribution when adapting upstream code.
- Re-read the current upstream PR and SHA before reusing it. Check whether main already contains an adapted version. Record the source URL/SHA and retain author credit; old audit findings may be stale.
- Never persist secrets or private page content in logs, fixtures, screenshots or commits. Do not initialize inactive profiles, hidden web views, models or timers merely to display a feature menu.
- Persistence changes need backward-compatible decoding, failure handling and recoverable migration. Saved groups/read-later entries must not retain live web views.
- Add a focused regression for nontrivial behavior. Do not add tests that merely restate implementation or weaken failing security assertions to make CI green.

## Validation and evidence

- Baseline commands: `swift build`, `swift test`, `./build.sh debug`, `Tests/HistoryRegression/run.sh`, `Tests/run-extension-files-tests.sh`. Run the relevant checks and any required CI gate; use targeted native harness tests for affected behavior after isolation is repaired.
- Known starting defects: Store.folder missing return, icon generator references removed variables, bench profile-name mismatch, and a host-dependent ExtensionFileAccessTests fixture failure. Reconfirm against your base. Report baseline failures separately; do not call the suite green when they remain.
- No app tests are required for documentation-only changes. Check links/templates/diffs instead. Never claim an unrun check passed.
- UI changes need reproducible native fixture screenshots in `docs/screenshots/`, light/dark coverage where applicable, keyboard/accessibility checks and real animation evidence when motion is changed. See repo-conventions for format; preserve existing screenshots until replacements exist.
- Performance claims need the same workload/Mac/OS/configuration, repeated measurements and separate host/WebKit memory. Disk size is not RAM, and idle CPU is not battery life. State untested devices/OS versions.
- Update CHANGELOG Unreleased and relevant documentation for user-visible work; update plan/issue status without deleting historical provenance.

## Writing

- Keep documentation, issues and PRs brief, direct and clear. Lead with the outcome; include only scope, decisions and evidence needed to act or review. Link shared rules instead of repeating them.
- Use familiar prefixes for issue and PR titles: `fix:` for bugs, `feat:` for features, `perf:` for performance, `docs:` for documentation, `ci:` for CI, `test:` for validation, and `chore:` for maintenance or investigation. Follow with a short, concrete action. Keep plan IDs out of titles.

## Commits

- Use short imperative subjects, generally under 60 characters: `fix: preserve moved pins`, `feat: save closed tab groups`, `perf: reduce sidebar layout work`, `ci: check app bundles`, `docs: document agent workflow`.
- Use a small number of coherent commits. Stage explicit paths, inspect the staged diff and run the available secret guard. Never include another agent's files, local profiles, credentials, raw diagnostic dumps or generated builds.
- Keep upstream authorship/co-author credit and license notices. Source PR and reviewed SHA belong in the commit body or PR, not a long subject.

## Pull requests and handoff

- Open PRs against Browse `main` using [.github/pull_request_template.md](.github/pull_request_template.md). Use `Closes #N` only when all of that issue's acceptance criteria are delivered; use `Refs #N` for partial work.
- Required sections: **Issue or feature**, **Code changes**, **Validation**, **Remaining limitations**. Explain final behavior and relevant code, not conversation history. List exact commands/results and source attribution. Provide before/after UI evidence or resource measurements when applicable.
- Draft PRs may be used for substantive work in progress; do not create empty placeholder PRs for every issue. Link dependencies and stack bases explicitly. PR creation does not authorize merge or release.
- Register every PR created or worked on using the thread's `link_pull_request` tool when available; verify with `list_thread_pull_requests` before finishing.
- Hand off with issue/PR URLs, head SHA, changed areas, completed criteria, actual checks, unresolved risks and the next action. Keep the issue in review until merged and validated; do not close it merely because code was pushed.

## Independent review and merge

- A review agent reads the issue, full diff and connected code at an exact head SHA. Review correctness, data loss, privacy/security, lifecycle/resource use, compatibility, accessibility and test strength.
- Review without editing the author's branch. Report actionable findings with severity, path/line, trigger and consequence; distinguish reproduced bugs from hypotheses. If none, state no findings plus checks and limitations, not “safe” without evidence.
- Implementer fixes findings; reviewer rechecks the new SHA. Avoid cosmetic review churn. High-risk profile/persistence/permissions work needs explicit focused validation.
- Agents sharing one GitHub identity cannot supply a genuinely separate GitHub account approval. A separate review session can provide evidence but must not impersonate a reviewer or claim it satisfies hosted approval rules.
- Human/coordinator approval is the default merge gate unless the user explicitly delegates merging. No auto-merge, signing-secret changes, tags or releases without that authorization.
- After merge, reconcile dependencies: verify newly unblocked issues before assigning them and clean up only owned branches/worktrees.

## Versioned releases

- Deliver releases as batches of reviewed changes. Record the target version, included issues/PRs, explicit deferrals and release blockers in the delivery tracker. Keep the existing phase milestones and native dependency order; a target date does not waive acceptance criteria.
- Browse 1.0 targets the existing backlog, including connected search/new-tab entry (#71). Explain and obtain a scope decision for exclusions. Feasibility issues require an evidenced go/no-go decision, not an unsupported feature promise; AI remains deferred under the product plan.
- Merge approved, independently reviewed feature/fix PRs into `main` incrementally. Each PR stays focused; the release combines their results. A merge makes code available for the next release but does not deliver an update to users. Do not add a permanent develop branch.
- Before release, freeze the intended scope and validate a combined release candidate at an exact `main` SHA. Run required build/test/package gates and the release acceptance matrix, including persistence/migration recovery, privacy boundaries, keyboard/accessibility, supported platforms and install-update-rollback. Record actual evidence and unresolved blockers; validate release fixes again at the new candidate SHA.
- Prepare a release PR updating `VERSION`, `NOTES.md` and `CHANGELOG.md`, with included PRs, user-facing changes, compatibility/migration notes and known limitations. Keep the first `NOTES.md` paragraph suitable for the update feed. Version and build identifiers must satisfy the updater's newer-build rules.
- After explicit release authorization and a validated final SHA, push the matching `v<VERSION>` tag. Follow [README releasing instructions](README.md#releasing) and the [release workflow](.github/workflows/release.yml) to sign/notarize Apple Silicon and Intel bundles and publish downloads and signed update feeds. Keep signing identity continuity; never commit credentials. Review credentials, tags and publication under the authority rules above.
- Verify the published assets and each architecture's update feed, then test installing/updating the signed app and relaunching with user data intact in owned fixtures. Signed Browse installations receive updates through the updater; ad-hoc development previews require a separate signed installation. Confirm delivery before marking the release shipped, and reconcile included issues, release notes and follow-up work.
- If release acceptance fails, stop publication and fix or explicitly defer the affected work. After publication, handle regressions through a reviewed corrective release or a separately authorized rollback; never move an existing release tag or assume an older build will install through the updater.

Dispatch and review prompt examples: [docs/AGENT-WORKFLOW.md](docs/AGENT-WORKFLOW.md).
