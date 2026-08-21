# QuotaBar

**Claude와 Codex OAuth 구독 사용량을 한눈에 보는 macOS 메뉴바 앱**

여러 계정의 제한을 계정별 또는 제한 종류별로 비교하고, 별칭과 이메일 표시 정책까지 직접 관리합니다.

[한국어](README.ko.md) · [English](README.md) · [日本語](README.ja.md) · [简体中文](README.zh-CN.md) · [Español](README.es.md)

<p>
  <a href="https://github.com/Supia7/quota-bar"><img src="https://img.shields.io/badge/platform-macOS%2026%2B-black?logo=apple" alt="macOS 26+"></a>
  <a href="https://github.com/Supia7/quota-bar"><img src="https://img.shields.io/badge/Swift-6.2%2B-orange?logo=swift" alt="Swift 6.2+"></a>
  <a href="https://github.com/Supia7/quota-bar"><img src="https://img.shields.io/badge/auth-OAuth%20only-6f42c1" alt="OAuth only"></a>
</p>

> **현재 상태:** 초기 공개 버전입니다. Claude/Codex 사용량 endpoint는 공식 공개 billing API가 아니라 각 coding client가 사용하는 내부 endpoint이므로, provider 변경에 대비한 명시적 오류 처리를 포함합니다.

## 화면

> 아래 화면은 credential을 연결하지 않은 **샘플 데이터**입니다. 실제 토큰이나 계정정보는 포함되어 있지 않습니다.

<table>
  <tr>
    <td width="50%"><img src="docs/images/quotabar-accounts.png" alt="Accounts view showing Claude and Codex accounts"></td>
    <td width="50%"><img src="docs/images/quotabar-limit-types.png" alt="Limit types view grouping five-hour, weekly, and Fable limits"></td>
  </tr>
  <tr>
    <td align="center"><sub>계정 중심 보기</sub></td>
    <td align="center"><sub>제한 종류 중심 보기</sub></td>
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

QuotaBar는 앱 시작 시와 6시간마다 GitHub Releases를 확인합니다. 새 버전이 있으면 Monitor와 Settings에 release 링크를 보여줍니다. 사용자가 release를 확인하고 DMG를 설치하며, token·CLI·무인 실행 파일 교체는 하지 않습니다.

현재 build는 ad-hoc 서명 상태라 무인 교체를 의도적으로 활성화하지 않았습니다. 정식 다음 단계는 Developer ID 서명, Apple notarization, HTTPS appcast, 저장소 외부 Ed25519 key와 Sparkle 2.9.6 구성입니다.

### 요구사항

- macOS 26+
- Swift 6.2+
- Claude Code 또는 Codex가 관리하는 OAuth credential JSON

### 빌드 및 실행

```bash
swift run QuotaBarChecks
swift build --product QuotaBar
swift build --product QuotaBarPreview
swift run QuotaBar
```

`QuotaBarPreview`는 동일한 Monitor UI를 일반 창에서 확인하기 위한 개발용 target입니다.

### 계정 연결

앱의 Settings에서 `Add OAuth account`를 선택하면 provider 기본 credential 경로를 자동으로 찾습니다.

- Claude: `~/.claude/.credentials.json`
- Codex: `~/.codex/auth.json`

파일이 있으면 JSON을 직접 선택하지 않아도 버튼이 활성화됩니다. 다른 위치에 credential을 둔 경우에만 `Choose JSON…`을 사용하면 됩니다.

| Provider | 기본 credential 파일 |
| --- | --- |
| Claude | `~/.claude/.credentials.json` |
| Codex | `~/.codex/auth.json` |

QuotaBar는 파일 경로와 표시 설정만 저장합니다. access token과 refresh token을 QuotaBar의 JSON 파일로 복사하지 않으며, 토큰 입력란도 제공하지 않습니다.

## 보안 경계

- OAuth 전용 — API key billing 데이터를 구독 quota로 취급하지 않음
- credential은 provider-managed 파일에서 refresh 시점에 읽음
- QuotaBar 자체 저장소에는 token 값이 들어가지 않음
- Claude와 Codex 각각 고정된 HTTPS host/path만 허용
- HTTP redirect는 거부
- Claude Web cookie scraping 없음
- 외부 CLI 실행 없음
- telemetry와 analytics 없음
- 5분마다 자동 refresh
- 수동 Refresh는 즉시 snapshot 요청
- refresh 실패 시 마지막으로 확인한 화면을 유지
- token 만료 시 조용히 CLI를 실행하지 않고 재인증 필요 상태로 처리

> Claude OAuth usage endpoint와 Codex subscription usage endpoint는 공개 안정 API가 아닙니다. endpoint schema나 rate limit 정책이 바뀌면 QuotaBar는 추정값 대신 명시적 오류를 보여줍니다.

## 저장 데이터

| 위치 | 내용 |
| --- | --- |
| `~/Library/Application Support/QuotaBar/accounts.json` | provider, alias, email, email visibility, credential path |
| `~/Library/Application Support/QuotaBar/display-preferences.json` | 계정별 alias/email 표시 설정 |

저장 파일에는 OAuth access/refresh token을 기록하지 않습니다.

## 개발자 안내

```text
Sources/QuotaBarCore/       도메인 모델, decoder, credential boundary, provider client
Sources/QuotaBarUI/         메뉴바 UI, 두 view mode, polling, account editor
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

- provider-managed Keychain credential fallback
- Claude/Codex profile endpoint 기반 이메일 자동 조회
- 계정별 stale / re-auth 상태 카드
- OAuth token rotation과 provider 공식 인증 흐름 검토
- full Xcode test target 및 signed/notarized release pipeline

## 라이선스

QuotaBar는 [MIT License](LICENSE)로 배포됩니다. 상업적 사용, 수정, 재배포, fork를 허용하며 저작권 및 라이선스 고지를 유지해야 합니다.

## 저장소

- GitHub: <https://github.com/Supia7/quota-bar>
- 계획: [`docs/2026-08-21-multi-account-oauth-plan.md`](docs/2026-08-21-multi-account-oauth-plan.md)
- 요구사항: [`docs/2026-08-21-multi-account-oauth-requirements.md`](docs/2026-08-21-multi-account-oauth-requirements.md)
