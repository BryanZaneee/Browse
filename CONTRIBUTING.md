# Contributing

Browse is a community-maintained fork of Search. Contributions are welcome; please keep changes focused and describe the user-visible effect.

## Before writing code

For anything beyond a small fix, open an issue first describing what you want to change and why. It saves a rewritten pull request later if the direction doesn't fit.

## New features: off until someone turns them on

Browse stays small by default. Anything new that changes how the browser
looks or behaves — spaces, groups, a visible address bar, a new panel — is:

- **minimal**: the smallest version that does the job, in the app's own quiet style;
- **optional, and off by default**: someone who never asks for it never sees it;
- **findable**: a switch in Settings, and a mention in the welcome screens if it's a big one, so people know it's there to turn on.

Fixes and things every browser is expected to do (Tab moving between a form's fields, ⌘1–⌘9) don't need a switch. Before building a bigger feature, look at how other browsers do it and read what people asked for on its issue; [ROADMAP.md](ROADMAP.md) lists where each request came from.

## Where things are tracked

- [Implementation plan](docs/plans/BROWSE-IMPLEMENTATION-PLAN.md) and [issue index](docs/plans/ISSUE-INDEX.md): current Browse work, dependencies and acceptance criteria.
- [ROADMAP.md](ROADMAP.md): inherited upstream history; upstream links preserve attribution.
- [CHANGELOG.md](CHANGELOG.md): what has changed since the last version. A pull request that fixes or adds something also adds its line under **Unreleased** (and updates its roadmap status while preserving provenance), so the next update's notes write themselves.

## What tends to get merged

- **Small, focused changes.** One thing per pull request, easy to read start to finish.
- **No new dependencies.** The whole point of this app is staying small; a browser this size doesn't need a package for something Foundation or WebKit already does.
- **Matches the existing style.** Comments here explain *why*, not *what the next line does* — read a couple of existing files before adding a new one. No force-unwraps on anything that can plausibly fail (a network response, a file read, a keychain lookup).
- **Builds clean.** `swift build` with zero warnings you introduced.

## What doesn't

- Rewrites of things that already work, for style reasons alone.
- Anything that adds analytics or changes what leaves the app over the network without documenting it.
- Vendoring Chromium or any other engine. This is a WebKit browser on purpose.
- A real key or token anywhere: in code, a test, an issue, a pull request or a pasted log. Tests use keys that are obviously made up. `gitleaks git --pre-commit --staged` with the repo's `.gitleaks.toml` catches most of them before a commit; it is worth running as a pre-commit hook.

## Reporting a bug

Open an issue in this repository with: what you did, what you expected, what happened instead, and your macOS version. A crash log, if there is one, lives at `~/Library/Application Support/Browse/crash.log` — it only ever stays on your Mac unless you attach it yourself.

## Branches, commits and review

Follow [AGENTS.md](AGENTS.md) for agent ownership, isolated worktrees and review handoffs.
Use short-lived branches into `main`, one outcome per PR, and short imperative commits
such as `fix: preserve moved pins` or `feat: save closed tab groups`. Preserve upstream
authorship and link the source revision when adapting a patch.

Keep documentation, issues and PRs brief, direct and clear. Use the same short type
prefixes for issue and PR titles; keep internal plan IDs out of titles.

Use the PR template: issue or feature, code changes, actual validation, and remaining
limitations. Include reproducible screenshots for UI and comparable measurements for
performance claims. Build/test/package checks must pass where applicable; baseline
failures must be named, not hidden. A different agent reviews the exact PR head before
the human/coordinator merge decision. Creating a PR does not authorize a release.

High refresh defaults on for unset preferences under the approved Browse plan; preserve
explicit user settings. AI remains deferred until foundation acceptance.
