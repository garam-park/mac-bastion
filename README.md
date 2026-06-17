# Mac Bastion

Mac Bastion is a macOS bastion tunnel manager for repeated `ssh -L` workflows. It provides:

- a menu bar app for background tunnel control
- an `mbastion` CLI for automation
- YAML import/export
- single-file and split-profile config
- validation for duplicate profiles, port conflicts, and malformed profiles

## Build

Preferred SwiftPM path:

```sh
swift build
swift test
```

Dependency-free direct build path:

```sh
scripts/build-cli.sh
scripts/package-menu-app.sh
```

## Download

Packaged builds are published from GitHub Releases.

- `MacBastionMenu-<version>-macos-arm64.zip`: menu bar app
- `mbastion-<version>-macos-arm64.tar.gz`: CLI plus its runtime library
- `SHA256SUMS.txt`: checksums

## CLI

```sh
.build/manual/mbastion init
.build/manual/mbastion list
.build/manual/mbastion validate --live
.build/manual/mbastion render-ssh dev-db
.build/manual/mbastion start dev-db
.build/manual/mbastion start-all
.build/manual/mbastion status
.build/manual/mbastion logs dev-db
.build/manual/mbastion stop dev-db
.build/manual/mbastion stop-all
.build/manual/mbastion export --profile dev-db --output dev-db.yaml
.build/manual/mbastion import dev-db.yaml --mode merge
```

The default config path is:

```text
~/.config/mac-bastion/config.yaml
```

## Menu Bar App

Run directly during development:

```sh
scripts/package-menu-app.sh
open .build/MacBastionMenu.app
```

The packaged app stores no secrets. It reads the same YAML config as the CLI.

## Split Profiles

The root config can include profile files:

```yaml
apiVersion: mac-bastion/v1
kind: BastionConfig
currentProfile: prod-api
includes:
  - profiles/*.yaml
profiles: []
```

Each included file can contain either `profile:` or `profiles:`.

## Config

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

See `docs/` for product, design, and architecture notes.
