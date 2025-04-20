# Common Unity LTS version checking
function Get-UnityLtsVersion {
    param (
        [string]$VersionPrefix
    )

    $ltsReleases = Invoke-RestMethod -Uri 'https://unity.com/releases/editor/lts-releases.xml'
    if ($null -eq $ltsReleases) { Write-Error "Failed to fetch or parse XML"; return $null }
    $allItems = @($ltsReleases)
    $latestRelease = $allItems | Where-Object { $_.link -match "whats-new/$VersionPrefix\.\d+\.\d+$" } | Select-Object -First 1
    if ($null -eq $latestRelease) { Write-Error "No $VersionPrefix.x.x releases found"; return $null }
    $versionMatch = $latestRelease.link -match "whats-new/($VersionPrefix\.\d+\.\d+)$"
    $version = if ($versionMatch) { $matches[1] + "f1" }
    $releasePageUrl = $latestRelease.link
    $releasePage = Invoke-WebRequest -Uri $releasePageUrl -UseBasicParsing
    if ($releasePage.Content -match 'unityhub://[^/]+/([a-zA-Z0-9]+)') {
        $buildHash = $matches[1]
        return "$version|$buildHash"
    } else {
        $releaseNotesLink = $latestRelease.releaseNotesLink
        if ($releaseNotesLink -match '(\d+\_\d+\_\d+f\d)_([a-zA-Z0-9]+)') {
            $versionFromNotes = $matches[1] -replace '_', '.'
            $hashFromNotes = $matches[2]
            return "$versionFromNotes|$hashFromNotes"
        } else {
            Write-Error 'Could not find build hash information'
            return $null
        }
    }
}
