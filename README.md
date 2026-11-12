# QuotaBar

Claude plan usage in the macOS menu bar: how much of each limit is left, whether
your current pace lasts until reset, and when you would run out if it does not.

Native SwiftUI, one source file, no dependencies.

## Requirements

- macOS 14 or later, Xcode command line tools (`xcrun swiftc`)
- Claude Code CLI installed and signed in with a claude.ai plan (`claude auth login`).
  QuotaBar reads the CLI's keychain item `Claude Code-credentials`.

## Install

```bash
brew install rorydotgg/tap/quotabar
```

Homebrew builds it from source on your machine, then tells you how to open it. Both
repos are private, so git needs GitHub access to them (for example
`gh auth setup-git`).

## Build from a checkout

```bash
./build.sh
open QuotaBar.app
```

`./test.sh` runs the response-parsing checks plus one live call.

## How it works

- Every 5 minutes it calls `GET https://api.anthropic.com/api/oauth/usage`
  (header `anthropic-beta: oauth-2025-04-20`) with the CLI's access token.
- On HTTP 429 it doubles the wait, up to 30 minutes. The endpoint sends
  `retry-after: 0`, so there is nothing better to go on.
- When the token has expired it runs `claude auth status`, which renews it without
  a model call, then retries. The Claude desktop app does not renew this token.
  QuotaBar never touches the refresh token itself.
- The last numbers and back-off state are saved in `UserDefaults` (`local.quotabar`),
  so a relaunch shows the last reading without calling the endpoint.
- Accounts without a 5-hour limit (for example Ultra) show weekly limits only.

Projections are linear: average pace since the window opened, carried to the reset.
They are noisy in the first day of a weekly window.

## Settings

Under the `⋯` menu: **Show remaining** (default on; off shows usage instead) and
**Open at login**. Open at login works best once the app is in `~/Applications`.

## Caveats

The usage endpoint is undocumented and can change without notice.

## Scripts

- `scripts/claude-usage.sh`: same data as JSON in `~/.claude/usage-live.json`, for
  other tools.
- `scripts/statusline-usage.sh`: a Claude Code status line that exports
  `rate_limits` while the CLI is open.
