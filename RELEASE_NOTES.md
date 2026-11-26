AgentUsage v0.2.8

Codex·Claude 잔여 한도와 Mac 상태를 함께 보여주는 메뉴 막대 앱입니다.

- 설정의 **한도 조회 서비스**에서 Codex와 Claude Code를 각각 켜고 끌 수 있습니다.
- 서비스를 끄면 메뉴 막대와 팝업에서 숨겨지고, 진행 중인 조회를 취소합니다. 이후 자동·수동 새로고침에서도 제외됩니다.
- 서비스 선택은 앱을 다시 열어도 유지됩니다.

Apple Silicon / macOS 14 이상을 지원합니다. 설치되는 앱 이름은 AgentMeter입니다. 이 빌드는 ad-hoc 서명이며 Apple 공증이 없습니다. Claude 키체인 허용 창과 일부 계정 연결에는 기기별 추가 확인이 필요할 수 있습니다.

설치:

```sh
curl -fL https://github.com/HyeonjinBack/AgentUsage/releases/latest/download/install.sh -o /tmp/agentusage-install.sh
bash /tmp/agentusage-install.sh
open "$HOME/Applications/AgentMeter.app"
```

개인정보 검사에서 개인 홈 경로·인증 토큰·개인 키가 발견되지 않았습니다. 실제 로그인 파일·계정 데이터·로컬 설정은 배포 파일에 포함하지 않습니다.
