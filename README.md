# aws-console-url

Open the AWS Management Console for any profile straight from your terminal —
with **multi-session** support — as a native-feeling `aws console` subcommand.

```bash
aws console terracloud            # opens the console for the profile's account
aws console prod           # opens a second account in its own session
aws console staging --print      # print the sign-in URL instead of opening it
```

> Installed as two aliases pointing at the same script: `aws console` (short) and
> `aws console-url` (explicit). Use whichever you prefer.

## Why this exists

Tools that "open the AWS console" typically ship an opaque binary that reads your
SSO token cache (`~/.aws/sso/cache`) and talks to STS/SSO directly. That binary
runs with your full user privileges and holds your credentials, so you have to
trust it not to exfiltrate them.

This tool takes the opposite approach: **it delegates all credential handling to
the AWS CLI.** It never reads your SSO token cache and never fetches tokens
itself. It only:

1. asks the AWS CLI for already-resolved temporary credentials
   (`aws configure export-credentials`),
2. asks the AWS CLI for the account id (`aws sts get-caller-identity`),
3. performs the standard, documented [AWS federation sign-in flow][fed] against
   `signin.aws.amazon.com/federation`, and
4. opens the resulting URL in your browser.

The whole thing is ~150 lines of auditable `bash`. The only components that ever
touch your long-lived credentials are the AWS CLI (Amazon's own code) and, briefly,
the temporary session credentials used for the federation POST.

[fed]: https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_providers_enable-console-custom-url.html

## Requirements

- [AWS CLI v2](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)
  (needs `aws configure export-credentials`)
- `curl` and `python3` (both preinstalled on macOS and most Linux distros)
- Profiles configured for AWS IAM Identity Center (SSO) or assume-role — i.e.
  profiles that yield **temporary** credentials with a session token.

## Install

```bash
git clone <this-repo> aws-console-url
cd aws-console-url
./install.sh
```

This copies `bin/console-url.sh` to `~/.aws/cli/console-url.sh` and registers the
`console` and `console-url` aliases in `~/.aws/cli/alias` (preserving any aliases
you already have).

Verify:

```bash
aws console <your-profile> --print
```

## Usage

```
aws console <profile> [options]      # (aws console-url is an equivalent alias)

Options:
  --print          Print the URL instead of opening a browser.
  --browser <app>  Browser to open in. macOS: an app name ("Safari",
                   "Google Chrome"); Linux: a command on PATH ("firefox").
                   Overrides $AWS_CONSOLE_BROWSER. Defaults to the system default.
  --no-multi       Disable multi-session (account-scoped) routing.
  --region <r>     Console home region (default: profile region, else us-east-1).
  --destination <url>  Custom post-sign-in destination (overrides region/multi).
  --duration <sec> Federation session duration. Only honored for IAM long-term-key
                   profiles; ignored for SSO/assume-role sessions.
```

### Preferred browser

By default the URL opens in your system default browser. To pin one:

```bash
export AWS_CONSOLE_BROWSER="Safari"     # or "Google Chrome"
# or per-invocation:
aws console terracloud --browser "Google Chrome"
```

## Multi-session

The AWS Console supports being signed into up to **5 identities simultaneously**
in one browser. This tool enables it by scoping the sign-in destination to the
profile's account id (`&account=<id>`), so each account opens in its own session
instead of overwriting the previous one.

**One-time setup:** the first time you use multi-session, the AWS Console shows an
"Enable multi-session" prompt — click it once per browser. After that, opening
different profiles keeps their sessions separate.

Use `--no-multi` for the classic single-session behavior.

## How credentials flow

```
aws console <profile>
        │
        ├─ aws configure export-credentials  → temporary creds (CLI does SSO/STS)
        ├─ aws sts get-caller-identity        → account id
        │
        ├─ GET signin.aws.amazon.com/federation?Action=getSigninToken   (curl)
        └─ open  signin.aws.amazon.com/federation?Action=login&...       (browser)
```

The script never reads `~/.aws/sso/cache`, never stores credentials, and only
contacts `signin.aws.amazon.com`.

## Notes & limitations

- `SessionDuration` is only valid when federating with an IAM user's long-term
  keys. For SSO/assume-role sessions (which already carry a session token) it must
  be omitted, so `--duration` is ignored for those — the session length follows the
  underlying temporary credentials.
- macOS and Linux are supported for opening a browser. On other platforms, use
  `--print` and open the URL yourself.

## License

MIT — see [LICENSE](./LICENSE).
