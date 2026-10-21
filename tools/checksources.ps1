<#
.SYNOPSIS
    Request every version source (checkver.url, or homepage when checkver reads it) and every
    autoupdate.hash.url, and report the ones that do not answer 2xx.
.DESCRIPTION
    Complements bin/checkurls.ps1, which only checks the static download urls. Uses Scoop's
    user agent, so a block here is a block for checkver too. HEAD first, GET when HEAD is
    refused. GitHub checkver is skipped (API, rate-limited). Exits 1 on any failure.
.EXAMPLE
    .\tools\checksources.ps1
#>
#Requires -Version 7
param(
    [String] $App = '*',
    [String] $Dir
)
. "$PSScriptRoot\common.ps1"
. "$env:SCOOP_HOME\lib\download.ps1"
if (!$Dir) { $Dir = $BucketDir }

function Get-Source($Json) {
    $cv = $Json.checkver
    if ($cv -and $cv -ne 'github' -and !$cv.github) {
        [PSCustomObject]@{ Kind = 'checkver'; Url = if ($cv.url) { $cv.url } else { $Json.homepage } }
    }
    $subs = Get-AutoupdateSubstitution $Json
    foreach ($slot in Get-UrlSlot $Json) {
        $hash = if ($slot.Arch) { arch_specific 'hash' $Json.autoupdate $slot.Arch } else { $Json.autoupdate.hash }
        if (!$hash.url) { continue }
        # The same url variables Scoop adds in get_hash_for_app
        $origin = strip_fragment $slot.Url[0]
        $basename = [System.Web.HttpUtility]::UrlDecode((url_remote_filename $slot.Url[0]))
        $all = $subs.Clone()
        $all['$url'] = $origin
        $all['$baseurl'] = (strip_filename $origin).TrimEnd('/')
        $all['$basename'] = $basename
        $all['$urlNoExt'] = strip_ext $origin
        $all['$basenameNoExt'] = strip_ext $basename
        [PSCustomObject]@{ Kind = 'hash'; Url = substitute $hash.url $all }
    }
}

function Get-Status([String] $Url) {
    $request = @{ Uri = $Url; UserAgent = (Get-UserAgent); TimeoutSec = 30; SkipHttpErrorCheck = $true; MaximumRedirection = 5 }
    try {
        $status = (Invoke-WebRequest @request -Method Head).StatusCode
        if ($status -ge 400) { $status = (Invoke-WebRequest @request -Method Get).StatusCode }
        $status
    } catch {
        $_.Exception.Message
    }
}

$manifests = @(Get-BucketManifest $App $Dir)
$checked = 0
$results = foreach ($m in $manifests) {
    foreach ($source in Get-Source $m.Json | Sort-Object Url -Unique) {
        $checked++
        $status = Get-Status $source.Url
        if ($status -isnot [int] -or $status -ge 400) {
            [PSCustomObject]@{ App = $m.Name; Kind = $source.Kind; Status = $status; Url = $source.Url }
        }
    }
}

$results
Write-Host "checksources: $checked sources in $($manifests.Count) manifests, $(@($results).Count) failed"
exit [int][bool]$results
