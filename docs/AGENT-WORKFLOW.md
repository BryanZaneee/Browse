# Dispatching Browse agents

[AGENTS.md](../AGENTS.md) defines the rules. [Issue index](plans/ISSUE-INDEX.md) maps the backlog; GitHub dependencies and linked PRs determine current readiness.

## Coordinator sequence

1. Merge the reviewed workflow PR before dispatching implementations from main. Start with build repair #9, test isolation #10, then CI #12. Their build/isolation/CI gates come before feature work.
2. Pick a task whose native blockers are resolved and whose acceptance prerequisites actually landed. Check for an existing PR or claim.
3. Assign one implementation owner/session and one worktree. Schedule hot files serially; independent folders alone are not proof of independent behavior.
4. Send the implementation prompt below. When its PR is ready, run a separate review session using the review prompt.
5. Address findings and rerun affected checks at the new head. A human/coordinator makes the merge decision unless explicitly delegated otherwise.
6. After merge, verify the issue closed for the right reason, verify newly unblocked tasks and clean up only owned resources.

No recurring agent runner, model API key, automatic merge or release automation is installed by this setup. No agents are assigned merely because an issue exists.

## Intake prompt

> Review Browse issue #N for implementation readiness. Read AGENTS.md, the issue's blockers, current main, linked upstream revisions and existing PRs. Check that the problem still exists, identify affected callers/persistence/tests, and resolve routine implementation choices within the agreed scope. Report Ready or Blocked with concrete evidence, any necessary issue correction and the smallest validation plan. Do not implement or create a duplicate PR during intake.

## Implementation prompt

> Implement Browse issue #N using AGENTS.md. Confirm prerequisites and ownership, record your session/branch claim, and use an isolated worktree. Deliver the smallest complete fix, required regression/validation and relevant docs. Use short commits and open a focused PR to BryanZaneee/Browse main with the required four sections. Record source attribution and actual checks. Link the PR to this thread when the tool is available, then hand off its exact head SHA for independent review. Do not merge or release.

## Review prompt

> Independently review Browse PR #N at HEAD_SHA against its linked issue and AGENTS.md. Inspect connected code, migration/failure paths, privacy boundaries, lifecycle/resources and tests; run safe targeted checks in your own worktree where useful. Do not edit the author's branch. Report actionable findings with severity, path/line, reproduction or reason, impact and missing validation. If no findings, state that and the review limits. Recheck after the head changes. Do not submit an approval under an identity that cannot genuinely approve this PR, and do not merge.

## Review handoff record

```text
Issue / PR:
Head SHA reviewed:
Acceptance criteria completed / outstanding:
Checks actually run and results:
Findings (severity, location, trigger, consequence):
Untested platforms / remaining risks:
Next owner and action:
```

## GitHub protections to add after CI

[Issue #41](https://github.com/BryanZaneee/Browse/issues/41) covers protection after CI has successful named checks. Require PRs, actual passing check contexts and resolved conversations where supported; prevent force pushes/deletion. Do not add a nonexistent CI context or a separate-account approval requirement that no available reviewer can meet. Read back the effective configuration and report platform/plan limitations.

Agents using one owner's credentials are separate reasoning sessions, not separate GitHub identities. Their reviews can supply useful evidence but cannot replace a genuinely independent account approval. A GitHub App or dedicated reviewer identity can be considered later if unattended operation is explicitly requested; no long-lived token belongs in this repository.
