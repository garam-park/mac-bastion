# Design

## Principles

- The menu bar should solve the common path: see status, start, stop, restart.
- Config remains the source of truth. The app visualizes, validates, and executes it.
- Errors explain cause, impact, and next action.
- Dangerous writes go through import validation and backup.

## Menu Structure

```text
Mac Bastion
3/4 running - 1 config error

Validation Issues
Profile A - running
  postgres: 127.0.0.1:15432 -> db.internal:5432
  Stop
  Restart
  Copy SSH Command
  Copy Last Log
Profile B - stopped
  Start
  Copy SSH Command

Start All
Stop All
Reload Config
Validate Config

Open Config
Import Config...
Export Config...
Quit
```

## States

- `stopped`: no runtime record.
- `running`: pid exists and responds to `kill(pid, 0)`.
- `stale`: runtime record exists but process is gone.
- `failed`: reserved for future supervisor state.

## Empty State

When no config exists, the menu shows:

- `Create Sample Config`
- `Import Config...`
- `Quit`

This keeps first run useful without a separate onboarding window.
