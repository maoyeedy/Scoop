---
name: scoop-add
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
- **`homepage` must be the GitHub repo URL** (`https://github.com/owner/repo`) when `checkver` is `"github"` — `checkver` reads the repo URL from `homepage` to find the latest release. A custom project page (e.g. `gruntwork.io`) will cause `checkver` to fail with "expects the homepage to be a github repository".
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

**Pattern D — Artifact behind a signed/rotating link**
- A landing page or API hands out a link with per-request tokens (`?key1=...`), so neither the page nor the signed link can be a static `url`, and the page itself cannot be hashed (it changes every request)
- Test whether the tokens are cosmetic: fetch the link with no query and with bogus keys, and compare `ETag` / `x-goog-generation` against the signed response to confirm it is the same object
- If the object is public, use it directly (`.../UU-$version.exe#/dl.7z`) and keep `checkver` on the official page
- Capture a changing path segment as a named group, but keep the version as the first unnamed group
- Example: `uu.json`

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

The key insight: named capture groups in `checkver.regex` become `$matchGroupName` variables in `autoupdate`, via `'$match' + (Get-Culture).TextInfo.ToTitleCase(name)` (`lib/autoupdate.ps1:467`) — title case, not "capitalize the first letter", so the rest of each word is lowercased too: `(?<build>...)` → `$matchBuild`, but `(?<buildId>...)` → `$matchBuildid` and `(?<build_id>...)` → `$matchBuild_Id`. Use single-word lowercase group names.

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

Do **not** use `checkhashes.ps1` to fill a hash you do not have. It cannot write one: with
a top-level `"hash": ""` (or the key missing) `-Update` falls into the `architecture`
branch and errors on `Get-Member` and null method calls (Scoop core `checkhashes.ps1:163-178`),
leaving `hash` as it was. `URLS and hashes count mismatch` (`checkhashes.ps1:91`) is a different failure — the
`url` and `hash` arrays differ in length. A wrong non-empty hash is rewritten correctly,
but for a new manifest you have no hash to start from.

Instead, hash each url with `tools/hashurl.ps1`. It strips the `#/...` fragment (a Scoop
directive, not part of the HTTP URL), uses Scoop's user agent, and prints lowercase SHA256
(Scoop's default; no prefix needed in `hash`). Pass every arch url for multi-arch manifests:

```bash
pwsh -NoProfile -File C:/Users/jerkl/scoop/buckets/maoyeedy_scoop/tools/hashurl.ps1 'https://example.com/v1.2.3/app-x64.exe#/app.exe' 'https://example.com/v1.2.3/app-arm64.exe#/app.exe'
```

Key rules:
- If the source provides a checksum file (e.g., `SHA256SUMS`), verify against it as a sanity check, and point `autoupdate.hash` at it (`url` + `regex`/`jp`) instead of `mode: download`: a vendor checksum proves what the vendor published, a computed one only what the CDN served
- **Seed a real hash, never `""`:** Scoop only autoupdates a top-level hash that is already non-empty (`Update-ManifestProperty`), so an empty hash is permanent. If you must hash by download, give `autoupdate` its own version-less `url` — without it Scoop has nothing to download and writes `""` while exiting 0.

---

## Step 6 — Write and Format

Write the JSON to `bucket/<appname>.json` with the hashes filled in, then format it:

```powershell
pwsh -NoProfile -Command "cd 'C:/Users/jerkl/scoop/buckets/maoyeedy_scoop'; .\bin\formatjson.ps1 <appname>"
```

`formatjson.ps1` normalizes key ordering and indentation to match the bucket style. It also handles CRLF line endings (required by the repo's `.gitattributes`).

If upstream has no trackable version, omit `checkver`/`autoupdate` and say why in a `"##"` comment (see `otf-SF-Mono.json`), so `missing-checkver.ps1` output stays explainable.

---

## Step 7 — Verify

Run these in order. Each should succeed before moving to the next.

**0. Offline checks** (schema + Key Rules + autoupdate.url reproduces the static url; <1 s):
```bash
pwsh -NoProfile -File C:/Users/jerkl/scoop/buckets/maoyeedy_scoop/tools/audit.ps1 <appname> -Offline
```
Fix every `error` row before going on.

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

**2. Autoupdate hash proof:**
```bash
pwsh -NoProfile -File C:/Users/jerkl/scoop/buckets/maoyeedy_scoop/tools/provehash.ps1 <appname>
```
On a temp copy it sets every hash to 64 zeros, empties `SCOOP_CACHE`, runs `checkver -u -f`, and compares the result with your committed hash; `bucket/` is untouched. `ok` proves the autoupdate url and hash path. `not-computed` means `autoupdate.url` is missing or the hash extraction found nothing (log path in the row); `differs` means your seeded hash is wrong or the artifact changed. Plain `checkver -f` proves nothing here: with the correct hash in place it rewrites the same value.

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
| Placeholder hashes with `checkhashes.ps1` | `-Update` on `""` errors on a null method call and changes nothing; unequal url/hash arrays print `URLS and hashes count mismatch` | Compute hashes manually with `Get-FileHash`; skip `checkhashes.ps1` for new manifests |
| `autoupdate.hash` with `mode: "download"` but no `autoupdate.url` | `checkver -u -f` exits 0 and writes `"hash": ""` | Add a version-less `autoupdate.url`; it may repeat the static `url` |
| `"hash": ""` in a committed manifest | Install only warns `No hash in manifest` and proceeds unverified (`download.ps1:730`); Excavator never fills it | Seed a real hash; Scoop only updates a non-empty top-level hash |
| `checkver -f` "passes" but hash was never computed | Same manifest hash rewritten, no download log | `tools/provehash.ps1 <app>` (zeros, not `""`: an empty hash takes the `architecture` branch and stays empty) |
| URL fragment in `Invoke-WebRequest` | File downloads as empty or errors | `tools/hashurl.ps1` strips it |
| Wrong named capture casing | `$match` variable resolves empty | Title case via .NET, so `(?<buildId>...)` → `$matchBuildid`, not `$matchBuildId`. Keep group names one lowercase word |
| Unnamed group before a named `version` | checkver reports that token (e.g. the build id) as the version | Group 1 wins; a `version`-named group is only a fallback when group 1 is empty. Keep the version as the only unnamed group, or name it `version` with no unnamed groups |
| `7z l` reports `Type = PE` on an SFX | You assume it is not extractable and drop the archive | The same listing includes the embedded 7z stream; `7z x` extracts it, so `#/dl.7z` works |
| Hashing a signed/rotating landing page | Hash changes on every request, installs fail | Hash the artifact, not the page: point `url` at the public CDN object (Pattern D) |
| `powershell` instead of `pwsh` | `Get-FileHash` not recognized (inherited `PSModulePath` puts PS7's Utility module first) | Always use `pwsh -NoProfile` |
| No `extract_dir` for zips with a root folder | App files scattered or not found | Check zip structure with `7z l <file>.zip`; add `extract_dir` matching the folder name |
| `cd` in bash commands | Wrong working directory | Use `git -C <path>` for git; `pwsh -NoProfile -Command "cd '...'; ..."` for pwsh scripts |

---

## Reference

**Full schema:** `docs/scoop-manifest-reference.md` — covers all fields, all `checkver` strategies, all hash modes, all variables, and advanced patterns.

**Example manifests by pattern:**
- Pattern A (GitHub): `bucket/fetch.json`, `bucket/toasty.json`, `bucket/spicetify.json`, `bucket/editorconfig-checker.json`
- Pattern B (CDN): `bucket/feishu.json`, `bucket/uu.json`, `bucket/leigod.json`, `bucket/baidu-netdisk.json`
- Pattern C (Mirror): `bucket/blender-aliyun.json`
