# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Repo Is

A [Scoop](https://scoop.sh/) bucket — a collection of JSON app manifests for the Windows package manager. Each file in `bucket/` describes how to install, verify, and auto-update one application.

For the full manifest schema, all `checkver`/`autoupdate` strategies, variable reference, and detailed workflow notes, see [`docs/scoop-manifest-reference.md`](docs/scoop-manifest-reference.md).

---

## Required CLI Tools

These must be installed (all available via `scoop install <name>`):

| Tool | Scoop package | Purpose |
|---|---|---|
| `git` | `git` | Version control |
| `7zip` | `7zip` | Extract archives and `.exe#/dl.7z` installs |
| `jq` | `jq` | Probe JSON API endpoints when writing `checkver.jp` |
| `htmlq` | `htmlq` | Probe HTML pages with CSS selectors when writing `checkver.regex` |
| `curl` | `curl` | Fetch URLs manually to inspect version sources |
| PowerShell 5.1+ | built-in | Run all `bin/*.ps1` scripts |
| Scoop itself | — | Provides `bin/checkver.ps1`, `bin/checkhashes.ps1`, etc. |

Install in one shot:
```powershell
scoop install git 7zip jq htmlq curl
```

---

## Maintenance Commands

All `bin/` scripts are PowerShell wrappers that delegate to `$SCOOP_HOME/bin/`. Run from the repo root.

```powershell
# Check version (single app or all)
.\bin\checkver.ps1 feishu
.\bin\checkver.ps1 *

# Check + update manifest (writes new version/url/hash to JSON)
.\bin\checkver.ps1 feishu -u
.\bin\checkver.ps1 * -u

# Force re-apply autoupdate even if already up-to-date (for testing)
.\bin\checkver.ps1 feishu -f

# Update to a specific version
.\bin\checkver.ps1 feishu -v 7.60.0 -u

# Show only outdated apps (no update)
.\bin\checkver.ps1 * -s

# Verify that hashes in manifests match live download URLs
.\bin\checkhashes.ps1
.\bin\checkhashes.ps1 feishu

# Format all manifests to consistent JSON style
.\bin\formatjson.ps1

# Run Pester tests
.\Scoop-Bucket.Tests.ps1

# Open auto-PRs for outdated manifests
.\bin\auto-pr.ps1
```

Enable verbose debug output from checkver:
```powershell
scoop config debug $true
.\bin\checkver.ps1 feishu -u
```

---

## Workflow

### Adding a new manifest

1. **Probe the version source** manually before writing `checkver`:
   ```powershell
   # JSON endpoint
   curl -s "https://example.com/api/versions.json" | jq .
   # HTML page
   curl -s "https://example.com/download" | htmlq "a[href*='.exe']" --attribute href
   # GitHub API
   curl -s "https://api.github.com/repos/user/repo/releases/latest" | jq '.tag_name,.assets[].browser_download_url'
   ```
2. Create `bucket/<appname>.json` with `version`, `url`, `hash`, `checkver`, `autoupdate`.
3. Test autoupdate end-to-end: set `version` to an older value, then run `.\bin\checkver.ps1 <app> -u`. Confirm version, URL, and hash update correctly.
4. Install locally to verify: `scoop install bucket\<appname>.json`
5. Format: `.\bin\formatjson.ps1 <appname>`
6. Commit: `git add bucket\<appname>.json` then commit.

### Updating an existing manifest

```powershell
.\bin\checkver.ps1 <app> -u     # detect + write new version/hash
scoop install bucket\<app>.json  # verify install still works
git add bucket\<app>.json
git commit -m "<app>: Update to version X.Y.Z"
git push
```

Excavator handles this automatically every 4 hours for all manifests that have working `checkver` + `autoupdate` blocks. Manual updates are only needed when Excavator fails (broken regex, changed URL structure, etc.).

### Debugging a broken checkver

```powershell
scoop config debug $true
.\bin\checkver.ps1 <app>
# Read the verbose output: what URL was fetched, what regex matched, what version was found
```

Then re-probe the source manually with `curl | jq` or `curl | htmlq` to see what changed.

### Deprecating a manifest

Move the file to `deprecated/` and commit. Do not delete — it serves as historical reference.

### Commit message format

`<appname>: Update to version X.Y.Z` — lowercase app name, colon separator. Matches existing history (`uu: Update to version 5.77.2`, `leigod: Update to version 11.3.1.3`).

---

## Manifest Structure

Every `bucket/*.json` follows this core shape:

```json
{
    "version": "1.2.3",
    "description": "...",
    "homepage": "https://...",
    "license": "MIT",
    "url": "https://example.com/app-1.2.3.zip",
    "hash": "sha256hex...",
    "checkver": { ... },
    "autoupdate": { ... }
}
```

Key field notes:
- `url`: append `#/dl.7z` to extract an `.exe` installer as an archive (bypasses UAC/registry side-effects); use `#/dl.exe` to just rename the download, then handle extraction manually in `installer.script` (see `leigod.json`)
- `hash`: SHA256 by default; prefix with `md5:`, `sha1:`, or `sha512:` otherwise
- `checkver`: how Excavator finds the latest version — `"github"`, `url`+`regex`, `url`+`jp` (JSONPath), or combined
- `autoupdate`: URL/hash template using `$version`, `$matchName` (named capture groups), `$majorVersion`, etc.
- `persist`: files/dirs to preserve across updates (linked via junction to `~\scoop\persist\<app>\`)
- `architecture`: use instead of top-level `url`/`hash` when 32bit and 64bit URLs differ

Many manifests in this bucket (UU, Leigod, Feishu) use **combined JSONPath + named-capture regex** in `checkver` because their CDN URLs embed non-version tokens (build IDs, CDN keys) that must also be captured and replayed in `autoupdate` via `$matchBuild`, `$matchKey1`, etc.

Full schema and all variable types: [`docs/scoop-manifest-reference.md`](docs/scoop-manifest-reference.md).

---

## Automation

**Excavator** (`.github/workflows/excavator.yml`) runs every 4 hours via `ScoopInstaller/GithubActions`. It calls `checkver * -u` on all manifests and opens PRs for any that updated. The PR workflow validates manifests on every opened PR.

---

## Git Operations

Per global shell rules: never use `cd`. Use `git -C "C:/Users/jerkl/scoop/buckets/maoyeedy_scoop" <subcommand>` for all git operations.

---

## Line Endings

`.gitattributes` sets `* text=auto eol=crlf` — working-tree files use CRLF. **This overrides the global LF rule** from `~/.claude/rules/file-encoding.md`. Do not convert line endings when editing or creating any file in this repo.

## Deprecated Manifests

`deprecated/` holds removed manifests for historical reference. Do not install from there.
