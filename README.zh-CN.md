# QuotaBar

**在 macOS 菜单栏中查看 Claude 和 Codex OAuth 订阅使用量。**

支持按账号或按限制类型比较多个账号，并可自行管理账号别名和邮箱显示策略。

[한국어](README.ko.md) · [English](README.md) · [日本語](README.ja.md) · [简体中文](README.zh-CN.md) · [Español](README.es.md)

<p>
  <a href="https://github.com/Supia7/quota-bar"><img src="https://img.shields.io/badge/platform-macOS%2026%2B-black?logo=apple" alt="macOS 26+"></a>
  <a href="https://github.com/Supia7/quota-bar"><img src="https://img.shields.io/badge/Swift-6.2%2B-orange?logo=swift" alt="Swift 6.2+"></a>
  <a href="https://github.com/Supia7/quota-bar"><img src="https://img.shields.io/badge/auth-OAuth%20only-6f42c1" alt="OAuth only"></a>
</p>

> **当前状态：** 初始公开版本。Claude 和 Codex 的使用量 endpoint 并不是稳定的公开 billing API，而是对应 coding client 使用的内部 endpoint。发生变化时，QuotaBar 会显示明确错误，而不会生成猜测值。

## 截图

> 以下截图使用的是没有连接 credential 的**示例数据**，不包含真实 token 或账号信息。

<table>
  <tr>
    <td width="50%"><img src="docs/images/quotabar-accounts.png" alt="Claude 和 Codex 的账号视图"></td>
    <td width="50%"><img src="docs/images/quotabar-limit-types.png" alt="按五小时、Weekly 和 Fable 限制类型分组的视图"></td>
  </tr>
  <tr>
    <td align="center"><sub>账号视图</sub></td>
    <td align="center"><sub>限制类型视图</sub></td>
  </tr>
</table>

## 可以查看什么？

### Claude

- 5 小时 rolling window
- 全模型 Weekly 限制
- Fable / model-scoped Weekly 限制
- 如果 provider 没有返回 Fable 数据，则显示 `Unavailable`，不会把它推测成 0%

### Codex

- OAuth 订阅 Weekly 限制
- 剩余比例和 reset 时间

### 账号管理

- 没有账号数量上限
- 使用固定 UUID 管理账号，即使邮箱相同也保持为独立账号
- 可编辑账号别名
- 可按账号显示或隐藏 provider 邮箱
- `Accounts` / `Limit types` 两种视图
- 视图选择会保存在本地

## 安装方式

### 普通用户 — 推荐使用 DMG

1. 从 [Releases](https://github.com/Supia7/quota-bar/releases/latest) 下载 `QuotaBar-macos-arm64.dmg`。
2. 打开 DMG，把 `QuotaBar.app` 拖到 `Applications`。
3. 第一次启动时，如果 macOS 显示警告，请右键点击应用并选择**打开**。

当前 release artifact 使用 ad-hoc 签名。在加入 Apple Developer ID 签名和 notarization 之前，Gatekeeper 可能会要求确认开发者。

### 终端 — 自动安装最新 release

clone 仓库后运行下面一条命令。它会下载当前 Mac 架构对应的 release，验证 checksum，然后安装到 `~/Applications`。

```bash
./Scripts/install-release.sh
```

### 开发者 — 从源码构建并安装

```bash
./Scripts/install.sh
```

该命令会构建 release、生成 `.app` bundle、进行 ad-hoc 签名、复制到 `~/Applications/QuotaBar.app` 并启动应用。

### 更新机制

QuotaBar 会在启动时和每 6 小时检查 GitHub Releases。从 v0.1.8 开始，Sparkle 会先验证已签名的 HTTPS appcast 和更新压缩包，再提供更新。更新仍需要用户确认；QuotaBar 不会静默替换可执行文件。

v0.1.7 发布时还没有 Sparkle，因此 v0.1.7 用户需要先从 DMG 手动安装一次 v0.1.8。v0.1.9 增加了应用内 OAuth 登录；之后的版本可以使用已签名的 Sparkle 更新路径。

### 环境要求

- macOS 26+
- Swift 6.2+
- 由 Claude Code 或 Codex 管理的 OAuth credential JSON

### 构建和运行

```bash
swift run QuotaBarChecks
swift build --product QuotaBar
swift build --product QuotaBarPreview
swift run QuotaBar
```

`QuotaBarPreview` 使用与菜单栏应用相同的 Monitor UI，以普通窗口提供开发和视觉检查。

### 连接账号

打开 Settings，选择 `Sign in with Claude` 或 `Sign in with Codex`，即可在浏览器中开始 OAuth 登录。完成授权后，将 callback URL 或 authorization code 粘贴回 QuotaBar。QuotaBar 会交换 code，先验证一次真实 quota 响应，成功后才把 access / refresh token 保存到 macOS Keychain。

已有 CLI 登录的用户可以使用 `Use existing credential file (fallback)`。

- Claude：`~/.claude/.credentials.json`
- Codex：`~/.codex/auth.json`

只有 credential 位于其他位置时才需要 JSON picker。

## 安全边界

- 新 OAuth token 保存在 macOS Keychain，而不是 `accounts.json`
- account registry 只保存 provider、alias、email、source 和去重 metadata
- Keychain credential 通过 provider token endpoint 由应用自行 refresh
- 已有 CLI credential file 作为兼容 fallback 保留
- 仅支持 OAuth，不把 API key billing 数据当作订阅 quota
- authorize、token、usage endpoint 受固定 HTTPS 策略限制
- 拒绝 HTTP redirect
- 不抓取 Claude Web cookie
- 不执行外部 CLI
- 没有 telemetry 或 analytics
- 每 5 分钟自动 refresh
- 手动 Refresh 会立即请求 snapshot
- refresh 失败时保留上一次成功的数据
- token 过期或失效时显示重新认证状态

> Claude OAuth usage endpoint 和 Codex subscription usage endpoint 都不是公开稳定 API。如果 schema 或 rate limit 改变，QuotaBar 会显示明确错误，而不是显示估算值。

## 本地保存的数据

| 位置 | 内容 |
| --- | --- |
| `~/Library/Application Support/QuotaBar/accounts.json` | provider、alias、email、source、file fallback path、去重 identity |
| macOS Keychain (`com.supia.quotabar.oauth`) | 应用内 OAuth access / refresh token |
| `~/Library/Application Support/QuotaBar/display-preferences.json` | 每个账号的 alias / email 显示设置 |

OAuth access / refresh token 不会写入这些文件。

## 开发者说明

```text
Sources/QuotaBarCore/       模型、decoder、credential boundary、provider client
Sources/QuotaBarUI/         菜单栏 UI、两种视图、polling、账号编辑器
Sources/QuotaBar/            菜单栏应用入口
Sources/QuotaBarPreview/     普通窗口 Preview 入口
Sources/QuotaBarChecks/      framework-free self-check
```

验证命令：

```bash
swift run QuotaBarChecks
swift build --product QuotaBar
swift build --product QuotaBarPreview
git diff --check
```

当前 Command Line Tools 环境无法使用 XCTest/Testing module，因此仓库使用 framework-free self-check executable。

## Roadmap

- 在 provider 策略允许时，用 native callback 处理替代手动粘贴 callback
- 通过 Claude/Codex profile endpoint 自动获取邮箱
- 每个账号独立的 stale / re-auth 状态卡片
- 扩充 provider token rotation / revoke 场景测试
- 持续完善完整 Xcode test target 和 signed/notarized release hardening

## 许可证

QuotaBar 使用 [MIT License](LICENSE) 发布。允许商业使用、修改、再分发和 fork，但需要保留版权和许可证声明。

## Repository

- GitHub: <https://github.com/Supia7/quota-bar>
- Plan: [`docs/2026-08-21-multi-account-oauth-plan.md`](docs/2026-08-21-multi-account-oauth-plan.md)
- Requirements: [`docs/2026-08-21-multi-account-oauth-requirements.md`](docs/2026-08-21-multi-account-oauth-requirements.md)
