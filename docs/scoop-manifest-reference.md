# Scoop Bucket Maintenance Reference

Extracted and condensed from the official Scoop wiki. Covers everything needed to write, maintain, and auto-update manifests in this bucket.

---

## Table of Contents

1. [Manifest JSON Schema](#manifest-json-schema)
2. [checkver — Version Detection](#checkver--version-detection)
3. [autoupdate — Auto-Update Templates](#autoupdate--auto-update-templates)
4. [Hash Extraction Strategies](#hash-extraction-strategies)
5. [Internal Variables Reference](#internal-variables-reference)
6. [Pre/Post Install Scripts](#prepost-install-scripts)
7. [Persistent Data](#persistent-data)
8. [Maintenance Workflow](#maintenance-workflow)
9. [Testing Autoupdate](#testing-autoupdate)
10. [Tricks and Edge Cases](#tricks-and-edge-cases)

---

## Manifest JSON Schema

### Required Fields

| Field | Type | Notes |
|---|---|---|
| `version` | string | Current version string |
| `description` | string | One-line description (omit app name if same as filename) |
| `homepage` | string | URI |
| `license` | string or object | SPDX identifier, `"Freeware"`, `"Proprietary"`, `"Shareware"`, `"Unknown"`. Use `{ "identifier": "...", "url": "..." }` for non-SPDX. Multiple licenses: `,` (different files), `|` (dual-licensed). |
| `url` or `architecture` | string/array/object | Download URL(s). Use `architecture` when 32bit/64bit differ. |
| `hash` | string or array | SHA256 by default. Prefix: `sha512:`, `sha1:`, `md5:` |

### Optional Fields

| Field | Type | Notes |
|---|---|---|
| `##` | string or array | Comments (replaces deprecated `_comment`) |
| `architecture` | object | Keys: `64bit`, `32bit`, `arm64`. Each can contain: `bin`, `checkver`, `extract_dir`, `hash`, `installer`, `pre_install`, `post_install`, `shortcuts`, `uninstaller`, `url` |
| `autoupdate` | object | Auto-update definition. See [autoupdate section](#autoupdate--auto-update-templates). |
| `bin` | string or array | Executables/scripts to shim onto PATH. Alias shim: `["program.exe", "alias", "--args"]`. Single alias must be double-wrapped: `[["program.exe", "alias"]]`. |
| `checkver` | string or object | Version detection. See [checkver section](#checkver--version-detection). |
| `depends` | string or array | Runtime dependencies (auto-installed). |
| `env_add_path` | string | Directory relative to install dir to add to PATH. |
| `env_set` | object | Environment variables to set. Use `$persist_dir`, `$dir`, etc. |
| `extract_dir` | string | Extract only this subdirectory from the archive. |
| `extract_to` | string | Extract all content into this subdirectory. |
| `innosetup` | boolean | `true` if installer is InnoSetup-based. |
| `installer` | object | Run a non-MSI installer. Fields: `file`, `script`, `args`, `keep`. |
| `notes` | string or array | Message shown after install. |
| `persist` | string or array | Files/dirs to persist across updates. See [persist section](#persistent-data). |
| `post_install` | string or array | PowerShell commands run after install. |
| `pre_install` | string or array | PowerShell commands run before install. |
| `pre_uninstall` | string or array | PowerShell commands run before uninstall. |
| `post_uninstall` | string or array | PowerShell commands run after uninstall. |
| `psmodule` | object | Install as PowerShell module. Required field: `name`. |
| `shortcuts` | array | `[["target.exe", "Shortcut Name"], ...]`. Optional 3rd arg: start params. Optional 4th arg: icon path. Supports subdirs: `"SubDir\\Name"`. |
| `suggest` | object | Optional complementary apps. `"Feature": ["bucket/app1", "app2"]`. Suppressed if any suggested app is already installed. |
| `uninstaller` | object | Same as `installer` but for uninstall. |

### URL Tricks

- Append `#/dl.7z` to any URL to force Scoop to download and extract it as a 7z archive — bypasses installers that trigger UAC, registry changes, or place files outside the install dir:
  ```
  "url": "https://example.com/setup.exe#/dl.7z"
  ```
- Multiple URLs as array: `"url": ["https://.../a.zip", "https://.../b.zip"]`
- Rename download with fragment: `"url": "https://example.com/file.exe#/renamed.exe"`

### Deprecated Fields

- `_comment` → use `##`
- `msi` → treat `.msi` as a zip (just don't include the `msi` property)

---

## checkver — Version Detection

`checkver` tells `checkver.ps1` and Excavator where to find the current version.

### Simplest: regex on homepage

```json
"checkver": "Version ([\\d.]+)"
```

### Regex on a different URL

```json
"checkver": {
    "url": "https://example.com/download.html",
    "regex": "Download App ([\\d.]+)"
}
```

### GitHub latest release (ignores pre-releases)

```json
"homepage": "https://github.com/user/repo",
"checkver": "github"
```

Or with a different URL than homepage:

```json
"checkver": {
    "github": "https://github.com/user/repo"
}
```

Default tag pattern: `\/releases\/tag\/(?:v|V)?([\d.]+)`

### JSONPath on a JSON endpoint

```json
"checkver": {
    "url": "https://example.com/api/versions.json",
    "jsonpath": "$.latestVersion"
}
```

Short alias `jp` works too:

```json
"checkver": {
    "url": "https://example.com/api.json",
    "jp": "$..versions[?(@.channel == 'stable')].version"
}
```

### XPath on an XML endpoint

```json
"checkver": {
    "url": "https://example.com/updates.xml",
    "xpath": "//release[@channel='stable']/@version"
}
```

### JSONPath + Regex combined

Scoop runs the JSONPath first, then matches regex against the result:

```json
"checkver": {
    "url": "https://example.com/versions.json",
    "jsonpath": "$.stable",
    "regex": "v([\\d.]+)"
}
```

### Named capture groups → match variables

Named groups become `$matchGroupName` variables in `autoupdate`:

```json
"checkver": {
    "url": "https://example.com/releases",
    "regex": "/(?<id>[\\w]+)/App-(?<arch>[\\w]+)-([\\d\\.]+)\\.exe"
}
```

This creates `$matchId`, `$matchArch`, `$match3` (unnamed 3rd group).

> **Naming convention**: only first letter of group name is uppercased in variable: `(?<myGroup>...)` → `$matchMyGroup`

### `replace` — computed version string

Unnamed groups `${1}`, `${2}` feed into `replace`:

```json
"checkver": {
    "url": "https://example.com/commits.atom",
    "regex": "(\\d+)-(\\d+)-(\\d+)[\\S\\s]*?(?<sha>[0-9a-f]{40})",
    "replace": "0.${1}.${2}.${3}"
}
```

### `reverse: true` — match last occurrence

```json
"checkver": {
    "url": "https://example.com/releases/",
    "regex": "app-r(?<version>[\\d]+)\\.exe",
    "reverse": true
}
```

### PowerShell script (complex cases)

```json
"checkver": {
    "script": [
        "$page = Invoke-WebRequest 'https://example.com'",
        "if ($page.Content -match 'Version: ([\\d.]+)') { $matches[1] }"
    ]
}
```

### All `checkver` Properties

| Property | Type | Notes |
|---|---|---|
| `github` | uri | GitHub repo URL |
| `url` | uri | Page to fetch. Supports version variables. |
| `regex` / `re` | regex | Version pattern |
| `jsonpath` / `jp` | jsonpath | JSONPath expression |
| `xpath` | string | XPath expression |
| `reverse` | boolean | Match last occurrence (default: first) |
| `replace` | string | Rewrite version from capture groups |
| `useragent` | string | Custom User-Agent header |
| `script` | string or array | PowerShell commands for complex scenarios |

---

## autoupdate — Auto-Update Templates

Requires a working `checkver` block. Excavator calls `checkver.ps1 -u` to apply.

### Simple single-architecture

```json
"autoupdate": {
    "url": "https://example.com/app-v$version.zip"
}
```

### Multi-architecture

```json
"autoupdate": {
    "architecture": {
        "64bit": {
            "url": "https://example.com/app-$version-x64.zip"
        },
        "32bit": {
            "url": "https://example.com/app-$version-x86.zip"
        }
    }
}
```

Global properties (outside `architecture`) apply to all arches. Per-arch properties override them.

### With extract_dir

```json
"autoupdate": {
    "url": "https://example.com/app-$version.zip",
    "extract_dir": "app-$version"
}
```

### With captured variables from checkver

```json
"checkver": {
    "url": "https://cdn.example.com",
    "regex": "/(?<id>[\\w]+)/App-(?<arch>[\\w_]+)-([\\d\\.]+)\\.exe"
},
"autoupdate": {
    "url": "https://cdn.example.com/$matchId/App-$matchArch-$version.exe#/dl.7z"
}
```

### Properties supported in autoupdate

`bin`, `extract_dir`, `extract_to`, `env_add_path`, `env_set`, `installer`, `license`, `note`, `persist`, `post_install`, `psmodule`, `shortcuts`, `url`, `hash`

> All except `autoupdate.note` can be set globally or per-architecture.

---

## Hash Extraction Strategies

### Fallback (always works): download and hash locally

If `hash` is omitted or all methods fail, Scoop downloads the file and hashes it.

### From a plain text / SHA file (default mode: `extract`)

Built-in patterns — no config needed if file looks like:
```
abcdef0123456789...  *example.zip
```

Custom regex with `find`:

```json
"hash": {
    "url": "https://example.com/hashes.txt",
    "find": "SHA256\\($basename\\)=\\s+([a-fA-F\\d]{64})"
}
```

Use `$baseurl` to derive URL from the download URL:

```json
"hash": {
    "url": "$baseurl/SHA256SUMS"
}
```

Append a suffix to the download URL:

```json
"hash": {
    "url": "$url.sha256"
}
```

### From a JSON file

```json
"hash": {
    "mode": "json",
    "jp": "$.files.['$basename'].sha512",
    "url": "$baseurl/hashes.json"
}
```

### From an XML/RDF file

```json
"hash": {
    "mode": "rdf",
    "url": "https://example.com/digest.rdf"
}
```

```json
"hash": {
    "url": "https://example.com/hashes.xml",
    "xpath": "//file[@name='$basename']/sha256"
}
```

### From Metalink

```json
"hash": {
    "mode": "metalink"
}
```

### FossHub and SourceForge (automatic)

URLs matching these domains auto-detect hash mode — no `hash` block needed:
- `fosshub.com` → SHA256 from their JSON
- `sourceforge.net` / `downloads.sourceforge.net` → SHA1 from their JSON

### `autoupdate.hash` Properties

| Property | Type | Notes |
|---|---|---|
| `mode` | enum | `extract` (default), `json`, `xpath`, `rdf`, `metalink`, `fosshub`, `sourceforge`, `download` |
| `url` | uri | URL to hash file. Supports all variable types. |
| `regex` / `find` | regex | Pattern to extract hash from text |
| `jsonpath` / `jp` | jsonpath | JSONPath to hash value |
| `xpath` | string | XPath to hash value |

---

## Internal Variables Reference

### Version Variables

Available everywhere in `autoupdate` URLs, `extract_dir`, `env_set`, scripts, etc.

| Variable | Example (version `3.7.1.2-rc.1`) |
|---|---|
| `$version` | `3.7.1.2-rc.1` |
| `$underscoreVersion` | `3_7_1_2-rc.1` (dots → underscores) |
| `$dashVersion` | `3-7-1-2-rc.1` |
| `$cleanVersion` | `3712rc1` (all non-alphanumeric removed) |
| `$majorVersion` | `3` |
| `$minorVersion` | `7` |
| `$patchVersion` | `1` |
| `$buildVersion` | `2` |
| `$matchHead` | `3.7.1` (first 2-3 dot-separated numbers) |
| `$matchTail` | `.2-rc.1` (remainder after `$matchHead`) |
| `$preReleaseVersion` | `rc.1` (after last `-`) |

### Captured Variables

From **named** capture groups `(?<name>...)` in `checkver.regex`:

- In `checkver.replace`: `${name}`, `${1}`, `${2}`...
- In `autoupdate`: `$matchName` (first letter of group name uppercased), `$match1`, `$match2`...

Example: `(?<year>\d{4})-(?<month>\d{2})` → `$matchYear`, `$matchMonth`

### URL Variables (in `autoupdate.hash`)

| Variable | Value |
|---|---|
| `$url` | Full autoupdate URL without fragment (`#/dl.7z`) |
| `$baseurl` | URL without filename and fragment |
| `$basename` | Filename from URL (ignores fragment) |

### Hash Variables (in `autoupdate.hash.find`)

| Variable | Regex it expands to |
|---|---|
| `$md5` | `([a-fA-F0-9]{32})` |
| `$sha1` | `([a-fA-F0-9]{40})` |
| `$sha256` | `([a-fA-F0-9]{64})` |
| `$sha512` | `([a-fA-F0-9]{128})` |
| `$checksum` | `([a-fA-F0-9]{32,128})` |
| `$base64` | `([a-zA-Z0-9+\/=]{24,88})` |

---

## Pre/Post Install Scripts

### Available Variables

| Variable | Example | Notes |
|---|---|---|
| `$app` | `feishu` | Manifest filename (no extension) |
| `$architecture` | `64bit` or `32bit` | |
| `$cmd` | `install`, `update`, `uninstall` | Current subcommand |
| `$version` | `1.2.3` | Version being installed |
| `$dir` | `~\scoop\apps\$app\current` | In `post_install`. In others: versioned path. |
| `$persist_dir` | `~\scoop\persist\$app` | Persistent data directory |
| `$manifest` | PS object | Deserialized manifest |
| `$global` | `$true`/`$false` | Whether it's a global install |
| `$scoopdir` | `~\scoop` | Scoop root |

### Execution Order

1. `pre_install`
2. Download + extract
3. `installer` (if defined)
4. `post_install` — `$dir` here is the `current` junction (not version path)
5. On update: `pre_uninstall` → old uninstall → `post_uninstall` → then install sequence above

### Helper Function: `appdir`

Check if another app is installed:

```json
"post_install": [
    "if (Test-Path \"$(appdir git)\\current\\git.exe\") { Write-Host 'Git found' }"
]
```

### Registry scripts

Place in `scripts/<app-name>/` in the bucket root. Reference from `post_install`/`pre_uninstall` scripts. Good for file associations and Open With entries.

> **Warning**: For file associations, always use the `current` junction path (`~\scoop\apps\app\current\app.exe`), never the shim path or a versioned path — shims break Open With, versioned paths break on update.

---

## Persistent Data

Files and directories listed in `persist` survive `scoop update` and are linked via directory junctions / hard links from `~\scoop\persist\<app>\`.

### Basic usage

```json
"persist": "config"
```

```json
"persist": [
    "data",
    "config.ini"
]
```

### Rename in persist dir

```json
"persist": [
    ["original_name", "name_in_persist_dir"]
]
```

### In scripts

Use `$persist_dir` to reference the persist directory:

```json
"env_set": {
    "MY_CONFIG": "$persist_dir\\config"
}
```

### Uninstall behavior

`scoop uninstall <app>` keeps persist data by default.
`scoop uninstall -p <app>` purges it.

---

## Maintenance Workflow

### Checking versions

```powershell
# Check a single app
.\bin\checkver.ps1 feishu

# Check all apps
.\bin\checkver.ps1 *

# Check apps in a non-standard directory
.\bin\checkver.ps1 myapp ..\TODO
```

### Updating manifests

```powershell
# Update a single app (writes new version/url/hash to JSON)
.\bin\checkver.ps1 feishu -u

# Force-update even if already on latest (useful for testing autoupdate)
.\bin\checkver.ps1 feishu -f

# Update to a specific version
.\bin\checkver.ps1 feishu -v 7.60.0 -u

# Update all outdated apps
.\bin\checkver.ps1 * -u

# List only outdated apps (no update)
.\bin\checkver.ps1 * -s
```

### Verifying hashes

```powershell
# Verify hashes for all manifests
.\bin\checkhashes.ps1

# Verify a single manifest
.\bin\checkhashes.ps1 feishu
```

### Formatting JSON

```powershell
# Format all manifests consistently
.\bin\formatjson.ps1

# Format a single manifest
.\bin\formatjson.ps1 feishu
```

### Running tests

```powershell
# Requires Scoop installed; runs Pester tests
.\Scoop-Bucket.Tests.ps1
```

### Full update-and-commit cycle

```powershell
.\bin\checkver.ps1 * -u            # update all manifests
.\bin\checkhashes.ps1              # verify hashes
scoop install bucket\feishu.json   # test install the updated app
git add bucket\feishu.json
git commit -m "feishu: Update to version X.Y.Z"
git push
```

### Auto-PR (creates PRs for outdated manifests)

```powershell
.\bin\auto-pr.ps1
# Default upstream: Maoyeedy/Scoop-Yeedy:main
.\bin\auto-pr.ps1 -Upstream "user/repo:branch"
```

### Enabling debug output for checkver

```powershell
scoop config debug $true
.\bin\checkver.ps1 feishu -u
```

### Excavator (automated)

Runs every 4 hours via `.github/workflows/excavator.yml`. It calls `checkver * -u` on all manifests that have both `checkver` and `autoupdate` defined. No manual action needed for maintained manifests.

---

## Testing Autoupdate

When writing a new `autoupdate` block, test it end-to-end:

1. Temporarily set `version` to a lower/older value in the manifest
2. Run `checkver.ps1 <app> -u` — it should update the version, URL, and hash
3. Inspect the resulting JSON: check `url`, `hash`, `extract_dir`
4. Install directly from local manifest to verify:
   ```powershell
   scoop install bucket\myapp.json
   ```
5. Restore correct version if the test broke something

Or use `-f` (force) to re-apply autoupdate without changing version:

```powershell
.\bin\checkver.ps1 myapp -f
```

---

## Tricks and Edge Cases

### Extracting installers as archives (bypassing UAC)

```json
"url": "https://example.com/installer.exe#/dl.7z"
```

Scoop saves the `.exe` but extracts it with 7-Zip. The `#/dl.7z` fragment is the trigger.

### Multi-file downloads

```json
"url": [
    "https://example.com/app.zip",
    "https://example.com/extras.zip"
],
"hash": [
    "sha256:abc123...",
    "sha256:def456..."
]
```

Hashes must be in the same order as URLs.

### Arch-specific persist / env / bin

All manifest properties can be placed inside `architecture.64bit` / `architecture.32bit` — they override the top-level equivalents for that arch.

### `suggest` vs `depends`

- `depends`: hard dependency, auto-installed silently. For runtime requirements.
- `suggest`: soft recommendation, shown as a message. For optional features. Suppressed if any listed app is already installed.

### innosetup flag

If a `.exe` is an InnoSetup installer, set `"innosetup": true`. Scoop uses `/VERYSILENT /SUPPRESSMSGBOXES` automatically.

### `installer.keep: "true"`

Keeps the downloaded installer file after running (useful when the uninstaller needs it):

```json
"installer": {
    "file": "setup.exe",
    "args": ["/S"],
    "keep": "true"
}
```

### PowerShell module manifests

```json
"psmodule": {
    "name": "ModuleName"
}
```

The `name` must match the `.psd1` filename. Module lands in `~\scoop\modules\ModuleName` (a junction).

### Shortcut subdirectory

```json
"shortcuts": [
    ["app.exe", "MyApps\\App Name"]
]
```

Creates `Start Menu > MyApps > App Name`.

### Shortcut with custom icon

```json
"shortcuts": [
    ["app.exe", "My App", "", "icon.ico"]
]
```

Third arg is start parameters (use `""` to skip), fourth is icon path relative to install dir.

### `$dir` path difference in post_install

In `post_install` specifically, `$dir` resolves to the `current` junction (`~\scoop\apps\app\current`), not the versioned directory. In all other script fields it resolves to the versioned path (`~\scoop\apps\app\1.2.3`).

### `scoop config debug $true`

Enables verbose output from `checkver.ps1`, showing exactly what URL is fetched, what regex is matched, and what variables are produced. Essential for debugging new `checkver`/`autoupdate` blocks.
