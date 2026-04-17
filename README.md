# mac-ai-orphan-cleaner

Codex, Claude Code, Cursor, MCP 툴체인이 남기는 orphan AI 보조 프로세스를 macOS에서 안전하게 정리하는 도구입니다.

기본 모드는 `PPID=1`인 orphan 프로세스 중에서 AI 관련 패턴과 일치하는 보조 프로세스만 대상으로 삼습니다. 아래 항목은 기본적으로 건드리지 않습니다.

- `Codex.app` and `Cursor.app`
- crash handlers and update helpers
- dev servers such as `vite`, `turbo`, and `esbuild`
- active browser automation controllers such as `agent-browser`
- orphan `zsh` shells unless you explicitly opt in

위 목록을 한국어로 풀면:

- `Codex.app`, `Cursor.app` 같은 본체 앱
- crash handler, updater 같은 유지보수용 프로세스
- `vite`, `turbo`, `esbuild` 같은 개발 서버/빌드 도구
- `agent-browser` 같은 실제 브라우저 자동화 컨트롤러
- 사용자가 명시적으로 켜지 않은 orphan `zsh` 정리

기본 모드에는 오래 남기 쉬운 잔여 프로세스를 위한 보수적인 정리 규칙도 포함되어 있습니다.

- `agent-browser` 임시 프로필 아래에서 뜬 orphan `Google Chrome for Testing`
- 부모 셸이 이미 orphan `zsh`가 된 `gitstatusd-darwin-arm64`

맥이 점점 느려지는 원인이 Chromium 계열 helper renderer 누적이라면, 더 공격적인 `aggressive` 모드를 선택할 수 있습니다.

## 왜 복사 설치인가

이 레포는 맥 여러 대에서 같은 설정을 공유하는 상황을 기준으로 만들었습니다. 권장 흐름은 아래와 같습니다.

1. 각 맥에서 이 레포를 clone 합니다.
2. `./install.sh`를 실행합니다.
3. 설치 스크립트가 표준 사용자 경로로 파일을 복사하게 둡니다.

심링크보다 복사 설치를 권장하는 이유는, 맥북 여러 대와 맥 미니에 같은 설정을 깔 때 각 장비가 항상 표준 경로에 동일한 파일을 갖게 되어 덜 꼬이기 때문입니다.

- `~/bin/clean-ai-orphans.sh`
- `~/Library/LaunchAgents/com.leeth.clean-ai-orphans.plist`

## 설치

```bash
git clone https://github.com/maj0rika/mac-ai-orphan-cleaner.git
cd mac-ai-orphan-cleaner
./install.sh
```

더 공격적인 정리 모드로 설치하려면:

```bash
./install.sh --aggressive
```

설치가 끝나면 macOS는 아래처럼 동작합니다.

- 로그인 시점에 `RunAtLoad`로 한 번 실행
- 이후 `StartInterval` 기준으로 10분마다 반복 실행

## 사용법

수동 드라이런:

```bash
~/bin/clean-ai-orphans.sh --dry-run --verbose
```

수동 실행:

```bash
~/bin/clean-ai-orphans.sh
```

orphan `zsh`까지 포함해서 확인:

```bash
~/bin/clean-ai-orphans.sh --dry-run --verbose --include-shells
```

aggressive 모드 드라이런:

```bash
~/bin/clean-ai-orphans.sh --dry-run --verbose --aggressive
```

현재 aggressive 모드가 추가로 정리하는 대상은 아래와 같습니다.

- 오래 살아 있고 CPU 사용률은 낮지만 RSS 메모리는 큰 `Dia`의 `Browser Helper (Renderer)`

## 로그

```bash
tail -f ~/Library/Logs/clean-ai-orphans.log
```

## launchd 상태 확인

```bash
launchctl print gui/$(id -u)/com.leeth.clean-ai-orphans
```

즉시 한 번 실행:

```bash
launchctl kickstart -k gui/$(id -u)/com.leeth.clean-ai-orphans
```

## 제거

```bash
./uninstall.sh
```

제거 시 복사된 스크립트와 LaunchAgent는 삭제되지만, 로그 파일은 남겨 둡니다.
