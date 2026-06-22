# AGENTS.md

Mac Bastion 코드베이스에서 작업하는 에이전트를 위한 가이드.

## ⚠️ 검증 시 실제 상태를 건드리지 말 것

부작용이 있는 `mbastion` CLI 명령을 **검증·테스트 목적으로 사용자의 실제 상태에 실행하지 않는다.**

대상 명령: `start`, `start-all`, `stop`, `stop-all`, `restart`, `import` (백업은 하지만 config를 덮어씀).

**이유:** support 경로(`ConfigStore.supportDirectoryURL`)와 기본 config 경로는
`FileManager.homeDirectoryForCurrentUser`를 쓴다. 이 API는 `HOME` 환경변수를
무시하고 시스템 계정 DB(`getpwuid`)에서 실제 홈을 가져온다. 따라서
`HOME=$(mktemp -d) mbastion stop-all` 같은 격리는 **무력화되어** 실제
`~/Library/Application Support/MacBastion/` 의 터널을 종료시킨다. 과거 이
방식으로 사용자의 orphan 터널을 실수로 모두 종료시킨 적이 있다.

**대신:**
- 부작용 있는 동작은 라이브러리 단위로 검증한다. `TunnelRuntime`과
  `ConfigStore`는 생성자에 디렉토리를 주입할 수 있다:
  - `TunnelRuntime(supportDirectory: <임시 URL>)`
  - 임시 디렉토리를 만들고 그 안에서만 start/stop/레코드를 다룬다.
- 완성된 CLI 바이너리(`.build/manual/mbastion`)로는 **읽기 전용** 명령만
  실행한다: `list`, `status`, `validate`, `render-ssh`, `doctor`.

## 빌드

이 환경에서 `swift build`(SwiftPM)는 Command Line Tools 매니페스트 링킹
문제로 실패할 수 있다. 이는 기존 환경 이슈이며 코드 문제가 아니다.
대신 의존성 없는 스크립트를 쓴다:

```sh
scripts/build-cli.sh        # .build/manual/mbastion + libMacBastionCore.dylib
scripts/package-menu-app.sh # .build/MacBastionMenu.app
```

라이브러리 단위 검증용 임시 실행 파일을 컴파일할 때:

```sh
swiftc -I .build/manual/modules -L .build/manual -lMacBastionCore \
  -Xlinker -rpath -Xlinker .build/manual <file>.swift -o <out>
```

## 커밋

루트 `~/.claude/CLAUDE.md` 규칙을 따른다: 한국어로 대화, 의미 단위로 커밋,
커밋 메시지는 "왜" 중심, Claude/AI 관련 트레일러·서명 금지(사용자가 명시
요청한 경우 제외), push는 명시 요청 시에만.
