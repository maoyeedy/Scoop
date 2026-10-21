<#
.SYNOPSIS
    Offline check of manifests against the schema and this bucket's known pitfalls.
.DESCRIPTION
    No network. Each rule is a Key Rule in CLAUDE.md. Exits 1 when any error is found;
    warnings alone exit 0.
.EXAMPLE
    .\tools\lint.ps1
    .\tools\lint.ps1 uu
#>
#Requires -Version 7
param(
    [String] $App = '*',
    [String] $Dir
)
. "$PSScriptRoot\common.ps1"
if (!$Dir) { $Dir = $BucketDir }

Add-Type -Path "$env:SCOOP_HOME\supporting\validator\bin\Scoop.Validator.dll"
$validator = New-Object Scoop.Validator("$env:SCOOP_HOME/schema.json", $true)

$userShellFields = 'pre_install', 'post_install', 'pre_uninstall', 'post_uninstall'
$ps7Syntax = '\?\?|&&|\|\||-Parallel\b|\?\.|[\w\)\]]\s+\?\s'
$downloadCall = 'Invoke-WebRequest|Invoke-RestMethod|DownloadFile|Start-BitsTransfer|\bcurl\b|\bwget\b|\biwr\b|\birm\b'

# Lines of script that run in the user's shell, top level and per architecture.
function Get-UserShellScript($Json) {
    foreach ($node in @($Json) + @($Json.architecture.PSObject.Properties.Value)) {
        if (!$node) { continue }
        foreach ($field in $userShellFields) { $node.$field }
        $node.installer.script
        $node.uninstaller.script
    }
}

$results = foreach ($m in Get-BucketManifest $App $Dir) {
    $json = $m.Json
    $issue = { param($level, $rule, $detail) [PSCustomObject]@{ App = $m.Name; Level = $level; Rule = $rule; Detail = $detail } }
    if (!$json) { & $issue error invalid-json 'does not parse as JSON'; continue }

    if (!$validator.Validate($m.File)) {
        # The validator nests anyOf branches; the last message is the most specific one.
        $text = $validator.Errors -join "`n"
        $last = [Regex]::Matches($text, 'Error: ([^\r\n]+)') | Select-Object -Last 1
        & $issue error schema "$($last.Groups[1].Value) (line $([Regex]::Match($text, '\.json:(\d+):').Groups[1].Value))"
    }

    foreach ($slot in Get-UrlSlot $json) {
        $where = if ($slot.Arch) { "architecture.$($slot.Arch)" } else { 'top level' }
        if ($slot.Hash.Count -lt $slot.Url.Count -or @($slot.Hash | Where-Object { !$_ }).Count) {
            & $issue error hash-missing "$where`: a url has no hash; install proceeds unverified and Excavator never fills it"
        }
        if ($slot.Url -match '\$(version|match)') {
            & $issue error static-var "$where`: `$version/`$match in a static url is never substituted"
        }
        if ($json.autoupdate -and !$slot.AutoUrl.Count) {
            & $issue error autoupdate-url-missing "$where`: autoupdate has no url; url stays stale and a download hash is written as `"`""
        }
    }

    if (!$json.checkver) {
        if (!$json.'##') { & $issue error no-checkver 'no checkver and no "##" reason' }
    } else {
        if ($json.checkver -eq 'github' -and $json.homepage -notmatch '^https://github\.com/[^/]+/[^/]+/?$') {
            & $issue error github-homepage "checkver 'github' needs homepage https://github.com/owner/repo, got $($json.homepage)"
        }
        if ($json.checkver.script -and !$json.checkver.url) {
            & $issue warn script-no-url 'checkver.script without checkver.url: the script only runs if the homepage downloads'
        }
        $regex = if ($json.checkver.re) { $json.checkver.re } elseif ($json.checkver.regex) { $json.checkver.regex }
        if ($regex) {
            $names = [Regex]::new($regex).GetGroupNames() | Where-Object { $_ -ne '0' }
            $unnamed = @($names | Where-Object { $_ -match '^\d+$' })
            $named = @($names | Where-Object { $_ -notmatch '^\d+$' })
            if (!$json.checkver.replace) {
                if (!$unnamed.Count -and $named -notcontains 'version') {
                    & $issue error regex-version 'no unnamed group and no (?<version>...): checkver finds no version'
                } elseif ($unnamed.Count -gt 1) {
                    & $issue warn regex-version "$($unnamed.Count) unnamed groups: only group 1 becomes the version"
                }
            }
            $named | Where-Object { $_ -cnotmatch '^[a-z]+$' } | ForEach-Object {
                & $issue warn group-name "(?<$_>) becomes `$match$((Get-Culture).TextInfo.ToTitleCase($_)); use one lowercase word"
            }
            if ($json.autoupdate) {
                $defined = @('Head', 'Tail') + ($names | ForEach-Object { (Get-Culture).TextInfo.ToTitleCase($_) })
                $used = [Regex]::Matches(($json.autoupdate | ConvertTo-Json -Depth 10 -Compress), '\$match(\w+)') | ForEach-Object { $_.Groups[1].Value }
                $used | Select-Object -Unique | Where-Object { $defined -cnotcontains $_ } | ForEach-Object {
                    & $issue error match-undefined "autoupdate uses `$match$_, which checkver.regex does not define"
                }
            }
        }
    }

    foreach ($line in Get-UserShellScript $json) {
        if ($line -match $ps7Syntax) {
            & $issue error ps7-syntax "runs in the user's shell (maybe 5.1): $($line.Trim())"
        }
        if ($line -match $downloadCall) {
            & $issue warn unhashed-download "downloads outside url, so hash does not cover it: $($line.Trim())"
        }
    }
}

$results
Write-Host "lint: $(@(Get-BucketManifest $App $Dir).Count) manifests, $(@($results).Count) issues"
exit [int][bool]($results | Where-Object Level -EQ error)
