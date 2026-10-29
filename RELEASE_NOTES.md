Codex·Claude 구독의 5시간·주간 잔여 한도와 리셋 시간을 보여주는 macOS 메뉴 막대 앱입니다.

- 상단 메뉴 막대: 제공자 아이콘 옆 위쪽에 세션, 아래쪽에 주간 잔여 퍼센트.
- 한도 3분 조회, 리셋 시간 1분 갱신, 시스템 지표 5초 갱신.
- 직접 HTTP 연결, 기존 기기의 Codex·Claude Code 로그인 사용.
- Claude 인증정보는 연결 시 한 번 읽고 메모리에서 재사용. 자동·일반 새로고침에서 키체인 반복 접근 제거.
- Apple Silicon / macOS 14 이상. 설치 앱 이름은 AgentMeter입니다.
- 기존 사용자 설정·로그인 파일·계정 정보는 배포 파일에 포함하지 않습니다.

이 버전은 로컬 ad-hoc 서명이며 Apple 공증이 없습니다. 실시간 계정 조회는 개발 환경의 네트워크·키체인 제한으로 완전히 검증되지 않았습니다. Codex 파일 기반 ChatGPT 로그인과 Claude 기본 키체인/파일 로그인을 지원합니다.

설치:

```sh
curl -fL https://github.com/HyeonjinBack/AgentUsage/releases/latest/download/install.sh -o /tmp/agentusage-install.sh
bash /tmp/agentusage-install.sh
open "$HOME/Applications/AgentMeter.app"
```
