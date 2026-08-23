# QuotaBar

**Claude와 Codex OAuth 구독 사용량을 한눈에 보는 macOS 메뉴바 앱**

여러 계정의 제한을 계정별 또는 제한 종류별로 비교하고, 별칭과 이메일 표시 정책까지 직접 관리합니다.

[한국어](README.ko.md) · [English](README.md) · [日本語](README.ja.md) · [简体中文](README.zh-CN.md) · [Español](README.es.md)

<p>
  <a href="https://github.com/Supia7/quota-bar"><img src="https://img.shields.io/badge/platform-macOS%2026%2B-black?logo=apple" alt="macOS 26+"></a>
  <a href="https://github.com/Supia7/quota-bar"><img src="https://img.shields.io/badge/Swift-6.2%2B-orange?logo=swift" alt="Swift 6.2+"></a>
  <a href="https://github.com/Supia7/quota-bar"><img src="https://img.shields.io/badge/auth-OAuth%20only-6f42c1" alt="OAuth only"></a>
</p>

<p>
  <img src="docs/images/quotabar-logo.png" width="96" alt="QuotaBar 마스코트 로고">
</p>

> **현재 상태:** 초기 공개 버전입니다. Claude/Codex 사용량 endpoint는 공식 공개 billing API가 아니라 각 coding client가 사용하는 내부 endpoint이므로, provider 변경에 대비한 명시적 오류 처리를 포함합니다.

## 화면

> 아래 화면은 `QuotaBarPreview` 전용 fixture로 만든 예시입니다. 실제 앱을 새로 설치하면 예시 계정이 아니라 빈 상태가 표시됩니다.

<table>
  <tr>
    <td width="33%"><img src="docs/images/quotabar-accounts.png" alt="Claude와 Codex 계정을 한 줄씩 표시하는 compact 계정 보기"></td>
    <td width="33%"><img src="docs/images/quotabar-limit-types.png" alt="5시간·Weekly·Fable 제한별 한 줄 계정 요약 보기"></td>
    <td width="33%"><img src="docs/images/quotabar-settings.png" alt="브라우저 OAuth 로그인과 Keychain 전용 보안을 보여주는 Settings 보기"></td>
  </tr>
  <tr>
    <td align="center"><sub>Compact 계정 보기</sub></td>
    <td align="center"><sub>Compact 제한 종류 보기</sub></td>
    <td align="center"><sub>Settings·OAuth 보기</sub></td>
  </tr>
</table>

## 무엇을 보여주나요?

### Claude

- 5시간 rolling window
- 전체 모델 Weekly 제한
- Fable/model-scoped Weekly 제한
- Fable 데이터가 provider 응답에 없으면 0%로 추정하지 않고 `Unavailable` 표시

### Codex

- OAuth 구독 Weekly 제한
- reset 시각과 잔여 비율

### 계정 관리

- 계정 수 제한 없음
- 계정별 고정 UUID로 관리 — 이메일이 같아도 별도 계정으로 유지
- 계정 별칭 편집
- provider 이메일 표시 또는 숨김
- `Accounts` / `Limit types` 뷰 전환
- 계정별 한 줄 요약과 펼쳐볼 수 있는 quota 상세
- 선택한 뷰는 로컬에 기억

## 설치 방법

### 일반 사용자 — DMG 권장

1. [Releases](https://github.com/Supia7/quota-bar/releases/latest)에서 `QuotaBar-macos-arm64.dmg`를 다운로드합니다.
2. DMG를 열고 `QuotaBar.app`을 `Applications`로 드래그합니다.
3. 처음 실행할 때 macOS 경고가 나오면 앱을 우클릭한 뒤 **열기**를 선택합니다.

현재 release artifact는 ad-hoc 서명 상태입니다. Apple Developer ID 서명과 notarization을 추가하기 전까지는 Gatekeeper에서 개발자 확인을 요청할 수 있습니다.

### 터미널 — 최신 release 자동 설치

저장소를 clone한 뒤 아래 한 줄을 실행하면 현재 Mac 아키텍처에 맞는 release를 다운로드하고 checksum을 확인한 뒤 `~/Applications`에 설치합니다.

```bash
./Scripts/install-release.sh
```

### 개발자 — 소스에서 빌드 및 설치

```bash
./Scripts/install.sh
```

위 명령은 release 빌드, `.app` bundle 생성, ad-hoc 서명, `~/Applications/QuotaBar.app` 복사, 실행까지 처리합니다.

### 업데이트

QuotaBar는 실행 시와 6시간마다 GitHub Releases를 확인합니다. v0.1.8부터는 Sparkle이 서명된 HTTPS appcast와 update archive를 검증한 뒤 업데이트를 제안합니다. 업데이트는 여전히 사용자가 승인해야 하며, QuotaBar가 실행 파일을 조용히 교체하지 않습니다.

v0.1.7은 Sparkle 도입 전 버전이므로 v0.1.7 사용자는 DMG로 v0.1.8을 한 번 수동 설치해야 합니다. v0.1.9에는 앱 내부 OAuth 로그인이, v0.1.10에는 설치 경로 guard와 로고가, v0.1.14에는 Codex loopback callback 자동 완료가 추가되었습니다.

### 요구사항

- macOS 26+
- Swift 6.2+
- Claude 및 Codex 브라우저 OAuth 로그인

### 빌드 및 실행

```bash
swift run QuotaBarChecks
swift build --product QuotaBar
swift build --product QuotaBarPreview
swift run QuotaBar
```

`QuotaBarPreview`는 동일한 Monitor UI를 일반 창에서 확인하기 위한 개발용 target입니다.

### 계정 연결

앱의 Settings에서 `Sign in with Claude` 또는 `Sign in with Codex`를 선택하면 브라우저 OAuth 로그인이 시작됩니다. Codex는 등록된 `http://localhost:1455/auth/callback` loopback redirect를 사용하므로 승인 후 보통 QuotaBar가 자동으로 완료합니다. Claude는 현재 고정 HTTPS callback을 사용하므로 전체 callback URL 또는 일회용 authorization code를 QuotaBar에 붙여 넣어야 합니다. Codex도 로컬 callback port를 사용할 수 없으면 paste 입력으로 fallback합니다. access/refresh token을 붙여 넣으면 안 됩니다. QuotaBar는 code를 교환한 뒤 실제 quota 응답을 한 번 검증하고, 성공한 경우에만 access/refresh token을 macOS Keychain에 저장합니다.

## 보안 경계

- 새 OAuth token은 `accounts.json`이 아니라 macOS Keychain에 저장
- account registry에는 provider, alias, email, Keychain source와 deduplication metadata만 저장
- Keychain credential은 provider token endpoint를 통해 앱이 직접 refresh
- 기존 CLI credential JSON은 가져오지 않음
- OAuth 전용 — API key billing 데이터를 구독 quota로 취급하지 않음
- Claude/Codex authorize·token·usage endpoint는 고정 HTTPS 정책으로 제한
- HTTP redirect는 거부
- Claude Web cookie scraping 없음
- 외부 CLI 실행 없음
- telemetry와 analytics 없음
- 5분마다 자동 refresh
- 수동 Refresh는 즉시 snapshot 요청
- refresh 실패 시 마지막으로 확인한 화면을 유지
- token 만료·폐기 시 재인증 필요 상태로 표시

> Claude OAuth usage endpoint와 Codex subscription usage endpoint는 공개 안정 API가 아닙니다. endpoint schema나 rate limit 정책이 바뀌면 QuotaBar는 추정값 대신 명시적 오류를 보여줍니다.

## 저장 데이터

| 위치 | 내용 |
| --- | --- |
| `~/Library/Application Support/QuotaBar/accounts.json` | provider, alias, email, Keychain source, deduplication identity |
| macOS Keychain (`com.supia.quotabar.oauth`) | in-app OAuth access/refresh token |
| `~/Library/Application Support/QuotaBar/display-preferences.json` | 계정별 alias/email 표시 설정 |

저장 파일에는 OAuth access/refresh token을 기록하지 않습니다.

## 개발자 안내

```text
Sources/QuotaBarCore/       도메인 모델, decoder, credential boundary, provider client
Sources/QuotaBarUI/         메뉴바 UI, 5개 언어 리소스, compact view, polling, account editor
Sources/QuotaBar/            메뉴바 앱 entry point
Sources/QuotaBarPreview/     일반 창 Preview entry point
Sources/QuotaBarChecks/      framework-free self-check
```

검증 명령:

```bash
swift run QuotaBarChecks
swift build --product QuotaBar
swift build --product QuotaBarPreview
git diff --check
```

현재 Command Line Tools 환경에서는 XCTest/Testing 모듈을 사용할 수 없어 framework-free self-check executable을 사용합니다.

## 다음 단계

- provider 정책이 허용하는 경우 manual callback paste 대신 native callback 처리
- Claude/Codex profile endpoint 기반 이메일 자동 조회
- 계정별 stale / re-auth 상태 카드
- provider token rotation·폐기 시나리오 테스트 확대
- full Xcode test target 및 signed/notarized release hardening 지속

## 라이선스

QuotaBar는 [MIT License](LICENSE)로 배포됩니다. 상업적 사용, 수정, 재배포, fork를 허용하며 저작권 및 라이선스 고지를 유지해야 합니다.

## 저장소

- GitHub: <https://github.com/Supia7/quota-bar>
- 계획: [`docs/2026-08-21-multi-account-oauth-plan.md`](docs/2026-08-21-multi-account-oauth-plan.md)
- 요구사항: [`docs/2026-08-21-multi-account-oauth-requirements.md`](docs/2026-08-21-multi-account-oauth-requirements.md)
