import Combine
import QuotaBarCore
import SwiftUI
import UniformTypeIdentifiers

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
        ) as? String ?? "0.1.2"
        self.currentVersion = currentVersion
            ?? (try? ReleaseVersion(bundleVersion))
            ?? ReleaseVersion(major: 0, minor: 1, patch: 2)
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
                    try await Task.sleep(for: .seconds(180))
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
        configuredAccounts.append(descriptor)
        saveRegistry()
        provider = LiveOAuthQuotaProvider(accounts: configuredAccounts)
        Task { await refresh() }
    }

    public func removeAccount(id: UUID) {
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
    @State private var editingAccount: QuotaAccount?

    public init(model: QuotaBarModel) {
        self.model = model
    }

    public var body: some View {
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
            }

            Divider()
            footer
        }
        .padding(16)
        .frame(
            minWidth: 560,
            idealWidth: 620,
            maxWidth: 680,
            minHeight: 620,
            idealHeight: 720,
            maxHeight: 820
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
            if let release = model.availableRelease {
                Link(destination: release.pageURL) {
                    Label("Update \(release.version.description)", systemImage: "arrow.down.circle")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.blue)
            }
            SettingsLink {
                Label("Settings", systemImage: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("Open QuotaBar settings")
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
    @State private var provider: QuotaProviderID = .claude
    @State private var alias = ""
    @State private var email = ""
    @State private var credentialPath = ""
    @State private var isImporterPresented = false

    public init(model: QuotaBarModel) {
        self.model = model
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("QuotaBar")
                    .font(.title2.weight(.semibold))
                Text("Claude and Codex OAuth subscriptions only.")
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Updates")
                            .font(.headline)
                        Spacer()
                        Button {
                            Task { await model.checkForUpdates() }
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
                                    Text(account.email.isEmpty ? account.credentialPath : account.email)
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
                    Text("Add OAuth account")
                        .font(.headline)
                    Picker("Provider", selection: $provider) {
                        ForEach(QuotaProviderID.allCases, id: \.self) { provider in
                            Text(provider.displayName).tag(provider)
                        }
                    }
                    TextField("Alias (optional)", text: $alias)
                        .textFieldStyle(.roundedBorder)
                    TextField("Email (display only)", text: $email)
                        .textFieldStyle(.roundedBorder)
                    HStack {
                        Text(credentialPath.isEmpty ? "No credential file selected" : credentialPath)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer()
                        Button("Choose JSON…") {
                            isImporterPresented = true
                        }
                    }
                    Button("Add OAuth account") {
                        model.addAccount(
                            OAuthAccountDescriptor(
                                provider: provider,
                                alias: alias,
                                email: email,
                                credentialPath: credentialPath
                            )
                        )
                        alias = ""
                        email = ""
                        credentialPath = ""
                    }
                    .disabled(credentialPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Label("Tokens stay in provider credential files", systemImage: "key.fill")
                    Label("Only fixed HTTPS usage hosts are called", systemImage: "lock.shield")
                    Label("Email visibility and aliases are local", systemImage: "person.crop.circle")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(28)
        }
        .frame(width: 440, height: 620)
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
