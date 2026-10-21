<#
.SYNOPSIS
    Report how this bucket diverges from ScoopInstaller/BucketTemplate.
.DESCRIPTION
    Read-only. Refreshes a shallow clone of the template in a temp directory, then reports
    the template files that are missing or differ here, plus the repo files the template
    does not have. bucket/ and deprecated/ are ignored: they are this bucket's manifests by
    design. Run with pwsh: a powershell started from a pwsh session inherits PS7's
    PSModulePath, which hides the 5.1 Get-FileHash.
.NOTES
    A differing file is reported before its diff, so the diff run is easy to skim.
#>
[CmdletBinding()]
param(
    [string] $TemplateDir = 'C:/Users/jerkl/AppData/Local/Temp/opencode/scoop-template',
    [string] $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')).Path
)

$templateRepo = 'https://github.com/ScoopInstaller/BucketTemplate.git'
$manifestDirs = '^(bucket|deprecated)/'

if (Test-Path -LiteralPath (Join-Path $TemplateDir '.git')) {
    git -C $TemplateDir fetch --depth 1 --quiet origin HEAD
    git -C $TemplateDir reset --hard --quiet FETCH_HEAD
}
else {
    git clone --depth 1 --quiet $templateRepo $TemplateDir
}

Write-Host "repo:     $RepoRoot"
Write-Host "template: $(git -C $TemplateDir log --oneline -1)"
Write-Host

$templateFiles = @(git -C $TemplateDir ls-files)
$repoFiles = @(git -C $RepoRoot ls-files)

$drift = @(
    foreach ($rel in $templateFiles) {
        $templatePath = Join-Path $TemplateDir $rel
        $repoPath = Join-Path $RepoRoot $rel
        if (!(Test-Path -LiteralPath $repoPath)) {
            [pscustomobject]@{ Kind = 'Missing'; Path = $rel }
        }
        elseif ((Get-FileHash -LiteralPath $templatePath).Hash -ne (Get-FileHash -LiteralPath $repoPath).Hash) {
            [pscustomobject]@{ Kind = 'Differs'; Path = $rel }
        }
    }
)
$extra = @($repoFiles | Where-Object { $_ -notin $templateFiles -and $_ -notmatch $manifestDirs })

if (!$drift -and !$extra) {
    Write-Host 'no drift: every template file matches'
    return
}

$drift | ForEach-Object { Write-Host ('{0,-8} {1}' -f $_.Kind, $_.Path) }
$extra | ForEach-Object { Write-Host ('{0,-8} {1}' -f 'Extra', $_) }
Write-Host

foreach ($item in $drift | Where-Object Kind -eq 'Differs') {
    Write-Host "===== $($item.Path) ====="
    git --no-pager diff --no-index --no-color -- `
        (Join-Path $TemplateDir $item.Path) (Join-Path $RepoRoot $item.Path)
    Write-Host
}
