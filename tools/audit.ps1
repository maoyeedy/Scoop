<#
.SYNOPSIS
    One-shot bucket health report: every check, one table of problems with the fix to apply.
.DESCRIPTION
    Runs checkver -s (outdated), checkhashes -SkipCorrect (mismatches; downloads every url),
    tools/lint, tools/checkautoupdate and tools/checksources. -Offline runs only lint and
    checkautoupdate (seconds, no network). Prints nothing per app that passes.
    Exits 1 when any row is an error.
.EXAMPLE
    .\tools\audit.ps1
    .\tools\audit.ps1 -Offline
#>
#Requires -Version 7
param(
    [String] $App = '*',
    [String] $Dir,
    [Switch] $Offline
)
. "$PSScriptRoot\common.ps1"
if (!$Dir) { $Dir = $BucketDir }

function Row($app, $check, $level, $detail, $fix) {
    [PSCustomObject]@{ App = $app; Check = $check; Level = $level; Detail = $detail; Fix = $fix }
}

# Scoop scripts report per app as "<app>: <message>" through Write-Host.
function Invoke-ScoopScript([String] $Script, [String[]] $Arguments) {
    pwsh -NoProfile -File "$env:SCOOP_HOME\bin\$Script" -App $App -Dir $Dir @Arguments *>&1 | ForEach-Object {
        if ("$_" -replace '\e\[[\d;]*m' -match '^([\w.+-]+): (.+)$') { [PSCustomObject]@{ App = $Matches[1]; Message = $Matches[2].Trim() } }
    }
}

$rows = @(
    if (!$Offline) {
        Invoke-ScoopScript checkver.ps1 '-SkipUpdated' | ForEach-Object {
            if ($_.Message -match '^(\S+) \(scoop version is (\S+)\)') {
                Row $_.App outdated error "$($Matches[2]) -> $($Matches[1])" "bin/checkver.ps1 $($_.App) -u"
            } else {
                Row $_.App checkver error $_.Message 'investigate the checkver source (tools/checksources.ps1)'
            }
        }
        Invoke-ScoopScript checkhashes.ps1 '-SkipCorrect' | ForEach-Object {
            Row $_.App hash error $_.Message "bin/checkhashes.ps1 $($_.App) -Update; an empty hash: tools/hashurl.ps1"
        }
    }
    & "$PSScriptRoot\lint.ps1" -App $App -Dir $Dir 6>$null | ForEach-Object {
        Row $_.App "lint:$($_.Rule)" $_.Level $_.Detail 'edit the manifest (CLAUDE.md Key Rules)'
    }
    & "$PSScriptRoot\checkautoupdate.ps1" -App $App -Dir $Dir 6>$null | ForEach-Object {
        $level = if ($_.Status -eq 'mismatch') { 'error' } else { 'warn' }
        Row $_.App "autoupdate:$($_.Status)" $level $_.Detail 'align autoupdate.url with the static url'
    }
    if (!$Offline) {
        & "$PSScriptRoot\checksources.ps1" -App $App -Dir $Dir 6>$null | ForEach-Object {
            Row $_.App "source:$($_.Kind)" error "$($_.Status) $($_.Url)" 'find the new source url'
        }
    }
)

if ($rows) { $rows | Sort-Object App, Check | Format-Table -AutoSize -Wrap } else { Write-Host 'audit: no problems found' }
exit [int][bool]($rows | Where-Object Level -EQ error)
