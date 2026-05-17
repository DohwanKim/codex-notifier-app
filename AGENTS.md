## Codex Notifier 작업 지침

- 이 디렉터리는 SwiftPM 기반 macOS 메뉴바 앱이다.
- 앱 소스(`Sources/`), 테스트(`Tests/`), 패키징(`packaging/`, `scripts/`, `Makefile`)을 수정한 뒤에는 `make test`를 실행한다.
- 앱 실행 결과에 영향을 주는 변경을 했다면 `make app`까지 실행해서 `build/Codex Notifier.app` 번들에 새 바이너리를 반영한다.
- `/Applications/Codex Notifier.app`가 설치되어 있거나 사용자가 실제 설치 앱 반영을 기대하는 흐름이면 `make install`까지 실행한다. 사용자가 명시적으로 설치를 원하지 않는 경우에만 생략한다.
- `make install` 후에는 다음을 확인한다.
  - `/Applications/Codex Notifier.app/Contents/MacOS/Codex Notifier`의 수정 시간이 최신인지 확인한다.
  - `/Applications/Codex Notifier.app/Contents/MacOS/codex-notifier-helper`의 수정 시간이 최신인지 확인한다.
  - `codesign --verify --deep --strict --verbose=2 "/Applications/Codex Notifier.app"`가 통과하는지 확인한다.
- 최종 응답에는 소스 검증(`make test`)과 앱 반영 여부(`make app` 또는 `make install`)를 구분해서 보고한다.
