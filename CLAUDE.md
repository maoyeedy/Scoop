# CLAUDE.md

A [Scoop](https://scoop.sh/) bucket — JSON app manifests for the Windows package manager.

**Context7 library ID: `/scoopinstaller/scoop`** — use this with the Context7 MCP for any Scoop-specific syntax, schema fields, or scripting APIs not covered below.

---

## Repo Structure

```
bucket/          # Active manifests (one JSON per app)
deprecated/      # Removed manifests — historical reference only, do not install
  scripts/       # checkver helpers of the deprecated Unity manifests
bin/             # BucketTemplate copies: wrappers around $SCOOP_HOME/bin/. Never add files here
tools/           # This bucket's own maintenance scripts (see "tools/ Scripts")
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
| `/scoop-audit` | Audit bucket health — wraps `tools/audit.ps1` |
| `/scoop-add` | Add a new manifest to `bucket/` |
| `/scoop-bucket-sync` | Check/sync workflows and `bin/` against ScoopInstaller/BucketTemplate |

---

## Key Rules

**Shell:** Use `pwsh -NoProfile` for Scoop scripts, never `powershell`: a `powershell` started from this session inherits pwsh's `PSModulePath`, PS7's `Microsoft.PowerShell.Utility` shadows the 5.1 one, and `Get-FileHash` disappears. 5.1 itself is fine (CI's 5.1 leg is unaffected). Use `git -C <repo-root>` instead of `cd` for git commands.

**Manifest scripts must run on 5.1:** tooling runs in pwsh (Excavator does too), but `pre_install`/`installer`/`post_install`/`uninstaller` run in the user's shell, which is 5.1 when pwsh is absent. No PS7-only syntax (`??`, `?:`, `&&`, `||`, `-Parallel`). To test under 5.1 from here: `env -u PSModulePath powershell -NoProfile`.

**`file:line` refs** below and in `.claude/skills/` point at Scoop core master `e6aa3b36` (2026-09-30). Re-check them before relying on them after a Scoop update.

**Line endings:** CRLF everywhere (`.gitattributes` sets `eol=crlf`). Overrides the global LF rule.

**Hashes for new manifests:** Do NOT use `checkhashes.ps1` to fill a hash you do not have. It cannot write one: with a top-level `"hash": ""` (or the key missing) `-Update` falls through to the `architecture` branch, errors on `Get-Member` (Scoop core `checkhashes.ps1:163`) and then on null method calls (`:170-178`), and leaves `hash` as it was, so nothing is fixed. `URLS and hashes count mismatch` (`:91`) is a different case — `url` and `hash` arrays of unequal length. A wrong non-empty hash is rewritten correctly. Seed new hashes with `tools/hashurl.ps1 <url>`.

**`$version` substitution:** Only works in `autoupdate` URLs. Static `url` fields require literal version strings.

**`checkver: "github"` requires a GitHub homepage:** When `checkver` is `"github"`, `homepage` must be `https://github.com/owner/repo` — checkver reads the repo URL from it. A custom project page causes "expects the homepage to be a github repository" errors.

**`checkver.script` requires a working URL:** Even when using `script`, `checkver.url` (or `homepage` as fallback) must resolve successfully — the script never runs if the URL download fails. Set `checkver.url` to a known-working URL like the download URL itself.

**GitHub release asset renames break autoupdate.url:** When a project renames their release asset, `checkver: "github"` still detects the new version, but `autoupdate.url` will 404. Manually update the asset name pattern.

**`.zip` to `.exe` migration:** When a portable release changes from `.zip` archive to standalone `.exe`, update the URL directly and use `#/appname.exe` fragment to rename. No `extract_dir` needed.

**Hash extraction from GitHub API:** Use `autoupdate.hash` with `mode: json` and `jp` expression to extract `.digest` field (format `sha256:hex` — prefix auto-stripped). Avoids downloading the asset just for hashing.

**`autoupdate.hash` needs a URL to hash:** `mode: "download"` hashes whatever `autoupdate.url` resolves to. With no `autoupdate.url`, Scoop substitutes `$null`, downloads nothing, writes `"hash": ""`, and still exits 0. When hashing by download, always set a version-less `autoupdate.url` (it may be identical to the static `url`).

**Never commit `"hash": ""`:** Scoop's `Update-ManifestProperty` only refreshes a top-level hash when it is already non-empty; an empty one is never auto-filled by Excavator, and install only warns and proceeds unverified (`lib/download.ps1:730`). Seed a real hash when creating the manifest. `tools/lint.ps1` (and the schema test in `bin/test.ps1`) fails on it. CI only validates manifests changed in the pushed commit, and Excavator's `GITHUB_TOKEN` pushes do not trigger CI, so lint locally.

**`hash` only covers `url`:** files fetched inside `pre_install` are never verified, and a vendor API/landing page that rotates tokens cannot be hashed. If the real artifact has a stable public URL, point `url` at it and let Scoop hash that (see `uu.json`).

**`checkver <app> -u -f` can pass without computing anything:** if the hash is already correct, it rewrites the same value. `tools/provehash.ps1 <app>` does the real proof on a temp copy: hash set to 64 zeros, empty `SCOOP_CACHE`, `-u -f`, result compared to the committed hash. Zeros, not `""`: autoupdate only takes the global-hash branch when `$Manifest.hash` is truthy; otherwise it walks `architecture`, and on a manifest without one `Get-Member` on `$null` errors while the manifest is still written with the empty hash (`lib/autoupdate.ps1:383-399`).

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
| `.\Scoop-Bucket.Tests.ps1` | Run Pester tests (needs Pester 5.2+ and BuildHelpers); for one manifest's schema, `tools/lint.ps1 <app>` is faster |

Debug: `scoop config debug $true` before running checkver to see verbose fetch/regex output.

Excavator runs `checkver * -u` with `SKIP_UPDATED=1`, so a current manifest's autoupdate/hash path is never exercised until upstream bumps. `tools/provehash.ps1` is the pre-release proof; a CI probe needs a `workflow_dispatch` workflow that exists on the default branch, dispatched with `--ref`.

## Quick Reference: `tools/` Scripts

This bucket's own scripts, not from the template. All take `[<app>] [-Dir <bucket>]`, default `*` and `bucket/`, emit objects, and exit 1 on an error. pwsh only.

| Command | Purpose | Cost |
|---|---|---|
| `.\tools\audit.ps1 [-Offline]` | Every check below plus `checkver -s` and `checkhashes`, one table with the fix per row | minutes; `-Offline` seconds |
| `.\tools\lint.ps1` | Schema + the Key Rules: empty/missing hash, `$version` in static url, missing `autoupdate.url`, github homepage, regex groups, undefined `$matchXxx`, no checkver without `##`, PS7-only syntax and downloads in install scripts | <1 s, offline |
| `.\tools\checkautoupdate.ps1` | `autoupdate.url` filled with the committed version must equal the static `url` (catches asset renames before the next release) | <1 s, offline |
| `.\tools\checksources.ps1` | Every `checkver.url` (or homepage) and `autoupdate.hash.url` answers 2xx; `bin/checkurls.ps1` covers download urls | ~10 s |
| `.\tools\provehash.ps1` | Autoupdate recomputes each hash from zeros on a temp copy; `moved` means upstream released, run `checkver -u` first | downloads artifacts |
| `.\tools\hashurl.ps1 <url>` | SHA256 of a url (fragment stripped), for seeding a new manifest | one download |

## Maintenance Commands

| Command | Purpose |
|---|---|
| `.\bin\checkurls.ps1 <app>` | Verify manifest URLs |
| `.\bin\missing-checkver.ps1` | List manifests missing `checkver` or `autoupdate`. Expected: `otf-SF-Mono`, `window-centering-helper` (reason in each manifest's `##`) |
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
