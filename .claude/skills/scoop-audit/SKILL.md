---
name: scoop-audit
description: >
  Health audit for Scoop bucket repositories. Use this skill whenever the user wants
  to audit, check, verify, or inspect their Scoop bucket — including checking for
  outdated manifests, hash mismatches, or anything that might be broken or stale.
  Triggers on phrases like "audit the bucket", "check repo health", "run checkver",
  "verify hashes", "what's outdated", "check everything", or similar.
  Always present findings first and wait for explicit user approval before fixing anything.
---

# Scoop Bucket Health Check

## Overview

This skill audits a Scoop bucket by running the official maintenance scripts and
presenting findings as structured tables. Nothing is modified until the user explicitly
approves.

The two categories have different fixes, and using the wrong one silently does nothing:

- **Outdated** -> `checkver.ps1 <app> -u` re-fetches upstream and rewrites version/url/hash.
- **Hash mismatch** -> `checkhashes.ps1 <app> -Update`, or `checkver.ps1 <app> -u -f`.
  Plain `checkver -u` will NOT fix a hash: when the detected version equals the manifest
  version it prints the version and `continue`s before autoupdate (`checkver.ps1:425` in
  `$SCOOP_HOME`), so a mismatch at the current version is left untouched.

---

## Step 1 — Run the checks

Run both checks. Capture their full output.

**Check for outdated manifests** (show-only mode, no updates written):
```bash
pwsh -NoProfile -Command "cd 'C:/Users/jerkl/scoop/buckets/maoyeedy_scoop'; .\bin\checkver.ps1 * -s"
```
`-s` is `-SkipUpdated`: a current manifest hits an early `continue` (`checkver.ps1:420`) and
prints nothing at all, so an empty run is a pass, not a failure.

**Check for hash mismatches:**
```bash
pwsh -NoProfile -Command "cd 'C:/Users/jerkl/scoop/buckets/maoyeedy_scoop'; .\bin\checkhashes.ps1"
```

Always use `pwsh -NoProfile`, never `powershell`. Scoop's `checkhashes.ps1` calls
`Get-FileHash`, and this machine's Windows PowerShell 5.1 has no
`Microsoft.PowerShell.Utility` module, so the cmdlet is missing there entirely.

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
> (Outdated -> `checkver <app> -u`; hash mismatch -> `checkhashes <app> -Update`.)

Wait for the user's response. Do not run any fix commands until they confirm.

The user may say "yes fix all", name specific apps, or say "no" — respect all responses.

---

## Step 5 — Apply fixes (only after approval)

Pick the command per category — they are not interchangeable:

**Outdated manifests:**
```bash
pwsh -NoProfile -Command "cd 'C:/Users/jerkl/scoop/buckets/maoyeedy_scoop'; .\bin\checkver.ps1 <app> -u"
```

**Hash mismatches:**
```bash
pwsh -NoProfile -Command "cd 'C:/Users/jerkl/scoop/buckets/maoyeedy_scoop'; .\bin\checkhashes.ps1 <app> -Update"
```

An app can be in both tables; run `checkver -u` first (it moves version and url), then
`checkhashes -Update` for whatever hash is still wrong. `checkhashes -Update` only rewrites
a hash that already exists: with a top-level `"hash": ""` it errors on a null method call
(`checkhashes.ps1:178`) and leaves the hash untouched, so those have to be computed by hand.
A wrong non-empty hash is fixed normally (verified end-to-end).

Run them one at a time, show the output for each, and confirm success before moving on.

If `checkver -u` fails for an app (e.g., the upstream URL structure changed and the
regex no longer matches), report that it needs manual investigation — do not attempt
further workarounds.

After all fixes are applied, offer to run `.\bin\formatjson.ps1` to normalize
JSON formatting, and offer to stage + commit the changed files.
