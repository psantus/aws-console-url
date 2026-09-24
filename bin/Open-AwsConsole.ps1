<#
.SYNOPSIS
    Open the AWS Management Console for a profile from PowerShell — with
    multi-session support and service deep-links.

.DESCRIPTION
    PowerShell-native port of console-url.sh. Credential handling is fully
    delegated to the AWS CLI: this script never reads ~/.aws/sso/cache and never
    calls SSO/STS itself for tokens. It asks the CLI for already-resolved
    temporary credentials (aws configure export-credentials), resolves the
    account id (aws sts get-caller-identity), performs the standard AWS
    federation getSigninToken flow, and opens (or prints) the sign-in URL.

.PARAMETER Profile
    The AWS profile to open the console for. Falls back to $env:AWS_PROFILE.

.PARAMETER Service
    Optional service to deep-link into (e.g. ec2, s3, lambda, rds). Most map to
    /<service>/home; s3/iam/route53/billing are global; stepfunctions -> states.

.PARAMETER Print
    Print the URL instead of opening a browser.

.PARAMETER NoMulti
    Disable multi-session (account-scoped) routing.

.PARAMETER Region
    Console landing region (default: profile region, else us-east-1).

.PARAMETER Destination
    Custom post-sign-in destination URL (overrides region/service/multi).

.EXAMPLE
    .\Open-AwsConsole.ps1 myprofile
.EXAMPLE
    .\Open-AwsConsole.ps1 myprofile ec2 -Print
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)][string]$AwsProfile,
    [Parameter(Position = 1)][string]$Service,
    [switch]$Print,
    [switch]$NoMulti,
    [string]$Region,
    [string]$Destination,
    [string]$Duration = "3600"
)

$ErrorActionPreference = "Stop"

# Locate the AWS CLI.
$awsCmd = (Get-Command aws -ErrorAction SilentlyContinue).Source
if (-not $awsCmd) {
    $fallback = "C:\Program Files\Amazon\AWSCLIV2\aws.exe"
    if (Test-Path $fallback) { $awsCmd = $fallback }
    else { Write-Error "AWS CLI not found on PATH."; exit 1 }
}

# Profile: explicit arg, else $env:AWS_PROFILE.
if (-not $AwsProfile) { $AwsProfile = $env:AWS_PROFILE }
if (-not $AwsProfile) {
    Write-Error "usage: Open-AwsConsole <profile> [service] [-Print] [-NoMulti] [-Region r] [-Destination url]"
    exit 2
}

# Region: explicit flag > profile config > us-east-1.
if (-not $Region) {
    $Region = (& $awsCmd configure get region --profile $AwsProfile 2>$null)
}
if (-not $Region) { $Region = "us-east-1" }

# Verify we have a usable session for this profile. Capture stdout+stderr so a
# native-command error surface as a clean message, not a PowerShell stack trace.
$whoAmI = & $awsCmd sts get-caller-identity --profile $AwsProfile --query Account --output text 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "Not signed in for profile '$AwsProfile' (or the session has expired)." -ForegroundColor Yellow
    Write-Host "Run:  aws sso login --profile $AwsProfile" -ForegroundColor Yellow
    exit 1
}
$AccountId = "$whoAmI".Trim()
if ($AccountId -eq "None") { $AccountId = "" }

# Build the destination.
if (-not $Destination) {
    $global = $false
    if ($Service) {
        switch ($Service) {
            "s3"            { $svcPath = "s3";          $global = $true }
            "iam"           { $svcPath = "iam";         $global = $true }
            { $_ -in "route53","r53" } { $svcPath = "route53/v2"; $global = $true }
            { $_ -in "billing","cost" } { $svcPath = "billing";  $global = $true }
            { $_ -in "stepfunctions","sfn" } { $svcPath = "states" }
            default         { $svcPath = $Service }
        }
        if ($global) { $base = "https://console.aws.amazon.com/$svcPath/home" }
        else         { $base = "https://$Region.console.aws.amazon.com/$svcPath/home?region=$Region" }
    }
    else {
        $base = "https://$Region.console.aws.amazon.com/console/home?region=$Region"
    }

    if (-not $NoMulti -and $AccountId) {
        if ($base -match "\?") { $Destination = "$base&account=$AccountId" }
        else                   { $Destination = "$base`?account=$AccountId" }
    }
    else {
        $Destination = $base
    }
}

# --- Credentials: delegated entirely to the AWS CLI ---
$credsJson = & $awsCmd configure export-credentials --profile $AwsProfile --format process 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "Could not obtain credentials for profile '$AwsProfile'." -ForegroundColor Yellow
    Write-Host "Run:  aws sso login --profile $AwsProfile" -ForegroundColor Yellow
    exit 1
}
try { $creds = "$credsJson" | ConvertFrom-Json } catch {
    Write-Host "Could not parse credentials for profile '$AwsProfile'." -ForegroundColor Yellow
    Write-Host "Run:  aws sso login --profile $AwsProfile" -ForegroundColor Yellow
    exit 1
}
if (-not $creds.SessionToken) {
    Write-Error "federation requires temporary credentials (a SessionToken); profile '$AwsProfile' returned long-term keys. Use an SSO/assume-role profile."
    exit 1
}

$session = @{
    sessionId    = $creds.AccessKeyId
    sessionKey   = $creds.SecretAccessKey
    sessionToken = $creds.SessionToken
} | ConvertTo-Json -Compress

$fed = "https://signin.aws.amazon.com/federation"

# Step 1: exchange the session for a SigninToken.
# NOTE: no SessionDuration for temporary (SSO/assume-role) credentials.
$getTokenUri = "$fed`?Action=getSigninToken&Session=$([uri]::EscapeDataString($session))"
$signinToken = (Invoke-RestMethod -Uri $getTokenUri -Method Get).SigninToken

# Step 2: build the login URL.
$loginUrl = "$fed`?Action=login" +
    "&Issuer=$([uri]::EscapeDataString('console-url'))" +
    "&Destination=$([uri]::EscapeDataString($Destination))" +
    "&SigninToken=$([uri]::EscapeDataString($signinToken))"

if ($Print) {
    Write-Output $loginUrl
}
else {
    Start-Process $loginUrl
    $what = if ($Service) { "AWS $Service console" } else { "AWS Console" }
    $acct = if ($AccountId) { " account $AccountId" } else { "" }
    Write-Host "Opened $what for profile '$AwsProfile'$acct (region $Region)."
}
