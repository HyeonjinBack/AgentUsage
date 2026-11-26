AgentUsage v0.2.7

Codex·Claude 잔여 한도와 Mac 상태를 함께 보여주는 메뉴 막대 앱입니다.

- 팝업 하단에 최근 한도 조회 시각과 배터리 잔량을 나란히 표시합니다.
- 새로고침과 일시 중지·재개를 별도 버튼으로 배치하고, 설정과 종료를 `…` 메뉴에 모았습니다.
- CPU와 메모리 사용량은 메뉴 막대에서 확인할 수 있습니다.

Apple Silicon / macOS 14 이상을 지원합니다. 설치되는 앱 이름은 AgentMeter입니다. 이 빌드는 ad-hoc 서명이며 Apple 공증이 없습니다. Claude 키체인 허용 창과 일부 계정 연결에는 기기별 추가 확인이 필요할 수 있습니다.

설치:

```sh
curl -fL https://github.com/HyeonjinBack/AgentUsage/releases/latest/download/install.sh -o /tmp/agentusage-install.sh
bash /tmp/agentusage-install.sh
open "$HOME/Applications/AgentMeter.app"
```

개인정보 검사에서 개인 홈 경로·인증 토큰·개인 키가 발견되지 않았습니다. 실제 로그인 파일·계정 데이터·로컬 설정은 배포 파일에 포함하지 않습니다.
