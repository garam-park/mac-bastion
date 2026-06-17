# Architecture

## Shape

Mac Bastion is a SwiftPM project with three targets.

- `MacBastionCore`: data model, YAML parsing, config loading/merging, validation, SSH command construction, and runtime process records.
- `mbastion`: thin CLI wrapper around core.
- `MacBastionMenu`: AppKit `NSStatusItem` menu bar app around the same core.

The core is intentionally dependency-free so the project can build with Apple Command Line Tools.

## Config Model

The default config is `~/.config/mac-bastion/config.yaml`.

```yaml
apiVersion: mac-bastion/v1
kind: BastionConfig
currentProfile: dev-db
includes:
  - profiles/*.yaml
profiles:
  - name: dev-db
    bastion:
      host: bastion.example.com
      user: ec2-user
    forwards:
      - name: postgres
        local:
          host: 127.0.0.1
          port: 15432
        remote:
          host: postgres.internal
          port: 5432
```

Included files may contain a full config, a `profiles` list, or a single `profile`.

## Validation

Validation returns shared `ValidationIssue` values with `error`, `warning`, and `info` severities. CLI and UI render the same issues.

The first release validates structure and local endpoint conflicts. Live port checks use a temporary socket bind against IPv4 local hosts.

## Runtime

`TunnelRuntime` starts `/usr/bin/ssh` directly with an argument array:

```text
ssh -N -T -o ExitOnForwardFailure=yes -L localHost:localPort:remoteHost:remotePort user@bastion
```

Runtime metadata is stored under:

- `~/Library/Application Support/MacBastion/runtime/*.json`
- `~/Library/Application Support/MacBastion/logs/*.log`

This lets the CLI and menu bar observe the same running processes without a daemon in the first release.

## Known Tradeoffs

- CLI and menu bar can both start processes; runtime records reduce confusion but are not a full lock manager yet.
- The YAML parser supports the product schema subset rather than the entire YAML specification.
- SSH authentication prompts are not implemented as a custom UI. Users should rely on `ssh-agent`, macOS Keychain integration, or run the rendered SSH command to diagnose.
