# aws-console-url — zsh completion for the `ac` helper (and a standalone
# `console-url` on PATH, if you have one).
#
# Enable by sourcing this file from your ~/.zshrc, after compinit:
#
#     autoload -Uz compinit && compinit         # (usually already in your ~/.zshrc)
#     source /path/to/aws-console-url/shell/completion.zsh
#
# Completes:
#   arg 1  -> AWS profile names (live, from `aws configure list-profiles`)
#   arg 2  -> common service deep-link names
#   flags  -> --print --browser --no-multi --multi --service --region --destination --duration
#
# Note: this completes the `ac` function and a `console-url` command. It does NOT
# complete the `aws console` alias form, because the AWS CLI drives its own
# completer for `aws ...` and treats alias arguments as opaque.

# Curated list of services that resolve to a console deep-link.
# Most map to /<service>/home; the tool special-cases s3, iam, route53,
# billing, stepfunctions (see bin/console-url.sh).
_acu_services() {
  local -a services
  services=(
    ec2 vpc lambda s3 rds dynamodb iam
    ecs eks ecr cloudformation cloudwatch
    sns sqs kms secretsmanager ssm
    apigateway route53 cloudfront
    stepfunctions sfn athena glue
    logs events elasticache efs
    billing cost organizations
    states
  )
  _describe -t services 'AWS service' services
}

# Live profile names from the AWS CLI config.
_acu_profiles() {
  local -a profiles
  profiles=(${(f)"$(aws configure list-profiles 2>/dev/null)"})
  _describe -t profiles 'AWS profile' profiles
}

_ac() {
  local curcontext="$curcontext" state line
  typeset -A opt_args

  _arguments -C \
    '(--print)--print[print the URL instead of opening a browser]' \
    '(--browser)--browser[browser app/command to open the URL in]:browser:' \
    '(--no-multi --multi)--no-multi[disable multi-session account scoping]' \
    '(--no-multi --multi)--multi[enable multi-session account scoping]' \
    '(--service)--service[service to deep-link into]:service:_acu_services' \
    '(--region)--region[console landing region]:region:' \
    '(--destination)--destination[custom post-sign-in destination URL]:url:' \
    '(--duration)--duration[federation session duration (seconds)]:seconds:' \
    '1:profile:_acu_profiles' \
    '2:service:_acu_services' \
    && return 0
}

# Register for the `ac` function and a standalone `console-url` command.
# (compdef is available once compinit has run in your ~/.zshrc.)
compdef _ac ac console-url
