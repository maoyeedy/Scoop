# Dot-sourced by tools/*.ps1: loads Scoop core and enumerates this bucket's manifests.
if (!$env:SCOOP_HOME) { $env:SCOOP_HOME = Convert-Path (scoop prefix scoop) }
. "$env:SCOOP_HOME\lib\core.ps1"
. "$env:SCOOP_HOME\lib\manifest.ps1"
. "$env:SCOOP_HOME\lib\autoupdate.ps1"

$BucketDir = Convert-Path "$PSScriptRoot\..\bucket"

function Get-BucketManifest([String] $App = '*', [String] $Dir = $BucketDir) {
    Get-ChildItem $Dir -Filter "$App.json" | ForEach-Object {
        $json = try { Get-Content $_.FullName -Raw | ConvertFrom-Json -ErrorAction Stop } catch { $null }
        [PSCustomObject]@{ Name = $_.BaseName; File = $_.FullName; Json = $json }
    }
}

# One slot per download: the top level, or each architecture. Url/Hash are arrays.
function Get-UrlSlot($Json) {
    # '' marks the top level; a lone $null would be skipped by foreach
    $arches = if ($Json.url) { '' } else { @($Json.architecture.PSObject.Properties.Name) }
    foreach ($arch in $arches) {
        $node = if ($arch) { $Json.architecture.$arch } else { $Json }
        $auto = if ($Json.autoupdate -and $arch) { arch_specific 'url' $Json.autoupdate $arch } else { $Json.autoupdate.url }
        [PSCustomObject]@{ Arch = $arch; Url = @($node.url); Hash = @($node.hash); AutoUrl = @($auto | Where-Object { $_ }) }
    }
}

# Run checkver.regex against $Text the way checkver does; $null when it does not match.
function Get-CheckverMatch($Json, [String] $Text) {
    $regex = if ($Json.checkver.re) { $Json.checkver.re } elseif ($Json.checkver.regex) { $Json.checkver.regex }
    if (!$regex) { return $null }
    $m = [Regex]::new($regex).Match($Text)
    if (!$m.Success) { return $null }
    $table = @{}
    $m.Groups | Where-Object { $_.Name -ne '0' } | ForEach-Object { $table[$_.Name] = $_.Value }
    $table
}

# Autoupdate variables for the committed version. $matchXxx values come from running
# checkver.regex against the static urls; when it matches none, they stay unsubstituted.
function Get-AutoupdateSubstitution($Json) {
    $custom = $null
    foreach ($u in (Get-UrlSlot $Json).Url) { if (!$custom) { $custom = Get-CheckverMatch $Json $u } }
    Get-VersionSubstitution $Json.version $custom
}
