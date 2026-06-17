# Mac Bastion Product Plan

## Intent

Mac Bastion turns repeated `ssh -L` bastion commands into a quiet macOS product: a menu bar app for daily operation, a CLI for automation, and a YAML config model that can be shared like `kubectl` config.

## MVP

- Native macOS menu bar app with profile status, start, stop, restart, import, export, validation, and command/log copy actions.
- `mbastion` CLI with `init`, `list`, `validate`, `render-ssh`, `start`, `stop`, `restart`, `status`, `import`, `export`, and `doctor`.
- YAML config at `~/.config/mac-bastion/config.yaml`.
- Split profile support via `includes`, for example `profiles/*.yaml`.
- Validation for duplicate profile names, duplicate local endpoints, invalid ports, missing required fields, missing identity files, and live local port usage.
- SSH process execution through `/usr/bin/ssh` using argument arrays, not shell string interpolation.

## User Journeys

1. First run: `mbastion init` creates a sample config, then the menu bar app reads the same file.
2. Daily use: the user starts or stops profiles from the menu bar and sees a compact running count.
3. Debugging: the user validates config, copies the generated SSH command, or copies recent logs.
4. Sharing: the user exports the whole config or one profile, while private key contents are never embedded.
5. Scaling: a root config can include `profiles/*.yaml` so teams can manage one file or many files.

## Acceptance Criteria

- Three or more profiles can be listed, validated, started, stopped, and restarted.
- Duplicate enabled local ports are reported before startup.
- A local port already used by another process is blocked by `validate --live` and `start`.
- Exported YAML can be imported again and round-trips through tests.
- The menu bar app does not crash when config is missing or invalid.
- CLI and menu bar use the same config model and validation code.

## Later

- Launch at login.
- Profile editor window.
- Auto-reconnect with backoff.
- SSH config alias support.
- Redacted/team export mode.
- Keychain-aware UX for secrets.
- Codesigned/notarized app packaging.
