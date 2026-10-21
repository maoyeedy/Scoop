---
name: scoop-bucket-sync
description: Use this skill to check or sync this bucket's CI workflows, bin wrappers and GitHub scaffolding against the official ScoopInstaller/BucketTemplate. Trigger when asked whether the repo has drifted from the bucket template, to bump or pin GitHub Actions, or when workflows have not been reviewed in a while.
---

# Sync with ScoopInstaller/BucketTemplate

Establish what upstream changed, report the drift, and apply only the parts that are ours to change. The template is a starting point, not a target: manifests, README, `.gitignore`, `docs/`, `CLAUDE.md` and `.claude/` are deliberately customized here.

## 1. Get the drift

```powershell
pwsh -NoProfile -File .claude/skills/scoop-bucket-sync/scripts/template-drift.ps1
```

It refreshes a shallow clone in `C:/Users/jerkl/AppData/Local/Temp/opencode/scoop-template`, prints the template's HEAD commit, then lists template files that are `Missing` or `Differs` here plus repo files the template lacks (`Extra`), then a unified diff per differing file. It compares tracked files only, so untracked scratch such as `repomix-output.xml` stays out of the report, and `bucket/`/`deprecated/` are excluded as ours. Read the template HEAD commit subject too: it states upstream's current policy (for example `ci: use pinned actions`), which explains why a given diff exists.

Keep committed helpers in PowerShell: Scoop's Pester style test requires CRLF in every non-YAML file, and a bash script with CRLF breaks subtly (the drift filter stops matching and leaks `bucket/` lines), so a `.sh` helper cannot satisfy both.

These leftovers are expected and must not be "fixed":

| Difference | Why it is ours |
|---|---|
| `bin/auto-pr.ps1` | Holds `Maoyeedy/Scoop:master` instead of the `<username>/<bucketname>` placeholder. Default branch is `master`, not `main`. |
| `Scoop-Bucket.Tests.ps1` | Passes `-BucketPath $PSScriptRoot`; scoop core's `test/Import-Bucket-Tests.ps1` declares that parameter with the same default, so it is compatible. Keep. |
| `.gitignore`, `README.md` | Bucket-specific content. |
| no `bucket/app-name.json.template` | `scoop-add` covers manifest creation. |
| no `deprecated/.gitkeep` | The directory has real manifests. |
| extra `docs/`, `CLAUDE.md`, `.claude/`, `scripts/unitylts-checkver*.ps1`, `repomix-output.xml` | Repo-local. `repomix-output.xml` is gitignored; "Only in" is not drift. |

Everything else that differs is drift. `bin/checkver.ps1`, `checkhashes.ps1`, `checkurls.ps1`, `formatjson.ps1` and `missing-checkver.ps1` are 4-line wrappers around `$SCOOP_HOME/bin/`; `auto-pr.ps1` and `test.ps1` (a Pester runner) are longer. When a wrapper differs, copy the template file rather than editing it.

## 2. Classify

Sort the drift into these buckets before touching anything, because the cheap ones hide the important one:

- **Pinned vs floating action refs** - a digest or tag (with its `# vX.Y.Z` comment) is upstream policy; `@main` works today and breaks silently later.
- **Outdated action versions** - bump the `uses:` line, keep the trailing version comment accurate.
- **Workflow structure** - an `if:` that decides whether the whole job runs belongs on the job, not on a step: a step-level condition still starts a `windows-latest` runner for every event that matches `on:`. Upstream folded the `issue_comment` handler into `pull_request.yml` for exactly this reason; a separate workflow file with a step-level guard is drift even though the behaviour looks identical.
- **Scaffolding** - issue-template config, `.yaml` schema hints, template JSON. Cheap, copy wholesale.

## 3. Apply

Prefer copying whole files (`cp <template>/.github/workflows/x.yml .github/workflows/x.yml`) over hand-merging, then re-apply any repo-specific value (currently only `bin/auto-pr.ps1`) on top. Delete a workflow file upstream no longer has once its content is folded in.

## 4. Verify

```bash
actionlint .github/workflows/*.yml
for f in .github/workflows/*.yml .github/ISSUE_TEMPLATE/config.yml; do yq eval '.' "$f" >/dev/null || echo "BAD $f"; done
gh api repos/<owner>/<repo>/commits/<tag> --jq .sha   # must equal the digest you pinned
```

Then re-run `template-drift.ps1` and confirm only the expected leftovers above remain. A digest check catches the copy-paste failure where the comment says v7.0.1 and the hash belongs to v6.0.2.

## 5. Commit

`ci: Sync workflows and tooling with BucketTemplate`, body listing each behavioural change and why. Stage the tooling paths by name (`git add -- .github/... bin/auto-pr.ps1`); this tree often carries unrelated in-progress edits to `CLAUDE.md`, `.claude/skills/*`, or `bucket/*.json`, and those must not be staged or reverted. Commit only; do not push.

## Out of scope

Manifest health is `scoop-audit`; creating a manifest is `scoop-add`. This skill only reconciles tooling and workflows.
