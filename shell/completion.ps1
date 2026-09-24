# aws-console-url — PowerShell helper `awsc` + tab-completion.
#
# `aws console` (the CLI alias) cannot be tab-completed: the AWS CLI drives its
# own completer and treats alias arguments as opaque. So, like `ac` on zsh, we
# expose a PowerShell function `awsc` that CAN be completed.
#
# NOTE: `ac` is a built-in PowerShell alias for Add-Content, so we use `awsc`.
#
# This file is sourced from your PowerShell $PROFILE by install.ps1. It expects
# $env:AWS_CONSOLE_URL_SCRIPT to point at Open-AwsConsole.ps1 (install.ps1 sets it).

function awsc {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)][string]$AwsProfile,
        [Parameter(Position = 1)][string]$Service,
        [Parameter(ValueFromRemainingArguments = $true)]$Rest
    )
    if (-not $AwsProfile -and $env:AWS_PROFILE) { $AwsProfile = $env:AWS_PROFILE }
    if (-not $AwsProfile) { Write-Host "usage: awsc <profile> [service] [options]"; return }
    $script = $env:AWS_CONSOLE_URL_SCRIPT
    if (-not $script -or -not (Test-Path $script)) {
        Write-Error "Open-AwsConsole.ps1 not found (AWS_CONSOLE_URL_SCRIPT). Re-run install.ps1."
        return
    }
    # Build the argument list, omitting empty values (passing $null would bind as a
    # bogus positional argument to the target script).
    $argList = @($AwsProfile)
    if ($Service) { $argList += $Service }
    if ($Rest)    { $argList += $Rest }
    & $script @argList
}

# Complete profile names (live from the AWS CLI config).
Register-ArgumentCompleter -CommandName awsc -ParameterName AwsProfile -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete)
    try {
        $w = [regex]::Escape($wordToComplete)
        (& aws configure list-profiles 2>$null) |
            Where-Object { $_ -match "^$w" } |
            Sort-Object |
            ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_) }
    } catch { }
}

# Complete common service names.
Register-ArgumentCompleter -CommandName awsc -ParameterName Service -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete)
    try {
        $w = [regex]::Escape($wordToComplete)
        @('ec2','s3','lambda','rds','dynamodb','iam','vpc','ecs','ecr','eks',
          'cloudformation','cloudwatch','logs','sns','sqs','kms','secretsmanager',
          'ssm','apigateway','route53','cloudfront','stepfunctions','athena','glue') |
            Where-Object { $_ -match "^$w" } |
            ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_) }
    } catch { }
}
