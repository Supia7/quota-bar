import AppKit
import Combine
import QuotaBarCore
import SwiftUI

public enum QuotaBarAccountMutationError: Error, Equatable {
    case duplicateAccount
    case credentialStorageFailed
    case usageValidationFailed
}

public enum QuotaBarUpdateState: Equatable {
    case idle
    case checking
    case upToDate(String)
    case available(GitHubRelease)
    case failed
}

@MainActor
public final class QuotaBarModel: ObservableObject {
    @Published public private(set) var accounts: [QuotaAccount] = []
    @Published public private(set) var configuredAccounts: [OAuthAccountDescriptor]
    @Published public private(set) var lastUpdated: Date?
    @Published public private(set) var isRefreshing = false
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var updateState: QuotaBarUpdateState = .idle
    @Published public var viewMode: UsageViewMode {
        didSet {
            UserDefaults.standard.set(viewMode.rawValue, forKey: Self.viewModeDefaultsKey)
        }
    }

    private static let viewModeDefaultsKey = "QuotaBar.viewMode"
    public static let automaticRefreshInterval: Duration = .seconds(5 * 60)
    private var provider: any QuotaProvider
    private let registryStore: JSONAccountRegistryStore
    private let preferenceStore: JSONAccountDisplayPreferencesStore
    private var displayPreferences: [UUID: AccountDisplayPreference]
    private var pollingTask: Task<Void, Never>?
    private var updateCheckTask: Task<Void, Never>?
    private let updateChecker: GitHubReleaseUpdateChecker
    private let currentVersion: ReleaseVersion

    public init(
        provider: (any QuotaProvider)? = nil,
        registryStore: JSONAccountRegistryStore = JSONAccountRegistryStore(),
        preferenceStore: JSONAccountDisplayPreferencesStore = JSONAccountDisplayPreferencesStore(),
        updateChecker: GitHubReleaseUpdateChecker = GitHubReleaseUpdateChecker(),
        currentVersion: ReleaseVersion? = nil
    ) {
        self.registryStore = registryStore
        self.preferenceStore = preferenceStore
        self.updateChecker = updateChecker
        let bundleVersion = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "0.1.11"
        self.currentVersion = currentVersion
            ?? (try? ReleaseVersion(bundleVersion))
            ?? ReleaseVersion(major: 0, minor: 1, patch: 11)
        let loadedRegistry = (try? registryStore.load()) ?? AccountRegistry()
        let registry = loadedRegistry.keychainOnly
        if registry != loadedRegistry {
            try? registryStore.save(registry)
        }
        configuredAccounts = registry.accounts
        if let provider {
            self.provider = provider
        } else if registry.accounts.isEmpty {
            self.provider = EmptyQuotaProvider()
        } else {
            self.provider = LiveOAuthQuotaProvider(accounts: registry.accounts)
        }
        displayPreferences = (try? preferenceStore.load()) ?? [:]
        let storedMode = UserDefaults.standard.string(forKey: Self.viewModeDefaultsKey)
        viewMode = UsageViewMode(rawValue: storedMode ?? "") ?? .account
        startPolling()
        startUpdateChecking()
    }

    deinit {
        pollingTask?.cancel()
        updateCheckTask?.cancel()
    }

    public var menuTitle: String {
        guard let tightest = accounts
            .flatMap(\.windows)
            .compactMap(\.remainingPercentage)
            .min()
        else {
            return "QuotaBar"
        }
        return "\(tightest)%"
    }

    public var isSampleData: Bool {
        !accounts.isEmpty && accounts.allSatisfy(\.isSampleData)
    }

    public var groups: [QuotaGroup] {
        QuotaGrouping.groups(accounts: accounts, mode: viewMode)
    }

    public var availableRelease: GitHubRelease? {
        guard case let .available(release) = updateState else { return nil }
        return release
    }

    public func startPolling() {
        guard pollingTask == nil else { return }
        pollingTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await refresh()
                do {
                    try await Task.sleep(for: Self.automaticRefreshInterval)
                } catch {
                    return
                }
            }
        }
    }

    private func startUpdateChecking() {
        guard updateCheckTask == nil else { return }
        updateCheckTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await checkForUpdates()
                do {
                    try await Task.sleep(for: .seconds(6 * 60 * 60))
                } catch {
                    return
                }
            }
        }
    }

    public func checkForUpdates() async {
        if case .checking = updateState {
            return
        }
        updateState = .checking
        do {
            if let release = try await updateChecker.check(currentVersion: currentVersion) {
                updateState = .available(release)
            } else {
                updateState = .upToDate(currentVersion.description)
            }
        } catch {
            updateState = .failed
        }
    }

    public func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let fetched = try await provider.snapshot(at: Date())
            accounts = fetched.map(applyDisplayPreference)
            errorMessage = nil
            lastUpdated = Date()
        } catch {
            errorMessage = message(for: error)
        }
    }

    public func account(id: UUID) -> QuotaAccount? {
        accounts.first(where: { $0.id == id })
    }

    public func addKeychainAccount(
        provider providerID: QuotaProviderID,
        credential: OAuthCredential
    ) async throws {
        let resolvedEmail = credential.email ?? ""
        let descriptor = OAuthAccountDescriptor(
            provider: providerID,
            alias: "",
            email: resolvedEmail,
            credentialSource: .keychain,
            credentialIdentity: credential.accountID
                ?? (resolvedEmail.isEmpty ? nil : resolvedEmail)
        )
        guard !AccountRegistry(accounts: configuredAccounts).containsEquivalentAccount(descriptor) else {
            throw QuotaBarAccountMutationError.duplicateAccount
        }

        let keychainStore = KeychainOAuthCredentialStore()
        do {
            try keychainStore.save(credential, for: descriptor.id)
            _ = try await LiveOAuthQuotaProvider(accounts: [descriptor]).snapshot(at: Date())
        } catch {
            try? keychainStore.delete(for: descriptor.id)
            throw QuotaBarAccountMutationError.usageValidationFailed
        }

        configuredAccounts.append(descriptor)
        saveRegistry()
        self.provider = LiveOAuthQuotaProvider(accounts: configuredAccounts)
        await refresh()
    }

    public func removeAccount(id: UUID) {
        if let descriptor = configuredAccounts.first(where: { $0.id == id }) {
            try? OAuthCredentialResolver().delete(descriptor)
        }
        configuredAccounts.removeAll { $0.id == id }
        saveRegistry()
        provider = configuredAccounts.isEmpty
            ? EmptyQuotaProvider()
            : LiveOAuthQuotaProvider(accounts: configuredAccounts)
        Task { await refresh() }
    }

    public func updateDisplay(
        for accountID: UUID,
        alias: String,
        isEmailHidden: Bool
    ) {
        let normalizedAlias = alias.trimmingCharacters(in: .whitespacesAndNewlines)
        displayPreferences[accountID] = AccountDisplayPreference(
            alias: normalizedAlias,
            isEmailHidden: isEmailHidden
        )
        try? preferenceStore.save(displayPreferences)

        guard let index = accounts.firstIndex(where: { $0.id == accountID }) else {
            return
        }
        let account = accounts[index]
        accounts[index] = QuotaAccount(
            id: account.id,
            provider: account.provider,
            alias: normalizedAlias,
            email: account.email,
            isEmailHidden: isEmailHidden,
            windows: account.windows,
            isSampleData: account.isSampleData
        )
    }

    private func saveRegistry() {
        try? registryStore.save(AccountRegistry(accounts: configuredAccounts))
    }

    private func applyDisplayPreference(to account: QuotaAccount) -> QuotaAccount {
        guard let preference = displayPreferences[account.id] else {
            return account
        }
        return QuotaAccount(
            id: account.id,
            provider: account.provider,
            alias: preference.alias,
            email: account.email,
            isEmailHidden: preference.isEmailHidden,
            windows: account.windows,
            isSampleData: account.isSampleData
        )
    }

    private func message(for error: Error) -> String {
        switch error {
        case OAuthNetworkError.reauthenticationRequired:
            L10n.string("error.refresh_reauth")
        case OAuthNetworkError.rateLimited:
            L10n.string("error.refresh_rate_limited")
        default:
            L10n.string("error.refresh_generic")
        }
    }
}

public struct QuotaMonitorView: View {
    @ObservedObject public var model: QuotaBarModel
    private let updateAction: (@MainActor () -> Void)?
    @State private var editingAccount: QuotaAccount?
    @State private var isShowingSettings = false

    public init(
        model: QuotaBarModel,
        updateAction: (@MainActor () -> Void)? = nil
    ) {
        self.model = model
        self.updateAction = updateAction
    }

    public var body: some View {
        Group {
            if isShowingSettings {
                QuotaSettingsView(
                    model: model,
                    onDone: {
                        isShowingSettings = false
                    },
                    updateAction: updateAction
                )
            } else {
                monitorContent
            }
        }
        .padding(16)
        .frame(
            minWidth: 560,
            idealWidth: 620,
            maxWidth: 680,
            minHeight: preferredHeight,
            idealHeight: preferredHeight,
            maxHeight: preferredHeight
        )
        .sheet(item: $editingAccount) { account in
            AccountEditorView(account: account) { alias, isEmailHidden in
                model.updateDisplay(
                    for: account.id,
                    alias: alias,
                    isEmailHidden: isEmailHidden
                )
            }
        }
    }

    private var preferredHeight: CGFloat {
        if isShowingSettings {
            return 620
        }
        guard !model.groups.isEmpty else {
            return 240
        }
        let rowCount = model.viewMode == .account
            ? model.accounts.count
            : model.groups.reduce(0) { $0 + $1.rows.count }
        let groupSpacing = max(0, model.groups.count - 1) * 12
        let estimated = 185 + CGFloat(rowCount * 56 + groupSpacing)
        return min(max(estimated, 260), 560)
    }

    private var monitorContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Picker(L10n.string("monitor.view"), selection: $model.viewMode) {
                ForEach(UsageViewMode.allCases, id: \.self) { mode in
                    Text(L10n.viewTitle(mode)).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Divider()

            if let errorMessage = model.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if model.groups.isEmpty {
                ContentUnavailableView(
                    L10n.string("monitor.no_data_title"),
                    systemImage: "chart.bar.xaxis",
                    description: Text(L10n.string("monitor.no_data_description"))
                )
                .frame(minHeight: 150)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(model.groups) { group in
                            if let account = group.account {
                                AccountQuotaCard(
                                    account: account,
                                    rows: group.rows,
                                    onEdit: { editingAccount = account }
                                )
                            } else {
                                LimitTypeCard(
                                    group: group,
                                    onEdit: { accountID in
                                        editingAccount = model.account(id: accountID)
                                    }
                                )
                            }
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .frame(maxHeight: 560)
            }

            Divider()
            footer
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.string("app.name"))
                    .font(.title2.weight(.semibold))
                if model.isSampleData {
                    Text(L10n.string("monitor.sample_data"))
                        .font(.caption2.weight(.bold))
                        .tracking(1.1)
                        .foregroundStyle(.orange)
                }
            }
            Spacer()
            if let updateAction {
                Button(action: updateAction) {
                    Label(L10n.string("update.check"), systemImage: "arrow.down.circle")
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.borderless)
                .foregroundStyle(.blue)
            } else if let release = model.availableRelease {
                Link(destination: release.pageURL) {
                    Label(L10n.updateAvailable(release.version.description), systemImage: "arrow.down.circle")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.blue)
            }
            Button {
                isShowingSettings = true
            } label: {
                Label(L10n.string("settings.title"), systemImage: "gearshape")
            }
            .buttonStyle(.borderless)
            .help(L10n.string("settings.title"))
            Button {
                Task { await model.refresh() }
            } label: {
                Image(systemName: model.isRefreshing ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help(L10n.string("monitor.refresh"))
            .disabled(model.isRefreshing)
        }
    }

    private var footer: some View {
        HStack {
            if let lastUpdated = model.lastUpdated {
                Text(L10n.string("monitor.updated"))
                Text(lastUpdated, style: .relative)
            } else {
                Text(L10n.string("monitor.not_updated"))
            }
            Spacer()
            Text(L10n.string("monitor.oauth_only"))
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

private struct AccountQuotaCard: View {
    let account: QuotaAccount
    let rows: [QuotaGroupRow]
    let onEdit: () -> Void
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle()
                    .fill(account.provider.tint)
                    .frame(width: 8, height: 8)
                HStack(spacing: 4) {
                    Text(account.displayName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    if let email = account.visibleEmail {
                        Text("· \(email)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                HStack(spacing: 5) {
                    ForEach(rows) { row in
                        CompactQuotaBadge(window: row.window, tint: account.provider.tint)
                    }
                }
                Button {
                    withAnimation(.easeOut(duration: 0.15)) {
                        isExpanded.toggle()
                    }
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                }
                .buttonStyle(.borderless)
                .help(L10n.string("account.toggle_details"))
                Button(action: onEdit) {
                    Image(systemName: "ellipsis.circle")
                }
                .buttonStyle(.borderless)
                .help(L10n.string("account.edit"))
            }

            if isExpanded {
                Divider()
                ForEach(rows) { row in
                    QuotaWindowRow(window: row.window, tint: account.provider.tint)
                }
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct CompactQuotaBadge: View {
    let window: QuotaWindow
    let tint: Color

    var body: some View {
        HStack(spacing: 3) {
            Text(window.kind.compactLabel)
                .font(.caption2.weight(.semibold))
            if let percentage = window.remainingPercentage {
                Text("\(percentage)%")
                    .font(.caption2.monospacedDigit().weight(.semibold))
            } else {
                Text("—")
                    .font(.caption2.weight(.semibold))
            }
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(tint.opacity(0.12), in: Capsule())
    }
}

private struct LimitTypeCard: View {
    let group: QuotaGroup
    let onEdit: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L10n.windowTitle(group.kind ?? .weekly))
                    .font(.headline)
                Spacer()
                Text(L10n.accountCount(group.rows.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(group.rows) { row in
                HStack(spacing: 8) {
                    Circle()
                        .fill(row.provider.tint)
                        .frame(width: 7, height: 7)
                    HStack(spacing: 4) {
                        Text(row.accountName)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                        if let email = row.visibleEmail {
                            Text("· \(email)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                    CompactQuotaBadge(window: row.window, tint: row.provider.tint)
                    Button {
                        onEdit(row.accountID)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct QuotaWindowRow: View {
    let window: QuotaWindow
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(L10n.windowTitle(window.kind))
                    .font(.subheadline)
                Spacer()
                QuotaWindowValue(window: window, tint: tint)
            }

            if let fraction = window.remainingFraction {
                ProgressView(value: fraction)
                    .tint(tint)
            } else {
                ProgressView(value: 0)
                    .tint(.secondary)
                    .opacity(0.35)
            }

            HStack {
                Text(window.remainingFraction == nil
                    ? L10n.string("quota.unavailable")
                    : L10n.string("quota.remaining"))
                Spacer()
                if let resetAt = window.resetAt {
                    Text(L10n.string("quota.resets"))
                    Text(resetAt, style: .relative)
                } else {
                    Text(L10n.string("quota.reset_unavailable"))
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }
}

private struct QuotaWindowValue: View {
    let window: QuotaWindow
    let tint: Color

    var body: some View {
        if let percentage = window.remainingPercentage {
            Text("\(percentage)%")
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .foregroundStyle(tint)
        } else {
            Text(L10n.string("quota.unavailable"))
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }
}

private struct AccountEditorView: View {
    let account: QuotaAccount
    let onSave: (String, Bool) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var alias: String
    @State private var isEmailHidden: Bool

    init(account: QuotaAccount, onSave: @escaping (String, Bool) -> Void) {
        self.account = account
        self.onSave = onSave
        _alias = State(initialValue: account.alias)
        _isEmailHidden = State(initialValue: account.isEmailHidden)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.string("account.edit"))
                .font(.title3.weight(.semibold))
            LabeledContent(L10n.string("account.provider"), value: account.provider.displayName)
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.string("account.alias"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField(L10n.string("account.alias_placeholder"), text: $alias)
                    .textFieldStyle(.roundedBorder)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.string("account.email"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(account.email.isEmpty ? L10n.string("account.not_provided") : account.email)
                    .foregroundStyle(.secondary)
            }
            Toggle(L10n.string("account.hide_email"), isOn: $isEmailHidden)
            HStack {
                Spacer()
                Button(L10n.string("common.cancel")) { dismiss() }
                Button(L10n.string("common.save")) {
                    onSave(alias, isEmailHidden)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 360)
    }
}

public struct QuotaSettingsView: View {
    @ObservedObject public var model: QuotaBarModel
    private let onDone: (() -> Void)?
    private let updateAction: (@MainActor () -> Void)?
    @State private var oauthRequest: OAuthAuthorizationRequest?
    @State private var callbackInput = ""
    @State private var isCompletingOAuth = false
    @State private var oauthError: String?

    public init(
        model: QuotaBarModel,
        onDone: (() -> Void)? = nil,
        updateAction: (@MainActor () -> Void)? = nil
    ) {
        self.model = model
        self.onDone = onDone
        self.updateAction = updateAction
    }

    private var inAppOAuthSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.string("settings.sign_in_title"))
                .font(.headline)
            Text(L10n.string("settings.sign_in_description"))
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Button(L10n.string("provider.sign_in_claude")) {
                    startOAuthLogin(for: .claude)
                }
                .buttonStyle(.borderedProminent)
                Button(L10n.string("provider.sign_in_codex")) {
                    startOAuthLogin(for: .codex)
                }
                .buttonStyle(.borderedProminent)
            }

            if let oauthRequest {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.string("oauth.callback_instruction"))
                        .font(.caption)
                    Text(L10n.string("oauth.callback_warning"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    TextField(
                        L10n.string("oauth.callback_placeholder"),
                        text: $callbackInput
                    )
                    .textFieldStyle(.roundedBorder)
                    HStack {
                        Button(isCompletingOAuth
                            ? L10n.string("oauth.completing")
                            : L10n.string("oauth.complete")) {
                            Task { await completeOAuthLogin(oauthRequest) }
                        }
                        .disabled(isCompletingOAuth || callbackInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        Button(L10n.string("common.cancel")) {
                            self.oauthRequest = nil
                            callbackInput = ""
                            oauthError = nil
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .padding(10)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            }
            if let oauthError {
                Label(oauthError, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 10) {
                    if let onDone {
                        Button(action: onDone) {
                            Label(L10n.string("common.back"), systemImage: "chevron.left")
                        }
                        .buttonStyle(.borderless)
                    }
                    Text(L10n.string("settings.title"))
                        .font(.title2.weight(.semibold))
                }
                Text(L10n.string("settings.subtitle"))
                    .foregroundStyle(.secondary)

                inAppOAuthSection

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(L10n.string("update.title"))
                            .font(.headline)
                        Spacer()
                        Button {
                            if let updateAction {
                                updateAction()
                            } else {
                                Task { await model.checkForUpdates() }
                            }
                        } label: {
                            Label(L10n.string("update.check"), systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.borderless)
                        .disabled({
                            if case .checking = model.updateState { return true }
                            return false
                        }())
                    }
                    if case let .available(release) = model.updateState {
                        Link(
                            L10n.updateAvailable(release.version.description),
                            destination: release.pageURL
                        )
                        .foregroundStyle(.blue)
                    } else if case let .upToDate(version) = model.updateState {
                        Text(L10n.updateUpToDate(version))
                            .foregroundStyle(.secondary)
                    } else if case .checking = model.updateState {
                        Text(L10n.string("update.checking"))
                            .foregroundStyle(.secondary)
                    } else if case .failed = model.updateState {
                        Text(L10n.string("update.failed"))
                            .foregroundStyle(.orange)
                    } else {
                        Text(L10n.string("update.schedule"))
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.string("settings.connected_accounts"))
                        .font(.headline)
                    if model.configuredAccounts.isEmpty {
                        Text(L10n.string("settings.no_accounts"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(model.configuredAccounts) { account in
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(account.provider.tint)
                                    .frame(width: 8, height: 8)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(account.alias.isEmpty ? account.email : account.alias)
                                        .font(.subheadline.weight(.medium))
                                    Text(account.email.isEmpty
                                        ? L10n.string("settings.keychain_account")
                                        : account.email)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Button(role: .destructive) {
                                    model.removeAccount(id: account.id)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                                .help(L10n.string("account.remove"))
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Label(L10n.string("settings.keychain_only"), systemImage: "key.fill")
                    Label(L10n.string("settings.no_file_fallback"), systemImage: "doc.badge.minus")
                    Label(L10n.string("settings.fixed_endpoints"), systemImage: "lock.shield")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(28)
        }
        .frame(maxWidth: .infinity)
    }

    private func startOAuthLogin(for provider: QuotaProviderID) {
        do {
            let request = try OAuthAuthorizationConfiguration.makeRequest(for: provider)
            oauthRequest = request
            callbackInput = ""
            oauthError = nil
            NSWorkspace.shared.open(request.url)
        } catch {
            oauthError = L10n.string("error.browser_login_failed")
        }
    }

    private func completeOAuthLogin(_ request: OAuthAuthorizationRequest) async {
        isCompletingOAuth = true
        oauthError = nil
        defer { isCompletingOAuth = false }
        do {
            let callback = try OAuthCallbackParser.parse(
                callbackInput,
                expectedState: request.state
            )
            let credential = try await OAuthTokenService().exchange(
                request: request,
                callback: callback
            )
            try await model.addKeychainAccount(
                provider: request.provider,
                credential: credential
            )
            oauthRequest = nil
            callbackInput = ""
        } catch QuotaBarAccountMutationError.duplicateAccount {
            oauthError = L10n.string("error.duplicate")
        } catch QuotaBarAccountMutationError.usageValidationFailed {
            oauthError = L10n.string("error.usage_validation")
        } catch OAuthLoginError.stateMismatch {
            oauthError = L10n.string("error.state_mismatch")
        } catch OAuthLoginError.accessTokenNotAccepted {
            oauthError = L10n.string("error.access_token")
        } catch OAuthLoginError.invalidCallback {
            oauthError = L10n.string("error.invalid_callback")
        } catch let OAuthLoginError.tokenExchangeRejected(reason) {
            oauthError = message(for: reason)
        } catch OAuthNetworkError.rateLimited {
            oauthError = L10n.string("error.rate_limited")
        } catch OAuthNetworkError.reauthenticationRequired {
            oauthError = L10n.string("error.reauth")
        } catch {
            oauthError = L10n.string("error.oauth_generic")
        }
    }

    private func message(for reason: OAuthTokenExchangeReason) -> String {
        switch reason {
        case .invalidGrant:
            L10n.string("error.invalid_grant")
        case .redirectMismatch:
            L10n.string("error.redirect_mismatch")
        case .invalidRequest:
            L10n.string("error.invalid_request")
        case .providerRejected:
            L10n.string("error.provider_rejected")
        case .unknown:
            L10n.string("error.token_unknown")
        }
    }
}

private extension QuotaProviderID {
    var tint: Color {
        switch self {
        case .claude:
            .orange
        case .codex:
            .green
        }
    }
}
