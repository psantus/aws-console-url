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

    # Ensure the $PROFILE file exists (resolve the real path of THIS session).
    if (-not (Test-Path $PROFILE)) {
        New-Item -ItemType File -Path $PROFILE -Force | Out-Null
    }
    $marker = "# aws-console-url helper (awsc)"
    $block = @(
        "",
        $marker,
        "`$env:AWS_CONSOLE_URL_SCRIPT = `"$dst`"",
        ". `"$complDst`""
    ) -join "`r`n"

    $existing = Get-Content $PROFILE -Raw -ErrorAction SilentlyContinue
    if ($existing -notlike "*$marker*") {
        Add-Content -Path $PROFILE -Value $block -Encoding utf8
    }
    # Verify the block is actually present in THIS session's profile.
    if ((Get-Content $PROFILE -Raw -ErrorAction SilentlyContinue) -like "*$marker*") {
        Write-Host "  - 'awsc' + completion installed in $PROFILE"
    } else {
        Write-Warning "Could not write to `$PROFILE ($PROFILE). Add these two lines manually:"
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
