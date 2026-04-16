# mac-ai-orphan-cleaner

Safe macOS cleanup for orphaned AI helper processes left behind by Codex, Claude Code, Cursor, and MCP toolchains.

It targets only orphan helper processes (`PPID=1`) that match known AI-related command patterns, and it avoids killing:

- `Codex.app` and `Cursor.app`
- crash handlers and update helpers
- dev servers such as `vite`, `turbo`, and `esbuild`
- active browser automation controllers such as `agent-browser`
- orphan `zsh` shells unless you explicitly opt in

It also includes two conservative cleanup rules for common long-lived leftovers:

- orphaned `Google Chrome for Testing` processes created under `agent-browser` temp profiles
- `gitstatusd-darwin-arm64` processes whose parent shell has already become an orphaned `zsh`

## Why copy install

This repo is designed for multiple Macs. The recommended flow is:

1. Clone the repo on each machine.
2. Run `./install.sh`.
3. Let the installer copy files into the standard per-user locations.

Copy install is more reliable than symlinks when you want the same setup across MacBooks and a Mac mini, because each machine ends up with the expected files in:

- `~/bin/clean-ai-orphans.sh`
- `~/Library/LaunchAgents/com.leeth.clean-ai-orphans.plist`

## Install

```bash
git clone https://github.com/maj0rika/mac-ai-orphan-cleaner.git
cd mac-ai-orphan-cleaner
./install.sh
```

After install, macOS will:

- run the cleanup once at login via `RunAtLoad`
- run it every 10 minutes via `StartInterval`

## Usage

Manual dry run:

```bash
~/bin/clean-ai-orphans.sh --dry-run --verbose
```

Manual run:

```bash
~/bin/clean-ai-orphans.sh
```

Opt-in shell cleanup mode:

```bash
~/bin/clean-ai-orphans.sh --dry-run --verbose --include-shells
```

## Logs

```bash
tail -f ~/Library/Logs/clean-ai-orphans.log
```

## launchd status

```bash
launchctl print gui/$(id -u)/com.leeth.clean-ai-orphans
```

Run immediately:

```bash
launchctl kickstart -k gui/$(id -u)/com.leeth.clean-ai-orphans
```

## Uninstall

```bash
./uninstall.sh
```

This removes the copied script and LaunchAgent, but leaves the log file in place.
