import AppKit
import Combine
import QuotaBarCore
import SwiftUI
import UniformTypeIdentifiers

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
        ) as? String ?? "0.1.9"
        self.currentVersion = currentVersion
            ?? (try? ReleaseVersion(bundleVersion))
            ?? ReleaseVersion(major: 0, minor: 1, patch: 9)
        let registry = (try? registryStore.load()) ?? AccountRegistry()
        configuredAccounts = registry.accounts
        if let provider {
            self.provider = provider
        } else if registry.accounts.isEmpty {
            self.provider = SampleQuotaProvider()
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

    public func addAccount(_ descriptor: OAuthAccountDescriptor) {
        guard !AccountRegistry(accounts: configuredAccounts).containsEquivalentAccount(descriptor) else {
            errorMessage = "This OAuth account is already connected."
            return
        }
        configuredAccounts.append(descriptor)
        saveRegistry()
        provider = LiveOAuthQuotaProvider(accounts: configuredAccounts)
        Task { await refresh() }
    }

    public func addKeychainAccount(
        provider providerID: QuotaProviderID,
        credential: OAuthCredential,
        alias: String,
        email: String
    ) async throws {
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedEmail = normalizedEmail.isEmpty ? (credential.email ?? "") : normalizedEmail
        let descriptor = OAuthAccountDescriptor(
            provider: providerID,
            alias: alias.trimmingCharacters(in: .whitespacesAndNewlines),
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
            ? SampleQuotaProvider()
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
            "Re-authentication required for one or more accounts."
        case OAuthNetworkError.rateLimited:
            "Provider rate limited the refresh. Keeping the last data."
        default:
            "Refresh failed. Keeping the last data."
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
        let rowCount = model.groups.reduce(0) { $0 + $1.rows.count }
        let groupSpacing = max(0, model.groups.count - 1) * 12
        let estimated = 210 + CGFloat(rowCount * 78 + groupSpacing)
        return min(max(estimated, 300), 680)
    }

    private var monitorContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Picker("View", selection: $model.viewMode) {
                ForEach(UsageViewMode.allCases, id: \.self) { mode in
                    Text(mode.title).tag(mode)
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
                    "No quota data",
                    systemImage: "chart.bar.xaxis",
                    description: Text("Connect an OAuth account to load usage.")
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
                Text("QuotaBar")
                    .font(.title2.weight(.semibold))
                if model.isSampleData {
                    Text("SAMPLE DATA")
                        .font(.caption2.weight(.bold))
                        .tracking(1.1)
                        .foregroundStyle(.orange)
                }
            }
            Spacer()
            if let updateAction {
                Button(action: updateAction) {
                    Label("Check for updates", systemImage: "arrow.down.circle")
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.borderless)
                .foregroundStyle(.blue)
            } else if let release = model.availableRelease {
                Link(destination: release.pageURL) {
                    Label("Update \(release.version.description)", systemImage: "arrow.down.circle")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.blue)
            }
            Button {
                isShowingSettings = true
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("Show settings in this window")
            Button {
                Task { await model.refresh() }
            } label: {
                Image(systemName: model.isRefreshing ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Refresh quota data")
            .disabled(model.isRefreshing)
        }
    }

    private var footer: some View {
        HStack {
            if let lastUpdated = model.lastUpdated {
                Text("Updated \(lastUpdated, style: .relative)")
            } else {
                Text("Not updated yet")
            }
            Spacer()
            Text("OAuth only")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

private struct AccountQuotaCard: View {
    let account: QuotaAccount
    let rows: [QuotaGroupRow]
    let onEdit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle()
                    .fill(account.provider.tint)
                    .frame(width: 8, height: 8)
                Text(account.provider.displayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button(action: onEdit) {
                    Image(systemName: "ellipsis.circle")
                }
                .buttonStyle(.borderless)
                .help("Edit alias and email visibility")
            }

            HStack(alignment: .firstTextBaseline) {
                Text(account.displayName)
                    .font(.headline)
                Spacer()
                if let email = account.visibleEmail {
                    Text(email)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Image(systemName: "eye.slash")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .help("Email hidden")
                }
            }

            ForEach(rows) { row in
                QuotaWindowRow(window: row.window, tint: account.provider.tint)
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct LimitTypeCard: View {
    let group: QuotaGroup
    let onEdit: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(group.title)
                    .font(.headline)
                Spacer()
                Text("\(group.rows.count) accounts")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(group.rows) { row in
                HStack(spacing: 8) {
                    Circle()
                        .fill(row.provider.tint)
                        .frame(width: 7, height: 7)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.accountName)
                            .font(.subheadline.weight(.medium))
                        if let email = row.visibleEmail {
                            Text(email)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    QuotaWindowValue(window: row.window, tint: row.provider.tint)
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
                Text(window.title)
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
                Text(window.remainingFraction == nil ? "unavailable" : "remaining")
                Spacer()
                if let resetAt = window.resetAt {
                    Text("resets \(resetAt, style: .relative)")
                } else {
                    Text("reset unavailable")
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
            Text("Unavailable")
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
            Text("Edit account")
                .font(.title3.weight(.semibold))
            LabeledContent("Provider", value: account.provider.displayName)
            VStack(alignment: .leading, spacing: 6) {
                Text("Alias")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField("Optional alias", text: $alias)
                    .textFieldStyle(.roundedBorder)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Email")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(account.email.isEmpty ? "Not provided" : account.email)
                    .foregroundStyle(.secondary)
            }
            Toggle("Hide email in QuotaBar", isOn: $isEmailHidden)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
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
    @State private var provider: QuotaProviderID = .claude
    @State private var alias = ""
    @State private var email = ""
    @State private var credentialPath = ""
    @State private var isImporterPresented = false
    @State private var oauthRequest: OAuthAuthorizationRequest?
    @State private var callbackInput = ""
    @State private var isCompletingOAuth = false
    @State private var oauthError: String?

    private var suggestedCredentialPath: String {
        OAuthCredentialPathDiscovery.existingPath(for: provider)
            ?? OAuthCredentialPathDiscovery.defaultPath(for: provider)
    }

    private var selectedCredentialPath: String {
        let trimmed = credentialPath.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? suggestedCredentialPath : trimmed
    }

    private var credentialFileIsReadable: Bool {
        FileManager.default.isReadableFile(atPath: selectedCredentialPath)
    }

    public init(
        model: QuotaBarModel,
        onDone: (() -> Void)? = nil,
        updateAction: (@MainActor () -> Void)? = nil
    ) {
        self.model = model
        self.onDone = onDone
        self.updateAction = updateAction
        _credentialPath = State(
            initialValue: OAuthCredentialPathDiscovery.existingPath(for: .claude)
                ?? OAuthCredentialPathDiscovery.defaultPath(for: .claude)
        )
    }

    private var inAppOAuthSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sign in to QuotaBar")
                .font(.headline)
            Text("Open the provider login in your browser once. QuotaBar stores the resulting OAuth tokens in the macOS Keychain and refreshes them itself.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Button("Sign in with Claude") {
                    startOAuthLogin(for: .claude)
                }
                .buttonStyle(.borderedProminent)
                Button("Sign in with Codex") {
                    startOAuthLogin(for: .codex)
                }
                .buttonStyle(.borderedProminent)
            }

            if let oauthRequest {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Finish sign-in in your browser, then paste the callback URL or code here.")
                        .font(.caption)
                    TextField("Callback URL or authorization code", text: $callbackInput)
                        .textFieldStyle(.roundedBorder)
                    HStack {
                        Button(isCompletingOAuth ? "Completing…" : "Complete sign-in") {
                            Task { await completeOAuthLogin(oauthRequest) }
                        }
                        .disabled(isCompletingOAuth || callbackInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        Button("Cancel") {
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
                            Label("Back", systemImage: "chevron.left")
                        }
                        .buttonStyle(.borderless)
                    }
                    Text("Settings")
                        .font(.title2.weight(.semibold))
                }
                Text("Claude and Codex OAuth subscriptions only.")
                    .foregroundStyle(.secondary)

                inAppOAuthSection

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Updates")
                            .font(.headline)
                        Spacer()
                        Button {
                            if let updateAction {
                                updateAction()
                            } else {
                                Task { await model.checkForUpdates() }
                            }
                        } label: {
                            Label("Check for updates", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.borderless)
                        .disabled({
                            if case .checking = model.updateState { return true }
                            return false
                        }())
                    }
                    if case let .available(release) = model.updateState {
                        Link(
                            "QuotaBar \(release.version.description) is available — open release",
                            destination: release.pageURL
                        )
                        .foregroundStyle(.blue)
                    } else if case let .upToDate(version) = model.updateState {
                        Text("You are up to date (\(version)).")
                            .foregroundStyle(.secondary)
                    } else if case .checking = model.updateState {
                        Text("Checking GitHub Releases…")
                            .foregroundStyle(.secondary)
                    } else if case .failed = model.updateState {
                        Text("Could not check GitHub Releases right now.")
                            .foregroundStyle(.orange)
                    } else {
                        Text("Checks on launch and every 6 hours.")
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Connected accounts")
                        .font(.headline)
                    if model.configuredAccounts.isEmpty {
                        Text("No OAuth accounts configured. Sample data is shown in the monitor.")
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
                                        ? (account.credentialSource == .keychain
                                            ? "OAuth token in macOS Keychain"
                                            : account.credentialPath)
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
                                .help("Remove account")
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    Text("Use existing credential file (fallback)")
                        .font(.headline)
                    Picker("Provider", selection: $provider) {
                        ForEach(QuotaProviderID.allCases, id: \.self) { provider in
                            Text(provider.displayName).tag(provider)
                        }
                    }
                    .onChange(of: provider) { _, newProvider in
                        credentialPath = OAuthCredentialPathDiscovery.existingPath(for: newProvider)
                            ?? OAuthCredentialPathDiscovery.defaultPath(for: newProvider)
                    }
                    TextField("Alias (optional)", text: $alias)
                        .textFieldStyle(.roundedBorder)
                    TextField("Email (display only)", text: $email)
                        .textFieldStyle(.roundedBorder)
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(selectedCredentialPath)
                                .font(.caption)
                                .foregroundStyle(credentialFileIsReadable ? Color.secondary : Color.orange)
                                .lineLimit(1)
                            Label(
                                credentialFileIsReadable
                                    ? "Credential detected automatically"
                                    : "Credential file not found — choose JSON manually",
                                systemImage: credentialFileIsReadable ? "checkmark.circle" : "exclamationmark.triangle"
                            )
                            .font(.caption2)
                            .foregroundStyle(credentialFileIsReadable ? Color.green : Color.orange)
                        }
                        Spacer()
                        Button("Choose JSON…") {
                            isImporterPresented = true
                        }
                    }
                    Button("Add file-backed account") {
                        model.addAccount(
                            OAuthAccountDescriptor(
                                provider: provider,
                                alias: alias,
                                email: email,
                                credentialPath: selectedCredentialPath
                            )
                        )
                        alias = ""
                        email = ""
                    }
                    .disabled(!credentialFileIsReadable)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Label("New sign-ins are stored in the macOS Keychain", systemImage: "key.fill")
                    Label("Existing credential files remain available as a fallback", systemImage: "doc.badge.gearshape")
                    Label("Only fixed HTTPS provider endpoints are called", systemImage: "lock.shield")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(28)
        }
        .frame(maxWidth: .infinity)
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            if case let .success(urls) = result,
               let url = urls.first {
                credentialPath = url.path
            }
        }
    }

    private func startOAuthLogin(for provider: QuotaProviderID) {
        do {
            let request = try OAuthAuthorizationConfiguration.makeRequest(for: provider)
            oauthRequest = request
            callbackInput = ""
            oauthError = nil
            NSWorkspace.shared.open(request.url)
        } catch {
            oauthError = "Could not start browser login."
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
                credential: credential,
                alias: alias,
                email: email
            )
            oauthRequest = nil
            callbackInput = ""
            alias = ""
            email = ""
        } catch QuotaBarAccountMutationError.duplicateAccount {
            oauthError = "This OAuth account is already connected."
        } catch QuotaBarAccountMutationError.usageValidationFailed {
            oauthError = "Sign-in succeeded, but quota could not be verified. The account was not saved."
        } catch OAuthLoginError.stateMismatch {
            oauthError = "The callback state did not match. Start sign-in again."
        } catch OAuthLoginError.invalidCallback {
            oauthError = "Paste the complete callback URL or authorization code."
        } catch OAuthNetworkError.rateLimited {
            oauthError = "The provider rate-limited token exchange. Try again shortly."
        } catch OAuthNetworkError.reauthenticationRequired {
            oauthError = "The provider rejected the login. Start sign-in again."
        } catch {
            oauthError = "OAuth sign-in could not be completed."
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
