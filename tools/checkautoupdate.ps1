<#
.SYNOPSIS
    Offline check that autoupdate.url, filled with the committed version, reproduces the static url.
.DESCRIPTION
    A mismatch means the next upstream release will be written with a wrong url (asset renamed,
    path changed, typo in a $match variable). $matchXxx values come from running checkver.regex
    against the static url; if it does not match, the manifest is reported as skip.
    Exits 1 on any mismatch.
.EXAMPLE
    .\tools\checkautoupdate.ps1
    .\tools\checkautoupdate.ps1 uu
#>
#Requires -Version 7
param(
    [String] $App = '*',
    [String] $Dir
)
. "$PSScriptRoot\common.ps1"
if (!$Dir) { $Dir = $BucketDir }

$manifests = @(Get-BucketManifest $App $Dir | Where-Object { $_.Json.autoupdate })
$results = foreach ($m in $manifests) {
    $subs = Get-AutoupdateSubstitution $m.Json
    # An unresolved variable is only excusable when the regex gave no $match values to use.
    $unresolved = if (@($subs.Keys | Where-Object { $_ -like '$match*' -and $_ -notin '$matchHead', '$matchTail' }).Count) { 'mismatch' } else { 'skip' }
    foreach ($slot in Get-UrlSlot $m.Json) {
        $where = if ($slot.Arch) { " [$($slot.Arch)]" } else { '' }
        for ($i = 0; $i -lt $slot.Url.Count; $i++) {
            $expected = if ($i -lt $slot.AutoUrl.Count) { substitute $slot.AutoUrl[$i] $subs }
            $status = if (!$expected) { 'mismatch' } elseif ($expected -match '\$[a-zA-Z]') { $unresolved } elseif ($expected -ne $slot.Url[$i]) { 'mismatch' }
            if ($status) {
                [PSCustomObject]@{ App = $m.Name; Status = $status; Detail = "url$where`: $($slot.Url[$i]) <- autoupdate: $expected" }
            }
        }
    }
}

$results
Write-Host "checkautoupdate: $($manifests.Count) manifests with autoupdate, $(@($results).Count) issues"
exit [int][bool]($results | Where-Object Status -EQ mismatch)
