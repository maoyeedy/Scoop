---
name: scoop-create-bucket
description: >
  Create new Scoop bucket manifests from scratch. Use this skill whenever the user wants
  to add a new app to the bucket, create a manifest for a new app, package something for
  Scoop, or says things like "add <app> to the bucket", "create manifest for <app>",
  "add bucket for <url>", "new entry for <app>", "package <app> for scoop". Covers GitHub
  releases, CDN downloads, and custom version sources. Always probe the source first, then
  build the manifest incrementally. Use even if the user just pastes a GitHub URL.
---

# Create Scoop Bucket Manifest

This skill walks through adding a new `bucket/<appname>.json` manifest safely. The full
schema reference is at `docs/scoop-manifest-reference.md` — consult it for deep dives.
This skill focuses on the workflow and the pitfalls that burn you in practice.

---

## Step 1 — Gather Input

If not already provided, identify:
- **App name** — becomes the JSON filename (e.g., `toasty` → `bucket/toasty.json`)
- **Source URL** — GitHub repo, download page, or direct download URL
- **Architectures** — does the app provide separate 64bit/arm64/32bit binaries?

For GitHub URLs, extract `owner/repo` immediately — you'll use it in every `gh` command.

---

## Step 2 — Probe the Source

Always probe before writing any JSON. Never guess URL patterns.

### GitHub repos

```bash
gh repo view <owner>/<repo> --json url,description,licenseInfo -q '{homepage:.url, description:.description, license:.licenseInfo.spdxId}'
gh api repos/<owner>/<repo>/releases/latest --jq '{version:.tag_name, assets:[.assets[] | {name, content_type, size, browser_download_url}]}'
```

From these outputs, capture:
- `homepage`, `description`, `license` (use `spdxId`; `null` → check for a LICENSE file; if none → `"Freeware"`)
- `version`: strip any leading `v` from the tag (e.g., `v0.6` → `"0.6"`)
- Windows asset filenames — identify which are for 64bit/arm64/32bit and note exact names

### JSON API

```bash
curl -s "https://example.com/api/versions.json" | jq .
```

Find the field that contains the version string and the download URL.

### HTML page

```bash
curl -s "https://example.com/download" | htmlq "a[href*='.exe']" --attribute href
```

---

## Step 3 — Select Manifest Pattern

Based on what you found, pick one:

**Pattern A — GitHub release** (most common)
- Standard GitHub releases with version tags
- Download URLs are stable: `https://github.com/<owner>/<repo>/releases/download/v<version>/<asset>`
- Use `"checkver": "github"` (or `{"github": "<url>"}` if homepage differs from repo)
- Examples: `fetch.json`, `toasty.json`, `spicetify.json`, `editorconfig-checker.json`

**Pattern B — CDN with non-version tokens**
- Download URLs contain build IDs, CDN keys, or other tokens that change with each release
- Need `checkver` with JSONPath/regex + named capture groups
- `autoupdate` URL uses `$matchXxx` variables to replay those tokens
- Examples: `feishu.json`, `uu.json`, `leigod.json`

**Pattern C — Mirror/derived URL**
- Version is detected from the original source, but download comes from a different mirror
- URL structure often uses `$majorVersion.$minorVersion` for path construction
- Example: `blender-aliyun.json`

---

## Step 4 — Build the Manifest

### CRITICAL: Static URL vs Autoupdate URL

The `url` field in the manifest body uses **literal** version strings. The `autoupdate.url` field uses `$version` and `$matchXxx` **substitution variables**. Mixing these up causes 404 errors on install.

```json
// CORRECT
"url": "https://github.com/user/repo/releases/download/v0.6/app-x64.exe#/app.exe",
"autoupdate": {
    "url": "https://github.com/user/repo/releases/download/v$version/app-x64.exe#/app.exe"
}

// WRONG — $version is not substituted in static url fields
"url": "https://github.com/user/repo/releases/download/v$version/app-x64.exe#/app.exe"
```

### URL Fragment Rules

| Fragment | Effect | When to use |
|---|---|---|
| `#/name.exe` | Rename the downloaded file | Single `.exe` releases with unstable filenames |
| `#/dl.7z` | Extract the `.exe` as a 7z archive | Installer `.exe` files that would trigger UAC/registry changes |
| `#/dl.exe` | Rename to `.exe`, then use `installer.script` | Nested archives (e.g., leigod: .exe → .rdata → files) |

### License Field

| Situation | Value |
|---|---|
| GitHub repo has a license | `"MIT"`, `"GPL-3.0-or-later"`, etc. (SPDX ID from `gh repo view`) |
| Free app, no license file | `"Freeware"` |
| Proprietary with terms URL | `{ "identifier": "Proprietary", "url": "https://..." }` |
| Object form (used in this bucket) | `{ "identifier": "Freeware" }` |

### Architecture Block

Use `architecture` (with `64bit`/`arm64`/`32bit` keys) when download URLs differ per arch. Use top-level `url`/`hash` when there is only one binary for all architectures.

```json
// Single binary (top-level)
"url": "https://example.com/app.exe#/app.exe",
"hash": "abc123..."

// Multiple binaries (architecture block)
"architecture": {
    "64bit": {
        "url": "https://example.com/app-x64.exe#/app.exe",
        "hash": "abc123..."
    },
    "arm64": {
        "url": "https://example.com/app-arm64.exe#/app.exe",
        "hash": "def456..."
    }
}
```

### Pattern A Template (GitHub release)

```json
{
    "version": "1.2.3",
    "description": "...",
    "homepage": "https://github.com/owner/repo",
    "license": "MIT",
    "architecture": {
        "64bit": {
            "url": "https://github.com/owner/repo/releases/download/v1.2.3/app-x64.exe#/app.exe",
            "hash": ""
        },
        "arm64": {
            "url": "https://github.com/owner/repo/releases/download/v1.2.3/app-arm64.exe#/app.exe",
            "hash": ""
        }
    },
    "bin": "app.exe",
    "checkver": "github",
    "autoupdate": {
        "architecture": {
            "64bit": {
                "url": "https://github.com/owner/repo/releases/download/v$version/app-x64.exe#/app.exe"
            },
            "arm64": {
                "url": "https://github.com/owner/repo/releases/download/v$version/app-arm64.exe#/app.exe"
            }
        }
    }
}
```

For a zip archive (no rename needed):
```json
"url": "https://github.com/owner/repo/releases/download/v1.2.3/app-1.2.3-windows-x64.zip",
"autoupdate": {
    "url": "https://github.com/owner/repo/releases/download/v$version/app-$version-windows-x64.zip"
}
```

For a single `.exe` (no architecture split):
```json
"url": "https://github.com/owner/repo/releases/download/v1.2.3/app.exe#/app.exe",
"hash": "",
"bin": "app.exe",
"checkver": "github",
"autoupdate": {
    "url": "https://github.com/owner/repo/releases/download/v$version/app.exe#/app.exe"
}
```

### Pattern B Template (CDN with named captures)

The key insight: named capture groups in `checkver.regex` become `$matchGroupName` variables in `autoupdate`. Only the first letter is uppercased: `(?<build>...)` → `$matchBuild`, `(?<key1>...)` → `$matchKey1`.

```json
{
    "version": "7.65.8",
    "description": "...",
    "homepage": "https://example.com/",
    "license": { "identifier": "Freeware" },
    "url": "https://cdn.example.com/<literal-id>/App-<literal-arch>-7.65.8.exe#/dl.7z",
    "hash": "",
    "checkver": {
        "url": "https://example.com/api/versions",
        "jp": "$.versions.Windows.download_link",
        "regex": "/(?<id>[\\w]+)/App-(?<arch>[\\w_]+)-([\\d\\.]+)\\.exe"
    },
    "autoupdate": {
        "url": "https://cdn.example.com/$matchId/App-$matchArch-$version.exe#/dl.7z",
        "hash": {
            "url": "https://example.com/api/versions",
            "jp": "$.versions.Windows.hash"
        }
    }
}
```

See `bucket/feishu.json` (jp + regex + CDN hash) and `bucket/uu.json` (regex + reverse + query params) for real examples.

---

## Step 5 — Compute Hashes

Do **not** use `checkhashes.ps1` for new manifests. It is fragile when hash fields are missing or contain placeholders — it throws 404 errors or "count mismatch" failures.

Instead, download each file manually and hash it:

```powershell
pwsh -NoProfile -Command "
    \$url = 'https://example.com/release/v1.2.3/app-x64.exe'  # strip any #/... fragment
    \$tmp = '\$env:TEMP\app-x64.exe'
    Invoke-WebRequest -Uri \$url -OutFile \$tmp
    (Get-FileHash \$tmp -Algorithm SHA256).Hash.ToLower()
    Remove-Item \$tmp
"
```

Key rules:
- **Strip the URL fragment** (`#/app.exe`, `#/dl.7z`) before downloading — it's a Scoop directive, not part of the HTTP URL
- Use `-Algorithm SHA256` (Scoop default; no prefix needed in the `hash` field)
- Output must be lowercase hex
- For multi-arch manifests, download and hash each binary separately
- If the source provides a checksum file (e.g., `SHA256SUMS`), verify against it as a sanity check

---

## Step 6 — Write and Format

Write the JSON to `bucket/<appname>.json` with the hashes filled in, then format it:

```powershell
pwsh -NoProfile -Command "cd 'C:/Users/jerkl/scoop/buckets/maoyeedy_scoop'; .\bin\formatjson.ps1 <appname>"
```

`formatjson.ps1` normalizes key ordering and indentation to match the bucket style. It also handles CRLF line endings (required by the repo's `.gitattributes`).

---

## Step 7 — Verify

Run these in order. Each should succeed before moving to the next.

**1. Version detection:**
```powershell
pwsh -NoProfile -Command "cd 'C:/Users/jerkl/scoop/buckets/maoyeedy_scoop'; .\bin\checkver.ps1 <appname>"
```
Expected: prints `<appname>: <version>` with no errors.

If it fails, enable debug output to see exactly what URL was fetched and what regex matched:
```powershell
pwsh -NoProfile -Command "scoop config debug `$true; cd 'C:/Users/jerkl/scoop/buckets/maoyeedy_scoop'; .\bin\checkver.ps1 <appname>"
```
Then re-probe the source to see what changed, and fix the `checkver` block.

**2. Autoupdate test (recommended for new manifests):**
```powershell
pwsh -NoProfile -Command "cd 'C:/Users/jerkl/scoop/buckets/maoyeedy_scoop'; .\bin\checkver.ps1 <appname> -f"
```
The `-f` flag forces autoupdate even if already current. Verify the JSON now contains the correct `version`, `url`, and `hash`. If something breaks, check that `autoupdate` URLs use `$version` (not a literal), and that named capture variables are spelled correctly.

**3. Install test:**
```powershell
scoop install 'C:\Users\jerkl\scoop\buckets\maoyeedy_scoop\bucket\<appname>.json'
```
Then verify the app runs (`<appname> --version` or similar). Uninstall when done:
```powershell
scoop uninstall <appname>
```

---

## Step 8 — Commit

```bash
git -C "C:/Users/jerkl/scoop/buckets/maoyeedy_scoop" add bucket/<appname>.json
git -C "C:/Users/jerkl/scoop/buckets/maoyeedy_scoop" commit -m "Add <appname>"
```

Commit message format for new manifests: `Add <appname>` (matches repo history: `Add toasty`, `Add fetch`, `Add code2prompt`).

---

## Pitfalls Reference

| Pitfall | Symptom | Fix |
|---|---|---|
| `$version` in static `url` | 404 on `scoop install` | Use literal version in `url`; `$version` only in `autoupdate` |
| Placeholder hashes with `checkhashes.ps1` | `OperationStopped: (404)` or "count mismatch" | Compute hashes manually with `Get-FileHash`; skip `checkhashes.ps1` for new manifests |
| URL fragment in `Invoke-WebRequest` | File downloads as empty or errors | Strip `#/...` fragment before constructing the download URL |
| Wrong named capture casing | `$match` variable resolves empty | First letter uppercased only: `(?<build>...)` → `$matchBuild`, `(?<key1>...)` → `$matchKey1` |
| `powershell` instead of `pwsh` | `Get-FileHash` or script errors | Always use `pwsh -NoProfile` |
| No `extract_dir` for zips with a root folder | App files scattered or not found | Check zip structure with `7z l <file>.zip`; add `extract_dir` matching the folder name |
| `cd` in bash commands | Wrong working directory | Use `git -C <path>` for git; `pwsh -NoProfile -Command "cd '...'; ..."` for pwsh scripts |

---

## Reference

**Full schema:** `docs/scoop-manifest-reference.md` — covers all fields, all `checkver` strategies, all hash modes, all variables, and advanced patterns.

**Example manifests by pattern:**
- Pattern A (GitHub): `bucket/fetch.json`, `bucket/toasty.json`, `bucket/spicetify.json`, `bucket/editorconfig-checker.json`
- Pattern B (CDN): `bucket/feishu.json`, `bucket/uu.json`, `bucket/leigod.json`, `bucket/baidu-netdisk.json`
- Pattern C (Mirror): `bucket/blender-aliyun.json`
