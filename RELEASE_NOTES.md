Codex·Claude 잔여 한도와 Mac 상태를 함께 보여주는 AgentUsage v0.2.2입니다.

변경 사항:
- 상단 바에 CPU 사용률과 메모리 사용 용량을 추가했습니다. 수치는 위, 얇은 게이지는 아래에 표시합니다.
- 시스템 사용률이 80% 이상이면 해당 게이지만 빨간색으로 바뀝니다.
- 기존 Codex·Claude의 세션/주간 잔여량 배치와 갱신 주기를 유지합니다.
- Claude 연결 버튼과 키체인 오류 번호를 추가하고, 자동·일반 새로고침에서 키체인 반복 접근을 제거했습니다.
- 설정 화면에서 앱 버전을 확인할 수 있습니다.

Apple Silicon / macOS 14 이상을 지원합니다. 설치되는 앱 이름은 AgentMeter입니다. 이 빌드는 ad-hoc 서명이며 Apple 공증이 없습니다. Claude 키체인 허용 창과 일부 계정 연결에는 기기별 추가 확인이 필요할 수 있습니다.

설치:

```sh
curl -fL https://github.com/HyeonjinBack/AgentUsage/releases/latest/download/install.sh -o /tmp/agentusage-install.sh
bash /tmp/agentusage-install.sh
open "$HOME/Applications/AgentMeter.app"
```

개인정보 검사에서 개인 홈 경로·인증 토큰·개인 키가 발견되지 않았습니다. 실제 로그인 파일·계정 데이터·로컬 설정은 배포 파일에 포함하지 않습니다.
