# QuotaBar

**Claude와 Codex OAuth quota를 한눈에 보는 컴팩트한 macOS 메뉴바 앱**

전체 대시보드를 열지 않고 메뉴바에서 여러 계정의 구독 quota와 초기화 시각을 확인합니다.

[한국어](README.ko.md) · [English](README.md) · [日本語](README.ja.md) · [简体中文](README.zh-CN.md) · [Español](README.es.md)

<p>
  <a href="https://github.com/Supia7/quota-bar"><img src="https://img.shields.io/badge/platform-macOS%2026%2B-black?logo=apple" alt="macOS 26+"></a>
  <a href="https://github.com/Supia7/quota-bar"><img src="https://img.shields.io/badge/Swift-6.2%2B-orange?logo=swift" alt="Swift 6.2+"></a>
  <a href="https://github.com/Supia7/quota-bar"><img src="https://img.shields.io/badge/auth-OAuth%20only-6f42c1" alt="OAuth only"></a>
</p>

<p align="center">
  <img src="docs/images/quotabar-accounts.png" width="420" alt="컴팩트한 QuotaBar 모니터 화면">
</p>

> QuotaBar는 Claude Code와 Codex가 사용하는 provider usage endpoint를 조회합니다. 공식 공개 billing API가 아니므로 provider 오류를 추정하지 않고 명시적으로 표시합니다.

## 핵심 기능

- **한눈에 보기:** 메뉴바에서 잔여량과 초기화 시각 확인
- **멀티 계정:** 계정별 또는 제한 종류별 비교
- **컴팩트 UI:** 중요한 숫자만 먼저 보여주고 상세 quota는 펼쳐서 확인
- **OAuth + Keychain:** 브라우저 로그인, token은 macOS Keychain에만 저장
- **초기화 감지:** 표시된 갱신일보다 이른 Codex reset도 감지
- **로컬 사용량:** 로컬 session log가 있으면 provider block 안에 오늘 token·session 수를 표시
- **로컬 우선:** telemetry, analytics, cookie scraping, API-key billing, 외부 CLI 실행 없음

## 표시 항목

| Provider | Quota window |
| --- | --- |
| Claude | 5시간 rolling, 전체 모델 weekly, Fable/model-scoped weekly |
| Codex | OAuth 구독 weekly quota와 초기화 시각 |

Provider가 특정 window를 반환하지 않으면 임의의 값을 만들지 않고 `Unavailable`로 표시합니다. 로컬 session log가 없으면 local usage 줄을 표시하지 않습니다.

## 시작하기

### Release 설치

1. [Releases](https://github.com/Supia7/quota-bar/releases/latest)에서 `QuotaBar-macos-arm64.dmg`를 받습니다.
2. `QuotaBar.app`을 `Applications`로 드래그합니다.
3. 앱을 열고 메뉴바 아이콘을 클릭합니다.
4. **Settings**에서 **Sign in with Claude** 또는 **Sign in with Codex**를 선택합니다.

Codex는 보통 localhost callback으로 자동 완료됩니다. Claude는 브라우저 승인 후 표시되는 전체 callback URL 또는 일회용 authorization code를 입력합니다. access/refresh token은 붙여넣지 마세요.

### 터미널 설치

```bash
./Scripts/install-release.sh
```

현재 아키텍처에 맞는 release를 다운로드하고 checksum을 확인한 뒤 `~/Applications`에 설치·실행합니다.

## 소스에서 빌드

요구사항: macOS 26+, Swift 6.2+.

```bash
./Scripts/install.sh
```

검사와 Preview 창만 실행하려면:

```bash
swift run QuotaBarChecks
swift build --product QuotaBar
swift build --product QuotaBarPreview
swift run QuotaBarPreview
```

`QuotaBarPreview`는 시각 검사용 fixture 계정을 사용합니다. 실제 앱은 OAuth 계정을 연결하기 전까지 빈 상태로 시작합니다.

## 보안과 로컬 데이터

- OAuth token은 QuotaBar Keychain service에 저장됩니다.
- `accounts.json`에는 provider, alias, email, Keychain identity 같은 metadata만 저장됩니다.
- 기존 CLI credential 파일은 가져오지 않습니다.
- 로컬 사용량은 오늘 날짜의 Claude/Codex JSONL session record만 읽으며 message 내용은 저장하거나 전송하지 않습니다.
- Claude/Codex 요청은 고정 HTTPS endpoint policy를 사용하고 redirect를 거부합니다.
- refresh 실패 시 마지막 정상 화면을 유지합니다.
- 5분마다 자동 refresh하며 하단 toolbar에서 수동 refresh할 수 있습니다.

로컬 metadata 위치:

```text
~/Library/Application Support/QuotaBar/
```

## 프로젝트 구조

```text
Sources/QuotaBarCore/    모델, OAuth, Keychain, provider decoder
Sources/QuotaBarUI/      컴팩트 monitor, Settings, localization
Sources/QuotaBar/        AppKit 메뉴바 host와 popover
Sources/QuotaBarPreview/ fixture 기반 visual QA 창
Sources/QuotaBarChecks/  framework-free self-check 실행 파일
```

로컬 사용량 요약은 [CodeBurn](https://github.com/getagentseal/codeburn)의 local analytics 방향을 참고한 독립 Swift 구현입니다. QuotaBar는 CodeBurn CLI를 번들하거나 실행하지 않습니다. 라이선스와 attribution은 [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md)에 기록했습니다.

## 검증

```bash
swift run QuotaBarChecks
swift build --product QuotaBar
swift build --product QuotaBarPreview
python3 Scripts/check-popover-layout.py
bash Scripts/check-menu-bar-host.sh
git diff --check
```

## 상태

초기 공개 버전입니다. Provider endpoint 또는 schema 변경에 따라 후속 업데이트가 필요할 수 있습니다.

## 라이선스

[MIT](LICENSE)

Repository: <https://github.com/Supia7/quota-bar>
