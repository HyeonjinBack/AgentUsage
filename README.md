# AgentUsage

Codex·Claude의 **지금 남은 5시간·주간 한도**와 **리셋까지 남은 시간**을 보여주는 개인용 macOS 메뉴 막대 앱입니다. CPU·메모리·배터리는 하단의 보조 지표입니다.

## 독립 연결

외부 모니터 앱이나 CLI를 실행하지 않고, Swift `URLSession`으로 각 서비스에 직접 GET 요청을 보냅니다. 자체 코드 외의 런타임 의존성은 없습니다. 기존 Codex·Claude Code 구독 로그인 정보를 사용합니다.

| 도구 | 기존 로그인 정보 | 조회 대상 |
|---|---|---|
| Codex | `CODEX_HOME/auth.json` (기본 `~/.codex/auth.json`) | `https://chatgpt.com/backend-api/wham/usage` |
| Claude | 기본 프로필의 macOS 키체인 `Claude Code-credentials`, 없는 경우 `.credentials.json` | `https://api.anthropic.com/api/oauth/usage` |

이 경로는 앱/CLI 호환을 위한 서비스 내부 엔드포인트이며 안정적인 공개 API 계약이 아닙니다. 서비스 변경 시 연결 코드를 수정해야 할 수 있습니다. 새 OAuth 계정을 생성하는 앱은 아니며, 먼저 Codex·Claude Code에 로그인한 상태여야 합니다. 로그인 캐시만 읽으므로 설치된 CLI 실행 파일은 필요 없습니다.

현재 Codex는 파일 기반 ChatGPT 로그인만 지원하며 키체인 전용 저장 모드는 지원하지 않습니다. Claude 사용자 지정 폴더는 그 폴더의 `.credentials.json`만 읽고 기본 프로필의 키체인으로 대체하지 않습니다. API 키·추론 전용 토큰은 구독 한도 조회에 사용하지 않습니다.

## 터미널에서 설치

현재 다운로드 대상은 **Apple Silicon Mac / macOS 14 이상**입니다.

```sh
curl -fL https://github.com/HyeonjinBack/AgentUsage/releases/latest/download/install.sh -o /tmp/agentusage-install.sh
bash /tmp/agentusage-install.sh
open "$HOME/Applications/AgentMeter.app"
```

설치 스크립트는 릴리스 ZIP의 SHA-256을 확인하고 `~/Applications/AgentMeter.app`에 설치합니다. 기존 버전은 백업합니다. 현재는 Apple 공증이 없는 미리보기 버전이므로 macOS가 첫 실행을 차단할 수 있습니다. 스크립트는 macOS 보안 설정을 바꾸지 않습니다.

## 빌드·실행

macOS 14 이상, Swift 6 지원 Xcode가 필요합니다. 현재 빌드·시스템 지표 검증 환경은 Apple Silicon / macOS 27입니다.

```sh
swift test
bash Scripts/build-app.sh
open dist/AgentMeter.app
```

메뉴 막대의 OpenAI·Claude 아이콘을 눌러 **한도 확인 시작**을 선택하세요. Claude 로그인 정보를 읽기 위해 macOS 키체인 확인 창이 나타나면 AgentMeter의 접근을 직접 허용하세요. 연결 시 한 번 읽은 Claude 인증정보는 앱 메모리에만 보관합니다. 자동 조회와 일반 새로고침은 기본 프로필의 키체인을 호출하지 않습니다. 만료·접근 거부 시 설정의 연결 버튼에서만 다시 읽습니다. 앱을 다시 시작하면 Claude 카드의 **Claude 연결 / 인증 다시 읽기**를 한 번 눌러 주세요. 아직 연결하지 않은 상태와 실제 키체인 읽기 실패를 별도로 표시합니다.

설정에서 로그인 폴더 변경·연결 해제가 가능합니다. 로그인이 만료되면 해당 도구에서 로그인 정보를 갱신한 뒤 새로고침하세요. 이 앱은 기존 로그인 파일이나 키체인을 수정하지 않습니다.

## 표시 규칙

- 3분마다 갱신, 수동 새로고침, 일시 중지.
- 리셋까지 남은 시간은 1분마다 다시 계산합니다. 서버 요청은 추가하지 않습니다. 시스템 지표는 별도 화면 모델에서 5초마다 갱신합니다.
- 메뉴 막대는 `OpenAI 아이콘 [위: 세션 / 아래: 주간] / Claude 아이콘 [위: 세션 / 아래: 주간]` 순서로 각 잔여 퍼센트를 표시합니다.
- CPU·Mem은 수치 위/게이지 아래로 표시하며 시스템 사용률이 80% 이상이면 해당 게이지만 빨간색으로 바뀝니다. 메모리 게이지는 사용 중인 용량/전체 용량 비율입니다.
- 제공된 사용 비율을 `100 - 사용 비율`로 계산합니다. 토큰·비용·대화 길이로 추측하지 않습니다.
- 누락된 한도는 없는 상태로 유지하며 0%나 100%로 만들지 않습니다.
- 조회 실패·10분 이상 지난 값은 메뉴 막대에서 `—`, 상세 화면에서 이전 값으로 표시합니다. 로그인·권한 오류에서는 이전 계정의 수치를 지웁니다.
- 리셋 시각이 지나면 갱신을 요청합니다. 리셋 완료를 가정하지 않습니다.
- HTTP 429는 재시도 간격을 늘립니다. 로그인 만료·권한 거부·네트워크·서버 오류를 구분합니다.

## 개인정보

인증 토큰은 메모리에서 요청의 Authorization 헤더로만 사용합니다. 인증·응답 원문을 로그·DB·내보내기에 기록하지 않습니다. 세션 쿠키·URL 캐시·인증 캐시를 사용하지 않으며 리다이렉트를 거부합니다. 토큰 갱신이나 원본 자격증명 수정을 하지 않습니다.

한도·시스템 값은 메모리에만 유지합니다. 로그인 폴더와 연결 시작 여부만 UserDefaults에 저장합니다. 연결 해제 후 자동 수집을 중단하며 진행 중인 요청 결과는 화면에 적용하지 않습니다.

## 개발·검증

```sh
swift run agentmeter-cli system
swift run agentmeter-cli codex
swift run agentmeter-cli claude
# 사용자가 직접 요청하는 키체인 확인 창을 허용할 때만:
swift run agentmeter-cli claude --allow-keychain-prompt
```

`Sources/AgentMeterCore`는 인증 읽기·직접 HTTP 연결·응답 해석·시스템 지표, `Sources/AgentMeter`는 화면입니다. 테스트는 실제 자격증명이나 네트워크를 사용하지 않습니다.

개발 환경의 실제 호출은 Codex 네트워크 오류와 Claude 키체인 접근 제한을 반환했습니다. 따라서 코드·합성 테스트 성공과 실제 계정 수치 확인은 구분합니다. 현재 앱은 로컬 ad-hoc 서명 버전이며 공개 배포용 Developer ID 서명·공증은 후속 작업입니다.

## 참고

- [OpenAI 로그인 정보 저장 안내](https://learn.chatgpt.com/docs/auth)
- [Claude Code 인증과 키체인 안내](https://code.claude.com/docs/en/authentication)
- [Codex 공식 한도 조회 프로토콜](https://learn.chatgpt.com/docs/app-server) — 직접 HTTP와 별개의 공식 App Server 인터페이스입니다.

MIT License.

아이콘: [Lobe Icons](https://github.com/lobehub/lobe-icons), MIT. 라이선스 원문은 앱 리소스의 `LobeIcons-LICENSE.txt`에 포함됩니다. 제공자 식별을 위한 아이콘이며 제휴를 의미하지 않습니다.
