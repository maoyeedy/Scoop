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

Run one script, report what it flagged, fix only after approval. Nothing is modified
until the user explicitly approves.

---

## Step 1 — Run the audit

```bash
pwsh -NoProfile -File C:/Users/jerkl/scoop/buckets/maoyeedy_scoop/tools/audit.ps1
```

It runs `checkver * -s` (outdated), `checkhashes` (mismatches; downloads every `url`, so it
takes minutes), `tools/lint.ps1` (schema + Key Rules), `tools/checkautoupdate.ps1` and
`tools/checksources.ps1`, and prints one table of problems: `App`, `Check`, `Level`,
`Detail`, `Fix`. Apps that pass print nothing; a clean run prints `audit: no problems found`.
For a quick pass without network, add `-Offline` (lint + checkautoupdate only).

Do not run the underlying scripts one by one or add your own analysis: report what the
table says. `otf-SF-Mono` and `window-centering-helper` have no checkver by design (reason
in their `##`); a hash mismatch is their only update signal.

Use `pwsh`, never `powershell`: a `powershell` launched from this session inherits pwsh's
`PSModulePath`, PS7's `Microsoft.PowerShell.Utility` shadows the 5.1 module, and
`Get-FileHash` is missing.

---

## Step 2 — Present the report

Group the rows by `Check` and keep the script's wording:

```
## Bucket Health Report

### Outdated
| App | Change |
|-----|--------|
| feishu | 7.20.0 -> 7.21.5 |

### Hash mismatches
| App | Detail |
|-----|--------|
| uu | Mismatch found |

### Lint / autoupdate / sources
| App | Check | Level | Detail |
|-----|-------|-------|--------|
| adobe-creative-cloud-cleaner-tool | lint:hash-missing | error | top level: a url has no hash ... |
```

Omit empty sections. Warnings (`warn`, `autoupdate:skip`) are informational: list them
after the errors. If the script printed `audit: no problems found`, say so and stop.

---

## Step 3 — Ask before fixing

List the affected apps with the `Fix` column and ask:

> Want me to fix **[app-a]**, **[app-b]**?

Wait for the user's response. Do not run any fix commands until they confirm.
The user may say "yes fix all", name specific apps, or say "no" — respect all responses.

---

## Step 4 — Apply fixes (only after approval)

The fixes are not interchangeable:

| Check | Fix |
|---|---|
| `outdated` | `bin/checkver.ps1 <app> -u` (rewrites version, url, hash) |
| `hash` | `bin/checkhashes.ps1 <app> -Update`, or `bin/checkver.ps1 <app> -u -f` |
| `lint:hash-missing` / empty hash | `tools/hashurl.ps1 <url>`, then write the hash by hand |
| other `lint:*`, `autoupdate:mismatch` | edit the manifest per CLAUDE.md Key Rules |
| `source:*`, `checkver` | the upstream source moved: report it, needs manual investigation |

Plain `checkver -u` will NOT fix a hash at the current version: it prints the version and
`continue`s before autoupdate (`checkver.ps1:425` in `$SCOOP_HOME`). `checkhashes -Update`
cannot fill an empty hash: it errors on `Get-Member` and null method calls
(`checkhashes.ps1:163-178`) and leaves it untouched. An app that is both outdated and
mismatched: `checkver -u` first, then `checkhashes -Update` for what is still wrong.

Run fixes one at a time, show the output for each. After a fix, re-run the app's checks:

```bash
pwsh -NoProfile -File C:/Users/jerkl/scoop/buckets/maoyeedy_scoop/tools/audit.ps1 <app>
```

If `checkver -u` fails for an app (e.g., the regex no longer matches), report that it needs
manual investigation — do not attempt further workarounds.

After all fixes, offer to run `.\bin\formatjson.ps1` to normalize JSON formatting, and offer
to stage + commit the changed files.
