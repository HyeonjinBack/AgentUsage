# 릴리스

현재 배포 대상은 Apple Silicon, macOS 14 이상입니다. 앱 파일 이름은 AgentMeter이며 저장소와 다운로드 패키지 이름은 AgentUsage입니다.

GitHub에 로그인한 터미널에서 전체 공개 절차를 실행하려면 `bash Scripts/publish.sh`를 사용합니다. 개인정보 검사를 통과한 지정 파일만 별도 체크아웃에 복사하고, 공개 noreply 이메일로 커밋한 뒤 소스와 릴리스를 업로드합니다. 기존 릴리스는 덮어쓰지 않습니다.

```sh
swift test
bash Scripts/build-app.sh
python3 Scripts/package-release.py
python3 Scripts/privacy-audit.py
```

생성 파일은 `dist/release/AgentUsage-macos-arm64.zip`, `install.sh`, `SHA256SUMS`입니다. 소스 저장소에는 빌드 산출물·로그인 파일을 커밋하지 않습니다.

```sh
gh release create v0.2.0 dist/release/AgentUsage-macos-arm64.zip dist/release/install.sh dist/release/SHA256SUMS --title 'AgentUsage v0.2.0' --notes-file RELEASE_NOTES.md
```

현재 버전은 ad-hoc 서명이고 Apple 공증이 없습니다. 최초 실행이 macOS 보안 정책에 의해 차단될 수 있습니다. 설치 스크립트는 Gatekeeper를 끄거나 quarantine 속성을 제거하지 않습니다. Developer ID 서명·공증 자동화는 후속 작업입니다.

설치는 기본적으로 `~/Applications/AgentMeter.app`에 수행하며 기존 버전은 백업합니다. 설치 후 자동 실행하지 않습니다. 개발 중 다운로드 없이 검증하려면 `AGENTUSAGE_INSTALL_DIR=/tmp/agentusage-test bash install.sh --local-release dist/release`를 사용합니다.
