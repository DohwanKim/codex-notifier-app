# Codex Notifier

Codex notify payload를 받아 이벤트를 분류하고 macOS, Telegram, Teams로 라우팅하는 macOS 메뉴바 앱입니다.

## 주요 기능

- Codex CLI `notify` payload를 helper로 받아 메뉴바 앱에 전달합니다.
- 이벤트를 작업 완료, 사용자 입력 필요, 실패로 분류합니다.
- 채널별 `사용하기`를 켠 뒤 이벤트 라우팅을 조정할 수 있습니다.
- 채널별로 전체 assistant 메시지, 폴더명, Git 브랜치 포함 여부를 켜고 끌 수 있습니다.
- Telegram Bot Token, Telegram Chat ID, Teams Workflow Webhook URL은 macOS Keychain에 저장합니다.
- 최근 처리 내역과 실패 로그를 앱 설정 화면에서 확인할 수 있습니다.

## 요구 사항

- macOS 13 이상
- Swift 6.0 이상
- Codex CLI

## 빠른 시작

```bash
make test
make app
```

생성된 앱은 `build/Codex Notifier.app`에 있습니다. `/Applications`에 설치하려면 다음을 실행합니다.

```bash
make install
```

설치 후 `/Applications/Codex Notifier.app`를 실행하면 메뉴바에 Codex Notifier가 표시됩니다.

## Codex 연결

설치 후 앱을 실행하고 메뉴바 `설정` → `Codex` → `자동 설정`을 누릅니다.
앱은 `/Applications/Codex Notifier.app` 안의 helper를 기준으로 `~/.codex/config.toml`을 설정합니다.

자동 설정은 다음 순서로 동작합니다.

- `~/.codex/config.toml`을 백업합니다.
- 기존 `notify`가 없으면 Codex Notifier helper를 등록합니다.
- 기존 `notify`가 있으면 덮어쓰지 않고 `--previous-notify`로 보존합니다.
- 이미 helper가 등록되어 있으면 중복 추가하지 않습니다.

수동으로 설정해야 하는 경우 Codex `config.toml`의 `notify`를 helper로 지정합니다.

```toml
notify = ["/Applications/Codex Notifier.app/Contents/MacOS/codex-notifier-helper"]
```

개발 중에는 번들 경로를 직접 사용할 수 있습니다. 이 경로는 앱을 옮기면 깨지므로 일반 사용자는 `/Applications` 설치를 권장합니다.

```toml
notify = ["/path/to/codex-cli-notify-app/build/Codex Notifier.app/Contents/MacOS/codex-notifier-helper"]
```

## 알림 라우팅

신규 설치의 기본 라우팅은 모든 채널이 꺼진 상태입니다.
각 채널 탭에서 `사용하기`를 켜면 다음 추천 라우팅이 적용됩니다.

| 이벤트 | 추천 채널 |
| --- | --- |
| 작업 완료 | Telegram, Teams |
| 사용자 입력 필요 | macOS |
| 실패 | macOS, Teams |

설정 화면의 각 채널 탭에서 채널 사용 여부, 이벤트 라우팅, 메시지 구성을 조정할 수 있습니다.
사용하지 않는 채널은 비밀값이나 권한을 설정하지 않아도 됩니다.
마무리 메시지/폴더명/브랜치 포함 옵션은 기본값이 모두 꺼져 있습니다.

## 동작 구조

- helper는 argv 또는 stdin의 Codex JSON payload를 `~/Library/Application Support/Codex Notifier/inbox`에 저장합니다.
- helper는 `open -a "Codex Notifier"`로 앱 실행을 보장하고 DistributedNotification 신호를 보냅니다.
- 메뉴바 앱은 시작 시와 신호 수신 시 inbox를 스캔해 payload를 처리합니다.
- 처리 완료 파일은 삭제하고, 처리 실패 파일은 `inbox/failed`로 이동합니다.

## 설정

메뉴바의 `설정`에서 각 채널 탭을 열어 다음 값을 입력하거나 조정합니다.

- Telegram Bot Token
- Telegram Chat ID
- Teams Workflow Webhook URL
- 채널별 사용 여부
- 이벤트별 macOS / Telegram / Teams 라우팅
- 채널별 마무리 메시지 / 폴더명 / Git 브랜치 포함 여부
- Telegram / Teams timeout

비밀값은 macOS Keychain에 저장됩니다. 앱 설정과 최근 히스토리/실패 로그는 UserDefaults에 저장됩니다.

## 공개 저장소 보안 메모

이 저장소에는 실제 Telegram Bot Token, Telegram Chat ID, Teams Workflow Webhook URL을 커밋하지 않습니다.
런타임 비밀값은 앱 설정 화면에서 입력하고 macOS Keychain에 저장하는 흐름을 사용합니다.

## 개발 검증

helper만 검증하려면 앱 실행을 건너뛰고 임시 Application Support 경로를 지정할 수 있습니다.

```bash
tmpdir="$(mktemp -d)"
CODEX_NOTIFIER_SKIP_OPEN=1 \
CODEX_NOTIFIER_APP_SUPPORT="$tmpdir" \
swift run codex-notifier-helper '{"type":"approval-requested"}'
find "$tmpdir" -type f
```

전체 검증은 다음 명령으로 실행합니다.

```bash
make test
```
