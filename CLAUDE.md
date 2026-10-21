# CLAUDE.md

A [Scoop](https://scoop.sh/) bucket — JSON app manifests for the Windows package manager.

**Context7 library ID: `/scoopinstaller/scoop`** — use this with the Context7 MCP for any Scoop-specific syntax, schema fields, or scripting APIs not covered below.

---

## Repo Structure

```
bucket/          # Active manifests (one JSON per app)
deprecated/      # Removed manifests — historical reference only, do not install
bin/             # Thin wrappers around $SCOOP_HOME/bin/ (auto-pr.ps1, test.ps1 differ)
docs/            # Reference documentation
  scoop-manifest-reference.md   # Full schema, all checkver/autoupdate strategies, all variables
.github/
  workflows/
    excavator.yml  # Every 4 hours: scheduled auto-pr (checkver, skip-current) pushes to master
.claude/
  skills/
    scoop-audit/       # /scoop-audit — health audit: outdated + hash mismatches
    scoop-add/         # /scoop-add   — create new manifests safely
    scoop-bucket-sync/ # workflows/bin vs ScoopInstaller/BucketTemplate (has scripts/)
```

---

## Skills

Use these instead of manual steps:

| Skill | When to use |
|---|---|
| `/scoop-audit` | Audit bucket health — outdated manifests, hash mismatches |
| `/scoop-add` | Add a new manifest to `bucket/` |
| `/scoop-bucket-sync` | Check/sync workflows and `bin/` against ScoopInstaller/BucketTemplate |

---

## Key Rules

**Shell:** Use `pwsh -NoProfile` for Scoop scripts, never `powershell`. Use `git -C <repo-root>` instead of `cd` for git commands.

**Line endings:** CRLF everywhere (`.gitattributes` sets `eol=crlf`). Overrides the global LF rule.

**Hashes for new manifests:** Do NOT use `checkhashes.ps1` to fill a hash you do not have. It cannot write one: with a top-level `"hash": ""` (or the key missing) `-Update` falls through to the `architecture` branch and dies on a null method call (Scoop core `checkhashes.ps1:178`) and leaves `hash` as it was, so nothing is fixed. `URLS and hashes count mismatch` (`:91`) is a different case — `url` and `hash` arrays of unequal length. A wrong non-empty hash is rewritten correctly. Download files manually and use `Get-FileHash`.

**`$version` substitution:** Only works in `autoupdate` URLs. Static `url` fields require literal version strings.

**`checkver: "github"` requires a GitHub homepage:** When `checkver` is `"github"`, `homepage` must be `https://github.com/owner/repo` — checkver reads the repo URL from it. A custom project page causes "expects the homepage to be a github repository" errors.

**`checkver.script` requires a working URL:** Even when using `script`, `checkver.url` (or `homepage` as fallback) must resolve successfully — the script never runs if the URL download fails. Set `checkver.url` to a known-working URL like the download URL itself.

**GitHub release asset renames break autoupdate.url:** When a project renames their release asset, `checkver: "github"` still detects the new version, but `autoupdate.url` will 404. Manually update the asset name pattern.

**`.zip` to `.exe` migration:** When a portable release changes from `.zip` archive to standalone `.exe`, update the URL directly and use `#/appname.exe` fragment to rename. No `extract_dir` needed.

**Hash extraction from GitHub API:** Use `autoupdate.hash` with `mode: json` and `jp` expression to extract `.digest` field (format `sha256:hex` — prefix auto-stripped). Avoids downloading the asset just for hashing.

**`autoupdate.hash` needs a URL to hash:** `mode: "download"` hashes whatever `autoupdate.url` resolves to. With no `autoupdate.url`, Scoop substitutes `$null`, downloads nothing, writes `"hash": ""`, and still exits 0. When hashing by download, always set a version-less `autoupdate.url` (it may be identical to the static `url`).

**Never commit `"hash": ""`:** Scoop's `Update-ManifestProperty` only refreshes a top-level hash when it is already non-empty; an empty one is never auto-filled by Excavator. Seed a real hash when creating the manifest.

**`hash` only covers `url`:** files fetched inside `pre_install` are never verified, and a vendor API/landing page that rotates tokens cannot be hashed. If the real artifact has a stable public URL, point `url` at it and let Scoop hash that (see `uu.json`).

**`checkver <app> -u -f` can pass without computing anything:** if the hash is already correct, it rewrites the same value. To prove the hash path works, zero the hash, point `SCOOP_CACHE` at an empty temp dir, run `-u -f`, and expect a `Downloading ...` + `Computed hash:` line.

**Version is capture group 1, or a group named `version`:** checkver takes group `1` first and only falls back to a `version`-named group when group 1 is empty. `(?<build>\\d+)/UU-([\\d.]+)\\.exe` works because the version is the only unnamed group. If another token is unnamed while the version is named, that token becomes the version. Keep the version as the only unnamed group, or name it `version` and leave no unnamed groups.

**Artifact behind a signed/rotating link:** pages that hand out `?key1=...` links change per request and cannot be hashed. Check whether the tokens are cosmetic (fetch keyless, then with bogus keys, and compare `ETag`/`x-goog-generation`); if the object is public, point `url` at it and keep `checkver` on the official page (see `uu.json`).

**Commit messages:**
- New manifest: `Add <appname>`
- Update: `<appname>: Update to version X.Y.Z`

---

## Quick Reference: `bin/` Scripts

All scripts run from repo root via `pwsh -NoProfile -Command "..."`.

| Command | Purpose |
|---|---|
| `.\bin\checkver.ps1 <app>` | Check version |
| `.\bin\checkver.ps1 <app> -u` | Detect + write new version/url/hash |
| `.\bin\checkver.ps1 <app> -f` | Force autoupdate re-apply (testing) |
| `.\bin\checkver.ps1 * -s` | List outdated apps only |
| `.\bin\checkhashes.ps1 <app>` | Verify hashes (downloads every URL) |
| `.\bin\checkhashes.ps1 <app> -Update` | Rewrite mismatched hashes in place |
| `.\bin\formatjson.ps1 <app>` | Normalize JSON formatting (4-space indent, CRLF) |
| `.\Scoop-Bucket.Tests.ps1` | Run Pester tests (needs Pester 5.2+ and BuildHelpers) |

Debug: `scoop config debug $true` before running checkver to see verbose fetch/regex output.

Excavator runs `checkver * -u` with `SKIP_UPDATED=1`, so a current manifest's autoupdate/hash path is never exercised until upstream bumps. `-f` locally is the only pre-release proof; a CI probe needs a `workflow_dispatch` workflow that exists on the default branch, dispatched with `--ref`.

## Maintenance Commands

| Command | Purpose |
|---|---|
| `.\bin\checkurls.ps1 <app>` | Verify manifest URLs |
| `.\bin\missing-checkver.ps1` | List manifests missing `checkver` or `autoupdate` |
| `.\bin\auto-pr.ps1` | Commit/push bucket changes via `-Push` (or open a PR with `-Request`) |
| `.\bin\test.ps1` | Run the Pester suite in the invoking shell; `ci.yml` runs the powershell/pwsh matrix |

---

## Manifest Patterns in This Bucket

For the full schema and all options, see [`docs/scoop-manifest-reference.md`](docs/scoop-manifest-reference.md).

| Pattern | Examples | Notes |
|---|---|---|
| GitHub release | `fetch.json`, `toasty.json`, `spicetify.json` | `fetch.json` is plain `"checkver": "github"`; `spicetify.json` needs the `{"github": "<url>"}` form (homepage is not the repo); `toasty.json` uses `checkver.script` |
| CDN + named captures | `feishu.json`, `uu.json`, `leigod.json` | `$matchXxx` in autoupdate for non-version tokens |
| Mirror/derived URL | `blender-aliyun.json` | Version from official source, download from mirror |
