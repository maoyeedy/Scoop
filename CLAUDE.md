# CLAUDE.md

A [Scoop](https://scoop.sh/) bucket — JSON app manifests for the Windows package manager.

**Context7 library ID: `/scoopinstaller/scoop`** — use this with the Context7 MCP for any Scoop-specific syntax, schema fields, or scripting APIs not covered below.

---

## Repo Structure

```
bucket/          # Active manifests (one JSON per app)
deprecated/      # Removed manifests — historical reference only, do not install
bin/             # PowerShell wrappers delegating to $SCOOP_HOME/bin/
docs/            # Reference documentation
  scoop-manifest-reference.md   # Full schema, all checkver/autoupdate strategies, all variables
.github/
  workflows/
    excavator.yml  # Runs checkver * -u every 4 hours; opens PRs for updates
.claude/
  skills/
    scoop-check/           # /scoop-check  — health check: outdated + hash mismatches
    scoop-create-bucket/   # /scoop-create-bucket — create new manifests safely
```

---

## Skills

Use these instead of manual steps:

| Skill | When to use |
|---|---|
| `/scoop-check` | Audit bucket health — outdated manifests, hash mismatches |
| `/scoop-create-bucket` | Add a new manifest to `bucket/` |

---

## Key Rules

**Shell:** Always `pwsh -NoProfile`, never `powershell`. Always `git -C "C:/Users/jerkl/scoop/buckets/maoyeedy_scoop" <cmd>` — never `cd`.

**Line endings:** CRLF everywhere (`.gitattributes` sets `eol=crlf`). Overrides the global LF rule.

**Hashes for new manifests:** Do NOT use `checkhashes.ps1` — it breaks with missing hashes. Download files manually and use `Get-FileHash`.

**`$version` substitution:** Only works in `autoupdate` URLs. Static `url` fields require literal version strings.

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
| `.\bin\checkhashes.ps1 <app>` | Verify hashes (existing manifests only) |
| `.\bin\formatjson.ps1 <app>` | Normalize JSON formatting |
| `.\Scoop-Bucket.Tests.ps1` | Run Pester tests |

Debug: `scoop config debug $true` before running checkver to see verbose fetch/regex output.

---

## Manifest Patterns in This Bucket

For the full schema and all options, see [`docs/scoop-manifest-reference.md`](docs/scoop-manifest-reference.md).

| Pattern | Examples | Notes |
|---|---|---|
| GitHub release | `fetch.json`, `toasty.json`, `spicetify.json` | `"checkver": "github"` |
| CDN + named captures | `feishu.json`, `uu.json`, `leigod.json` | `$matchXxx` in autoupdate for non-version tokens |
| Mirror/derived URL | `blender-aliyun.json` | Version from official source, download from mirror |
