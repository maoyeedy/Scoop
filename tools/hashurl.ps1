<#
.SYNOPSIS
    Download a url and print its lowercase SHA256, for seeding the hash of a new manifest.
.DESCRIPTION
    Strips any #/fragment (a Scoop directive, not part of the http url) and uses Scoop's
    user agent. The download goes to a fresh temp dir that is removed afterwards.
.EXAMPLE
    .\tools\hashurl.ps1 'https://example.com/app-1.2.3.exe#/app.exe'
#>
#Requires -Version 7
param(
    [Parameter(Mandatory)] [String[]] $Url
)
. "$PSScriptRoot\common.ps1"
. "$env:SCOOP_HOME\lib\download.ps1"

$work = New-Item -ItemType Directory (Join-Path ([IO.Path]::GetTempPath()) "hashurl-$(Get-Random)")
try {
    foreach ($u in $Url) {
        $file = Join-Path $work 'download'
        Invoke-WebRequest -Uri ($u -replace '#.*$') -OutFile $file -UserAgent (Get-UserAgent)
        [PSCustomObject]@{ Hash = (Get-FileHash $file -Algorithm SHA256).Hash.ToLower(); Url = $u }
        Remove-Item $file
    }
} finally {
    Remove-Item $work -Recurse -Force
}
