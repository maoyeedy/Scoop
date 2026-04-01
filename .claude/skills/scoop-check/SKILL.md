---
name: scoop-check
description: >
  Health check for Scoop bucket repositories. Use this skill whenever the user wants
  to audit, check, verify, or inspect their Scoop bucket — including checking for
  outdated manifests, hash mismatches, or anything that might be broken or stale.
  Triggers on phrases like "check repo health", "run checkver", "verify hashes",
  "what's outdated", "audit the bucket", "check everything", or similar.
  Always present findings first and wait for explicit user approval before fixing anything.
---

# Scoop Bucket Health Check

## Overview

This skill audits a Scoop bucket by running the official maintenance scripts and
presenting findings as structured tables. Nothing is modified until the user explicitly
approves. The fix for all detected issues is `checkver <app> -u`, which re-fetches
upstream, re-runs the checkver logic, and rewrites the manifest with the correct
version, URL, and hash.

---

## Step 1 — Run the checks

Run both checks. Capture their full output.

**Check for outdated manifests** (show-only mode, no updates written):
```bash
pwsh -NoProfile -Command "cd 'C:/Users/jerkl/scoop/buckets/maoyeedy_scoop'; .\bin\checkver.ps1 * -s"
```

**Check for hash mismatches:**
```bash
pwsh -NoProfile -Command "cd 'C:/Users/jerkl/scoop/buckets/maoyeedy_scoop'; .\bin\checkhashes.ps1"
```

Always use `pwsh -NoProfile`, never `powershell`. `pwsh` (PowerShell 7+) is required for `Get-FileHash` to work correctly.

---

## Step 2 — Parse and classify results

Only report what the scripts actually flagged. Do not invent issues or perform
additional static analysis.

Classify each flagged app into one or both categories:

| Category | Source | What it means |
|---|---|---|
| **Outdated** | `checkver -s` output | Upstream version differs from manifest `version` |
| **Hash mismatch** | `checkhashes.ps1` output | Downloaded file hash doesn't match manifest `hash` |

An app can appear in both tables if both issues apply.

---

## Step 3 — Present the report

Use this exact structure:

```
## Bucket Health Report

### Outdated Manifests
| App | Current Version | Latest Version |
|-----|----------------|----------------|
| feishu | 7.20.0 | 7.21.5 |
| ...   | ...    | ...    |

### Hash Mismatches
| App | Expected Hash (manifest) | Status |
|-----|--------------------------|--------|
| uu  | abc123...                | MISMATCH |
| ... | ...                      | ...   |
```

If a category has no issues, write `✓ All good` under that heading instead of a table.

If both checks pass cleanly, write:

```
## Bucket Health Report
✓ All manifests are up to date.
✓ All hashes verified.

No action needed.
```

---

## Step 4 — Ask before fixing

After the report, if any issues were found, list the affected apps and ask:

> Want me to fix **[app-a]**, **[app-b]**, **[app-c]**?
> (This will run `checkver <app> -u` for each selected app.)

Wait for the user's response. Do not run any fix commands until they confirm.

The user may say "yes fix all", name specific apps, or say "no" — respect all responses.

---

## Step 5 — Apply fixes (only after approval)

For each approved app, run:
```bash
pwsh -NoProfile -Command "cd 'C:/Users/jerkl/scoop/buckets/maoyeedy_scoop'; .\bin\checkver.ps1 <app> -u"
```

Run them one at a time, show the output for each, and confirm success before moving on.

If `checkver -u` fails for an app (e.g., the upstream URL structure changed and the
regex no longer matches), report that it needs manual investigation — do not attempt
further workarounds.

After all fixes are applied, offer to run `.\bin\formatjson.ps1` to normalize
JSON formatting, and offer to stage + commit the changed files.
