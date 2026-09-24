<#
.SYNOPSIS
    Install the `aws console` subcommand on Windows (PowerShell).

.DESCRIPTION
    Copies Open-AwsConsole.ps1 to a stable location and registers the
    `console` / `console-url` aliases in the AWS CLI alias file
    (%USERPROFILE%\.aws\cli\alias) so you can run:

        aws console <profile> [service] [options]

    Credential handling is fully delegated to the AWS CLI.

.EXAMPLE
    .\install.ps1
#>
[CmdletBinding()]
param(
    [string]$InstallDir = (Join-Path $HOME ".aws-console-url")
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$src = Join-Path $scriptDir "bin\Open-AwsConsole.ps1"
if (-not (Test-Path $src)) { throw "Cannot find bin\Open-AwsConsole.ps1 next to install.ps1" }

# 1) Copy the script to a stable, space-free location.
New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
$dst = Join-Path $InstallDir "Open-AwsConsole.ps1"
Copy-Item $src $dst -Force
Write-Host "  - installed $dst"

# 2) Register the AWS CLI aliases. The alias file must have [toplevel] then one
#    line per alias. On Windows the alias invokes PowerShell with -File.
$aliasDir = Join-Path $HOME ".aws\cli"
$aliasFile = Join-Path $aliasDir "alias"
New-Item -ItemType Directory -Force -Path $aliasDir | Out-Null

$line = 'console = !powershell -ExecutionPolicy Bypass -File "' + $dst + '"'
$lineUrl = 'console-url = !powershell -ExecutionPolicy Bypass -File "' + $dst + '"'

$lines = New-Object System.Collections.Generic.List[string]
if (Test-Path $aliasFile) {
    # Preserve existing aliases, drop any prior console/console-url lines and [toplevel].
    foreach ($l in Get-Content $aliasFile) {
        if ($l -match '^\s*\[toplevel\]\s*$') { continue }
        if ($l -match '^\s*console(-url)?\s*=') { continue }
        $lines.Add($l)
    }
}
$final = New-Object System.Collections.Generic.List[string]
$final.Add("[toplevel]")
$final.Add($line)
$final.Add($lineUrl)
foreach ($l in $lines) { if ($l.Trim()) { $final.Add($l) } }

Set-Content -Path $aliasFile -Value $final -Encoding ascii
Write-Host "  - registered 'aws console' in $aliasFile"

# 3) Install the `awsc` PowerShell helper + tab-completion into the user's
#    $PROFILE. `aws console` (the CLI alias) cannot be completed, so `awsc`
#    provides the tab-completable equivalent (profiles + services).
$complSrc = Join-Path $scriptDir "shell\completion.ps1"
if (Test-Path $complSrc) {
    $complDst = Join-Path $InstallDir "completion.ps1"
    Copy-Item $complSrc $complDst -Force

    # Resolve the profile path deterministically. Inside a script invoked with
    # `& script.ps1`, the automatic $PROFILE can be empty/unreliable, so we
    # rebuild it from the user's Documents folder (WindowsPowerShell host).
    $profilePath = $PROFILE
    if (-not $profilePath) {
        $docs = [Environment]::GetFolderPath('MyDocuments')
        $profilePath = Join-Path $docs "WindowsPowerShell\Microsoft.PowerShell_profile.ps1"
    }
    $profileDir = Split-Path -Parent $profilePath
    if (-not (Test-Path $profileDir)) { New-Item -ItemType Directory -Force -Path $profileDir | Out-Null }
    if (-not (Test-Path $profilePath)) { New-Item -ItemType File -Force -Path $profilePath | Out-Null }

    $marker = "# aws-console-url helper (awsc)"
    $blockLines = @(
        $marker,
        "`$env:AWS_CONSOLE_URL_SCRIPT = `"$dst`"",
        ". `"$complDst`""
    )

    # Idempotent: remove any previous aws-console-url block (marker + the two
    # lines that reference our install dir), then append a fresh one. Re-running
    # the installer — even with a different version/path — leaves exactly one
    # correct block.
    $kept = New-Object System.Collections.Generic.List[string]
    foreach ($l in (Get-Content $profilePath -ErrorAction SilentlyContinue)) {
        if ($l -match [regex]::Escape($marker)) { continue }
        if ($l -match 'AWS_CONSOLE_URL_SCRIPT') { continue }
        if ($l -match 'aws-console-url\\completion\.ps1') { continue }
        $kept.Add($l)
    }
    # Drop trailing blank lines for a clean file.
    while ($kept.Count -gt 0 -and -not $kept[$kept.Count - 1].Trim()) { $kept.RemoveAt($kept.Count - 1) }
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($l in $kept) { $out.Add($l) }
    $out.Add("")
    foreach ($l in $blockLines) { $out.Add($l) }
    # ASCII avoids the UTF-8 BOM that PowerShell 5.1 prepends (which breaks both
    # dot-sourcing of the profile and the marker check below).
    Set-Content -Path $profilePath -Value $out -Encoding ascii

    # Verify (line-by-line, BOM-insensitive).
    $ok = $false
    foreach ($l in (Get-Content $profilePath -ErrorAction SilentlyContinue)) {
        if ($l -match [regex]::Escape($marker)) { $ok = $true; break }
    }
    if ($ok) {
        Write-Host "  - 'awsc' + completion installed in $profilePath"
    } else {
        Write-Warning "Could not write to the PowerShell profile ($profilePath). Add these two lines manually:"
        Write-Host "    `$env:AWS_CONSOLE_URL_SCRIPT = `"$dst`""
        Write-Host "    . `"$complDst`""
    }
}

Write-Host ""
Write-Host "Done. Try:"
Write-Host "  aws console <your-profile> --print"
Write-Host "  aws console <your-profile> ec2"
Write-Host ""
Write-Host "For tab-completion, open a NEW PowerShell and use 'awsc':"
Write-Host "  awsc <TAB>            # completes profiles"
Write-Host "  awsc myprofile <TAB>  # completes services"
