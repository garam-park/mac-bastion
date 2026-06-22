# Mac Bastion

Mac Bastion은 macOS에서 반복적인 `ssh -L` 배스천 터널 작업을 자동화하는 관리 도구입니다.
긴 SSH 명령어를 매번 복사·붙여넣기 하는 대신, YAML 파일에 프로파일을 정의하고 메뉴바 앱 또는 `mbastion` CLI로 제어합니다.

[English](README.md)

## 기능

- **메뉴바 앱** — 터널 상태를 한눈에 확인하고 한 번의 클릭으로 시작/중지/재시작
- **`mbastion` CLI** — 모든 라이프사이클 작업을 스크립트로 자동화
- **YAML 설정** — 버전 관리 가능하고 팀 공유가 쉬우며 분할 프로파일 레이아웃 지원
- **유효성 검사** — 시작 전에 중복 이름, 포트 충돌, 필수 필드 누락, 실시간 포트 사용 여부를 감지
- **데몬 없음** — 터널은 일반 SSH 프로세스로 실행되며 런타임 레코드를 통해 CLI와 메뉴바 앱이 동일한 상태를 공유
- **의존성 없음** — Apple Command Line Tools만으로 빌드 가능

## 요구사항

- macOS 12 이상
- Xcode 14 이상 (SwiftPM 빌드 시) 또는 Apple Command Line Tools (스크립트 빌드 시)

## 다운로드

패키징된 빌드는 [GitHub Releases](../../releases)에서 제공됩니다.

| 파일 | 내용 |
| --- | --- |
| `MacBastionMenu-<version>-macos-arm64.zip` | 메뉴바 앱 |
| `mbastion-<version>-macos-arm64.tar.gz` | CLI 바이너리 + 런타임 라이브러리 |
| `SHA256SUMS.txt` | 체크섬 |

## 빌드

**SwiftPM (권장):**

```sh
swift build
swift test
```

**의존성 없는 스크립트 빌드:**

```sh
scripts/build-cli.sh        # .build/manual/mbastion 생성
scripts/package-menu-app.sh # .build/MacBastionMenu.app 생성
```

## 빠른 시작

```sh
# 1. 샘플 설정 파일 생성
mbastion init

# 2. ~/.config/mac-bastion/config.yaml 을 열어 배스천 정보를 입력

# 3. 유효성 검사
mbastion validate --live

# 4. 터널 시작
mbastion start dev-db

# 5. 상태 확인
mbastion status
```

## 설정

기본 설정 파일 경로: `~/.config/mac-bastion/config.yaml`

```yaml
apiVersion: mac-bastion/v1
kind: BastionConfig
currentProfile: dev-db
includes:
  - profiles/*.yaml
profiles:
  - name: dev-db
    description: 개발 배스천을 통한 로컬 Postgres 연결
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

**프로파일 필드:**

| 필드 | 필수 | 기본값 | 설명 |
| --- | --- | --- | --- |
| `name` | 예 | — | 프로파일 고유 식별자 |
| `description` | 아니오 | — | 사람이 읽는 설명 |
| `enabled` | 아니오 | `true` | `false`이면 `start-all` 대상과 포트 충돌 검사에서 제외 |
| `tags` | 아니오 | `[]` | 임의 레이블 |
| `bastion.host` | 예 | — | 배스천 호스트명 또는 IP |
| `bastion.user` | 아니오 | — | SSH 사용자 (`~/.ssh/config` 또는 시스템 기본값 사용) |
| `bastion.port` | 아니오 | `22` | SSH 포트 |
| `bastion.identityFile` | 아니오 | — | 개인키 경로; `~` 확장 지원 |
| `bastion.sshOptions` | 아니오 | `{}` | `ssh`에 전달하는 임의 `-o Key=Value` 옵션 |

## 분할 프로파일

팀 환경에서는 프로파일을 여러 파일로 분리할 수 있습니다:

```yaml
# ~/.config/mac-bastion/config.yaml
apiVersion: mac-bastion/v1
kind: BastionConfig
currentProfile: prod-api
includes:
  - profiles/*.yaml
profiles: []
```

포함된 각 파일에는 단일 `profile:` 키 또는 `profiles:` 목록을 사용할 수 있습니다.
글로브 패턴(`*`)을 지원하며 순환 참조는 감지 후 거부됩니다.
다이아몬드 include(두 경로에서 같은 파일을 참조)는 중복 제거되어 해당 파일을 한 번만 로드합니다.

## CLI 레퍼런스

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

| 커맨드 | 설명 |
| --- | --- |
| `init` | 샘플 설정 파일 생성 (파일이 존재하면 건너뜀; `--force`로 덮어쓰기) |
| `list` | 모든 프로파일의 상태, 포워드, 배스천 정보 출력 |
| `validate` | 설정 오류 및 경고 검사; `--live`는 로컬 포트 실사용 여부도 함께 확인 |
| `render-ssh` | 프로파일에 대해 실행될 SSH 명령어 출력 |
| `start` | 터널 시작 (시작 전 라이브 포트 유효성 검사) |
| `start-all` | 활성화된 모든 프로파일 시작; 오류 발생 시 중단 |
| `stop` | SIGTERM 전송 (필요 시 SIGKILL) 후 런타임 레코드 삭제 |
| `stop-all` | 실행 중인 모든 터널 중지 (config에서 삭제된 프로파일의 터널 포함) |
| `restart` | 중지 후 재시작 |
| `status` | 하나 또는 전체 프로파일의 `running`, `stopped`, `stale` 상태 표시 |
| `logs` | 터널 로그 마지막 4,000 bytes 출력 |
| `import` | YAML 파일로부터 설정을 병합 또는 교체; 기존 파일은 자동 백업 |
| `export` | 전체 설정 또는 단일 프로파일을 표준 출력 또는 파일로 저장 |
| `doctor` | 설정, 런타임, 로그 디렉토리 경로 출력 |

**터널 상태:**

| 상태 | 의미 |
| --- | --- |
| `stopped` | 런타임 레코드 없음 |
| `running` | 프로세스 살아있음 |
| `stale` | 런타임 레코드는 있지만 프로세스가 종료됨 |

## 메뉴바 앱

메뉴바 앱은 CLI와 동일한 YAML 설정을 읽으며 3초마다 터널 상태를 새로고침합니다.

```text
MB 2              ← 제목에 실행 중인 터널 수 표시
2/3 running

Validation Issues ← 오류 또는 경고가 있을 때만 표시
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

설정 파일이 없으면 **Create Sample Config** 와 **Import Config…** 메뉴가 대신 표시됩니다.

**개발 중 실행:**

```sh
scripts/package-menu-app.sh
open .build/MacBastionMenu.app
```

앱은 비밀 정보를 저장하지 않습니다. SSH 인증은 `ssh-agent`, macOS Keychain, 또는 `~/.ssh/config` 설정에 의존합니다.

## 동작 방식

Mac Bastion은 쉘 문자열 보간 없이 인자 배열을 사용해 `/usr/bin/ssh`를 직접 호출합니다:

```sh
ssh -N -T -o ExitOnForwardFailure=yes -o ServerAliveInterval=30 -o ServerAliveCountMax=3 \
    -L 127.0.0.1:15432:postgres.internal:5432 \
    ec2-user@bastion.example.com
```

시작 안정화 대기 후 프로세스가 살아있는지 확인합니다. 프로세스가 종료됐다면 로그 마지막 3,000 bytes를 오류 메시지로 출력합니다.

런타임 상태는 `~/Library/Application Support/MacBastion/` 하위에 저장됩니다:

```text
runtime/<profile-name>.json   ← PID, 시작 시각, 명령어, 로그 경로
logs/<profile-name>.log       ← SSH stdout + stderr
```

CLI와 메뉴바 앱이 동일한 레코드를 읽고 쓰므로 별도의 백그라운드 데몬 없이도 실행 중인 터널 상태를 일관되게 공유합니다.

## 문서

제품 계획, 설계 근거, 아키텍처 설명은 [`docs/`](docs/) 디렉토리를 참고하세요.
