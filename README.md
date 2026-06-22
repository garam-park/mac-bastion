# Mac Bastion

Mac Bastion is a macOS bastion tunnel manager for repeated `ssh -L` workflows.
Instead of copy-pasting long SSH commands, you define profiles in a YAML file and control them from a menu bar app or the `mbastion` CLI.

[한국어](README.ko.md)

## Features

- **Menu bar app** — see tunnel status at a glance, start/stop/restart from a single click
- **`mbastion` CLI** — scriptable control for all lifecycle operations
- **YAML config** — version-controllable, shareable, supports split-profile layouts
- **Validation** — catches duplicate names, port conflicts, missing fields, and live port usage before startup
- **No daemon** — tunnels run as plain SSH processes; runtime records let the CLI and menu bar observe the same state
- **No dependencies** — builds with Apple Command Line Tools only

## Requirements

- macOS 12 or later
- Xcode 14 or later (for SwiftPM build), or Apple Command Line Tools (for the script build)

## Download

Packaged builds are published from [GitHub Releases](../../releases).

| Artifact | Contents |
| --- | --- |
| `MacBastionMenu-<version>-macos-arm64.zip` | Menu bar app |
| `mbastion-<version>-macos-arm64.tar.gz` | CLI binary + runtime library |
| `SHA256SUMS.txt` | Checksums |

## Build

**SwiftPM (recommended):**

```sh
swift build
swift test
```

**Dependency-free script build:**

```sh
scripts/build-cli.sh        # produces .build/manual/mbastion
scripts/package-menu-app.sh # produces .build/MacBastionMenu.app
```

## Quick Start

```sh
# 1. Create a sample config
mbastion init

# 2. Edit ~/.config/mac-bastion/config.yaml with your bastion details

# 3. Validate
mbastion validate --live

# 4. Start a tunnel
mbastion start dev-db

# 5. Check status
mbastion status
```

## Config

The default config path is `~/.config/mac-bastion/config.yaml`.

```yaml
apiVersion: mac-bastion/v1
kind: BastionConfig
currentProfile: dev-db
includes:
  - profiles/*.yaml
profiles:
  - name: dev-db
    description: Local Postgres through the development bastion
    enabled: true
    tags: [dev, database]
    bastion:
      host: bastion.example.com
      user: ec2-user
      port: 22
      identityFile: ~/.ssh/id_ed25519
      sshOptions:
        StrictHostKeyChecking: accept-new
    forwards:
      - name: postgres
        local:
          host: 127.0.0.1
          port: 15432
        remote:
          host: postgres.internal
          port: 5432
```

**Profile fields:**

| Field | Required | Default | Description |
| --- | --- | --- | --- |
| `name` | yes | — | Unique profile identifier |
| `description` | no | — | Human-readable label |
| `enabled` | no | `true` | Excluded from `start-all` and cross-profile port conflict checks when `false` |
| `tags` | no | `[]` | Arbitrary labels |
| `bastion.host` | yes | — | Bastion hostname or IP |
| `bastion.user` | no | — | SSH user (falls back to `~/.ssh/config` or system default) |
| `bastion.port` | no | `22` | SSH port |
| `bastion.identityFile` | no | — | Path to private key; `~` is expanded |
| `bastion.sshOptions` | no | `{}` | Arbitrary `-o Key=Value` options passed to `ssh` |

## Split Profiles

Large teams can split profiles into separate files:

```yaml
# ~/.config/mac-bastion/config.yaml
apiVersion: mac-bastion/v1
kind: BastionConfig
currentProfile: prod-api
includes:
  - profiles/*.yaml
profiles: []
```

Each included file may contain a single `profile:` key or a `profiles:` list.
Glob patterns (`*`) are supported. Include cycles are detected and rejected.
Diamond includes (the same file reachable via two separate paths) are deduplicated — the file is loaded only once.

## CLI Reference

```text
mbastion init [--config PATH] [--force]
mbastion list [--config PATH]
mbastion validate [--config PATH] [--live]
mbastion render-ssh [--config PATH] [PROFILE]
mbastion start [--config PATH] [PROFILE]
mbastion start-all [--config PATH]
mbastion stop PROFILE
mbastion stop-all [--config PATH]
mbastion restart [--config PATH] [PROFILE]
mbastion status [--config PATH] [PROFILE]
mbastion logs PROFILE
mbastion import FILE [--config PATH] [--mode merge|replace]
mbastion export [--config PATH] [--profile PROFILE] [--output PATH]
mbastion doctor [--config PATH]
```

| Command | Description |
| --- | --- |
| `init` | Write a sample config (skips if file exists; `--force` overwrites) |
| `list` | Print all profiles with state, forwards, and bastion |
| `validate` | Check config for errors and warnings; `--live` also probes local ports |
| `render-ssh` | Print the SSH command that would be run for a profile |
| `start` | Start a tunnel; validates live ports first |
| `start-all` | Start all enabled profiles; stops on first error |
| `stop` | Send SIGTERM (then SIGKILL if needed) and remove the runtime record |
| `stop-all` | Stop all running tunnels, including any whose profiles have been removed from config |
| `restart` | Stop then start |
| `status` | Show `running`, `stopped`, or `stale` for one or all profiles |
| `logs` | Print the last 4,000 bytes of a tunnel's log |
| `import` | Merge or replace config from a YAML file; backs up existing file first |
| `export` | Write the full config or a single profile to stdout or a file |
| `doctor` | Print config, runtime, and log directory paths |

**Tunnel states:**

| State | Meaning |
| --- | --- |
| `stopped` | No runtime record |
| `running` | Process is alive |
| `stale` | Runtime record exists but process is gone |

## Menu Bar App

The menu bar app reads the same YAML config as the CLI and refreshes tunnel state every 3 seconds.

```text
MB 2              ← running count in title
2/3 running

Validation Issues ← only shown when errors or warnings exist
  ERROR …

profile-name - running
  postgres: 127.0.0.1:15432 -> db.internal:5432
  ----
  Stop
  Restart
  Copy SSH Command
  Copy Last Log

Start All
Stop All
Reload Config
Validate Config
----
Open Config
Import Config...
Export Config...
----
Quit
```

When no config file exists, the menu shows **Create Sample Config** and **Import Config…** instead.

**Run during development:**

```sh
scripts/package-menu-app.sh
open .build/MacBastionMenu.app
```

The app stores no secrets. SSH authentication relies on `ssh-agent`, the macOS Keychain, or entries in `~/.ssh/config`.

## How It Works

Mac Bastion calls `/usr/bin/ssh` directly using an argument array (no shell interpolation):

```sh
ssh -N -T -o ExitOnForwardFailure=yes -o ServerAliveInterval=30 -o ServerAliveCountMax=3 \
    -L 127.0.0.1:15432:postgres.internal:5432 \
    ec2-user@bastion.example.com
```

After a startup settle window, it checks that the process is still alive. If not, it surfaces the last 3,000 bytes of log output as the error message.

Runtime state is stored under `~/Library/Application Support/MacBastion/`:

```text
runtime/<profile-name>.json   ← PID, startedAt, command, log path
logs/<profile-name>.log       ← SSH stdout + stderr
```

Both the CLI and menu bar read and write the same records, so they share a consistent view of running tunnels without a background daemon.

## Docs

See [`docs/`](docs/) for product plan, design rationale, and architecture notes.
