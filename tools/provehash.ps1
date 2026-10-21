<#
.SYNOPSIS
    Prove that autoupdate recomputes each hash from scratch, without touching bucket/.
.DESCRIPTION
    Copies the manifests to a temp bucket, replaces every hash with 64 zeros, points
    SCOOP_CACHE at an empty dir, and runs checkver -u -f there. A hash that comes back equal
    to the committed one was really recomputed (zeros cannot pass). This is the path
    Excavator takes at the next upstream release, which SKIP_UPDATED hides until then.
    Downloads every artifact that hashes by download, so * is slow. Exits 1 on any failure.
.EXAMPLE
    .\tools\provehash.ps1 uu
    .\tools\provehash.ps1
#>
#Requires -Version 7
param(
    [String] $App = '*',
    [String] $Dir
)
. "$PSScriptRoot\common.ps1"
if (!$Dir) { $Dir = $BucketDir }

$zeros = '0' * 64
$work = Join-Path ([IO.Path]::GetTempPath()) "provehash-$(Get-Random)"
$copyDir = New-Item -ItemType Directory "$work\bucket"
$cacheDir = New-Item -ItemType Directory "$work\cache"
$log = "$work\checkver.log"

$manifests = @(Get-BucketManifest $App $Dir | Where-Object { $_.Json.autoupdate })
foreach ($m in $manifests) {
    $copy = $m.Json | ConvertTo-Json -Depth 20 | ConvertFrom-Json
    $nodes = if ($copy.url) { , $copy } else { @($copy.architecture.PSObject.Properties.Value) }
    foreach ($node in $nodes) { $node.hash = if ($node.hash -is [Array]) { @($node.hash | ForEach-Object { $zeros }) } else { $zeros } }
    $copy | ConvertTo-Json -Depth 20 | Set-Content "$copyDir\$($m.Name).json"
}

$env:SCOOP_CACHE, $savedCache = $cacheDir.FullName, $env:SCOOP_CACHE
pwsh -NoProfile -File "$env:SCOOP_HOME\bin\checkver.ps1" -App $App -Dir $copyDir -Update -ForceUpdate *> $log
$env:SCOOP_CACHE = $savedCache
Remove-Item $cacheDir -Recurse -Force

$hashes = { param($json) @(Get-UrlSlot $json | ForEach-Object { $_.Hash }) }
$results = foreach ($m in $manifests) {
    $after = Get-Content "$copyDir\$($m.Name).json" -Raw | ConvertFrom-Json
    $new = @(& $hashes $after)
    $status, $detail = if ($after.version -ne $m.Json.version) {
        'moved', "upstream is now $($after.version); run checkver -u, then prove again"
    } elseif ($new -contains $zeros) {
        'not-computed', "hash still zeros; see $log"
    } elseif (!$new.Count -or @($new | Where-Object { !$_ }).Count) {
        'not-computed', "hash written empty (no autoupdate.url to download?); see $log"
    } elseif (($new -join ',') -ne ((& $hashes $m.Json) -join ',')) {
        'differs', "recomputed $($new -join ',') <> committed (artifact changed behind the same url?)"
    } else {
        'ok', ''
    }
    [PSCustomObject]@{ App = $m.Name; Status = $status; Detail = $detail }
}

$results
Write-Host "provehash: $($manifests.Count) manifests, log $log"
exit [int][bool]($results | Where-Object Status -In 'not-computed', 'differs')
