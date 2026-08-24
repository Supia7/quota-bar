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
    @Published public private(set) var resetNotices: [QuotaResetEvent] = []
    @Published public private(set) var localUsage: [QuotaProviderID: LocalUsageSummary] = [:]
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
    private var localUsageTask: Task<Void, Never>?
    private var updateCheckTask: Task<Void, Never>?
    private let updateChecker: GitHubReleaseUpdateChecker
    private let currentVersion: ReleaseVersion
    private let resetObservationStore: JSONQuotaResetObservationStore
    private let localUsageScanner: LocalUsageScanner
    private var resetObservations: [QuotaResetObservation]

    public var resetHandler: (@MainActor ([QuotaResetEvent]) -> Void)?

    public init(
        provider: (any QuotaProvider)? = nil,
        registryStore: JSONAccountRegistryStore = JSONAccountRegistryStore(),
        preferenceStore: JSONAccountDisplayPreferencesStore = JSONAccountDisplayPreferencesStore(),
        updateChecker: GitHubReleaseUpdateChecker = GitHubReleaseUpdateChecker(),
        currentVersion: ReleaseVersion? = nil,
        resetObservationStore: JSONQuotaResetObservationStore = JSONQuotaResetObservationStore(),
        localUsageScanner: LocalUsageScanner = LocalUsageScanner()
    ) {
        self.registryStore = registryStore
        self.preferenceStore = preferenceStore
        self.updateChecker = updateChecker
        self.resetObservationStore = resetObservationStore
        self.localUsageScanner = localUsageScanner
        self.resetObservations = (try? resetObservationStore.load()) ?? []
        let bundleVersion = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "0.2.0"
        self.currentVersion = currentVersion
            ?? (try? ReleaseVersion(bundleVersion))
            ?? ReleaseVersion(major: 0, minor: 2, patch: 0)
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
        startLocalUsagePolling()
        startUpdateChecking()
    }

    deinit {
        pollingTask?.cancel()
        localUsageTask?.cancel()
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

    public func refreshLocalUsage() async {
        let scanner = localUsageScanner
        let summaries = await Task.detached(priority: .utility) {
            scanner.scanToday()
        }.value
        guard !Task.isCancelled else { return }
        localUsage = summaries
    }

    private func startLocalUsagePolling() {
        guard localUsageTask == nil else { return }
        localUsageTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await refreshLocalUsage()
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
            let now = Date()
            let fetched = try await provider.snapshot(at: now)
            let nextAccounts = fetched.map(applyDisplayPreference)
            let resetEvents = QuotaResetDetector.detect(
                previous: resetObservations,
                current: nextAccounts,
                at: now
            )
            resetObservations = QuotaResetDetector.observations(from: nextAccounts)
            try? resetObservationStore.save(resetObservations)
            accounts = nextAccounts
            errorMessage = nil
            lastUpdated = now
            if !resetEvents.isEmpty {
                let existingNoticeIDs = Set(resetNotices.map(\.id))
                resetNotices.append(contentsOf: resetEvents.filter {
                    !existingNoticeIDs.contains($0.id)
                })
                resetHandler?(resetEvents)
            }
        } catch {
            errorMessage = message(for: error)
        }
    }

    public func dismissResetNotice(id: String) {
        resetNotices.removeAll { $0.id == id }
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
        resetObservations.removeAll { $0.accountID == id }
        resetNotices.removeAll { $0.accountID == id }
        try? resetObservationStore.save(resetObservations)
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
    @State private var refreshRotation = 0.0

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
        .padding(12)
        .frame(
            minWidth: 380,
            idealWidth: 420,
            maxWidth: 460,
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
            return 400
        }
        guard !model.groups.isEmpty else {
            return 300
        }
        let providerCount = max(providerGroups.count, 1)
        let additionalAccountCount = max(0, model.accounts.count - providerCount)
        let secondaryWindowCount = model.accounts.reduce(0) { total, account in
            total + max(0, account.windows.count - 1)
        }
        let estimated = 110
            + CGFloat(providerCount * 150)
            + CGFloat(secondaryWindowCount * 30)
            + CGFloat(model.localUsage.count * 24)
            + CGFloat(additionalAccountCount * 44)
        return min(max(estimated, 320), 500)
    }

    private var providerGroups: [ProviderAccountGroup] {
        let providerOrder: [QuotaProviderID] = [.codex, .claude]
        return providerOrder.compactMap { provider in
            let accounts = model.accounts.filter { $0.provider == provider }
            guard !accounts.isEmpty else { return nil }
            return ProviderAccountGroup(provider: provider, accounts: accounts)
        }
    }

    private var monitorContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            if let resetNotice = model.resetNotices.last {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "arrow.clockwise.circle.fill")
                        .foregroundStyle(.orange)
                    Text(L10n.resetNotice(resetNotice))
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button {
                        model.dismissResetNotice(id: resetNotice.id)
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.borderless)
                    .help(L10n.string("common.close"))
                }
                .padding(8)
                .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                .padding(.top, 10)
            }

            if let errorMessage = model.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.top, 8)
            }

            if model.groups.isEmpty {
                ContentUnavailableView(
                    L10n.string("monitor.no_data_title"),
                    systemImage: "chart.bar.xaxis",
                    description: Text(L10n.string("monitor.no_data_description"))
                )
                .frame(minHeight: 120)
                .padding(.vertical, 8)
            } else if model.viewMode == .account {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(providerGroups.enumerated()), id: \.element.id) { index, group in
                            ProviderQuotaBlock(
                                group: group,
                                todayUsage: model.localUsage[group.provider]
                            ) { account in
                                editingAccount = account
                            }
                            if index < providerGroups.count - 1 {
                                Divider()
                                    .padding(.horizontal, 16)
                            }
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .frame(maxHeight: 440)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(model.groups) { group in
                            LimitTypeCard(
                                group: group,
                                onEdit: { accountID in
                                    editingAccount = model.account(id: accountID)
                                }
                            )
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .frame(maxHeight: 440)
            }

            Divider()
                .padding(.top, 4)
            viewToolbar
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.string("monitor.title"))
                    .font(.headline.weight(.semibold))
                HStack(spacing: 4) {
                    if model.isSampleData {
                        Text(L10n.string("monitor.sample_data"))
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.orange)
                    }
                    if let lastUpdated = model.lastUpdated {
                        Text(L10n.string("monitor.updated"))
                        Text(lastUpdated, style: .relative)
                            .monospacedDigit()
                    } else {
                        Text(L10n.string("monitor.not_updated"))
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Circle()
                .fill(refreshStatusColor)
                .frame(width: 7, height: 7)
                .padding(.top, 8)

            Button {
                withAnimation(.easeInOut(duration: 0.7)) {
                    refreshRotation += 360
                }
                Task { await model.refresh() }
            } label: {
                Image(systemName: model.isRefreshing
                    ? "arrow.triangle.2.circlepath"
                    : "arrow.clockwise")
                    .rotationEffect(.degrees(refreshRotation))
            }
            .buttonStyle(PopoverIconButtonStyle())
            .help(L10n.string("monitor.refresh"))
            .accessibilityLabel(L10n.string("monitor.refresh"))

            if let updateAction {
                Button(action: updateAction) {
                    Image(systemName: "arrow.down.circle")
                }
                .buttonStyle(PopoverIconButtonStyle())
                .help(L10n.string("update.check"))
                .accessibilityLabel(L10n.string("update.check"))
            } else if let release = model.availableRelease {
                Link(destination: release.pageURL) {
                    Image(systemName: "arrow.down.circle.fill")
                }
                .buttonStyle(PopoverIconButtonStyle())
                .help(L10n.updateAvailable(release.version.description))
                .accessibilityLabel(L10n.updateAvailable(release.version.description))
            }

            Button {
                isShowingSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(PopoverIconButtonStyle())
            .help(L10n.string("settings.title"))
            .accessibilityLabel(L10n.string("settings.title"))
        }
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    private var refreshStatusColor: Color {
        if model.errorMessage != nil { return .orange }
        if model.accounts.isEmpty { return .secondary }
        return .green
    }

    private var viewToolbar: some View {
        HStack {
            Picker(L10n.string("monitor.view"), selection: $model.viewMode) {
                ForEach(UsageViewMode.allCases, id: \.self) { mode in
                    Text(L10n.viewTitle(mode)).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 148)
            Spacer(minLength: 0)
        }
        .padding(.top, 8)
        .padding(.bottom, 2)
    }
}

private struct PopoverIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: 26, height: 22)
            .foregroundStyle(.secondary)
            .background(
                configuration.isPressed
                    ? Color.primary.opacity(0.14)
                    : Color.clear,
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

private struct ProviderAccountGroup: Identifiable {
    let provider: QuotaProviderID
    let accounts: [QuotaAccount]

    var id: String { provider.rawValue }
}

private struct ProviderQuotaBlock: View {
    let group: ProviderAccountGroup
    let todayUsage: LocalUsageSummary?
    let onEdit: (QuotaAccount) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(group.provider.tint)
                    .frame(width: 22, height: 22)
                    .overlay {
                        Image(systemName: group.provider == .codex ? "curlybraces" : "sparkles")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                    }

                VStack(alignment: .leading, spacing: 1) {
                    Text(group.provider.displayName)
                        .font(.headline.weight(.semibold))
                    Text(group.accounts.count == 1
                        ? group.accounts[0].displayName
                        : L10n.accountCount(group.accounts.count))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
                Circle()
                    .fill(.green)
                    .frame(width: 7, height: 7)
            }

            if let primary = group.accounts.first {
                ProviderPrimaryQuota(
                    provider: group.provider,
                    account: primary,
                    todayUsage: todayUsage
                )
            }

            ForEach(group.accounts.dropFirst()) { account in
                Divider()
                    .padding(.top, 12)
                CompactProviderAccountRow(
                    provider: group.provider,
                    account: account,
                    onEdit: { onEdit(account) }
                )
            }
        }
        .padding(.vertical, 14)
    }
}

private struct ProviderPrimaryQuota: View {
    let provider: QuotaProviderID
    let account: QuotaAccount
    let todayUsage: LocalUsageSummary?

    private var primaryWindow: QuotaWindow? {
        primaryQuotaWindow(for: account, provider: provider)
    }

    private var secondaryWindows: [QuotaWindow] {
        guard let primaryWindow else { return account.windows }
        return account.windows.filter { $0.id != primaryWindow.id }
    }

    var body: some View {
        if let primaryWindow {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: 14) {
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(alignment: .firstTextBaseline, spacing: 1) {
                            if let percentage = primaryWindow.remainingPercentage {
                                Text("\(percentage)")
                                    .font(.system(size: 36, weight: .semibold))
                                    .monospacedDigit()
                                    .foregroundStyle(quotaStatusColor(primaryWindow.remainingFraction))
                                Text("%")
                                    .font(.title3.weight(.semibold))
                                    .foregroundStyle(quotaStatusColor(primaryWindow.remainingFraction))
                            } else {
                                Text("—")
                                    .font(.system(size: 36, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Text(primaryWindowLabel(primaryWindow, provider: provider))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 104, alignment: .leading)

                    VStack(alignment: .leading, spacing: 7) {
                        QuotaProgressBar(
                            fraction: primaryWindow.remainingFraction,
                            tint: quotaStatusColor(primaryWindow.remainingFraction),
                            height: 7
                        )
                        HStack(spacing: 4) {
                            Text(compactResetText(primaryWindow.resetAt))
                                .font(.subheadline.weight(.medium))
                                .monospacedDigit()
                            Text(L10n.string("quota.resets"))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Spacer(minLength: 0)
                        }
                    }
                }
                .padding(.top, 12)

                if let todayUsage, !todayUsage.isEmpty {
                    LocalUsageLine(summary: todayUsage)
                        .padding(.top, 8)
                }

                ForEach(secondaryWindows) { window in
                    CompactQuotaWindowRow(window: window)
                        .padding(.top, 8)
                }
            }
        } else {
            Text(L10n.string("quota.unavailable"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 12)
        }
    }
}

private struct CompactProviderAccountRow: View {
    let provider: QuotaProviderID
    let account: QuotaAccount
    let onEdit: () -> Void

    private var primaryWindow: QuotaWindow? {
        primaryQuotaWindow(for: account, provider: provider)
    }

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(provider.tint)
                .frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 2) {
                Text(account.displayName)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                if let email = account.visibleEmail {
                    Text(email)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if let primaryWindow {
                VStack(alignment: .trailing, spacing: 1) {
                    if let percentage = primaryWindow.remainingPercentage {
                        Text("\(percentage)%")
                            .font(.subheadline.monospacedDigit().weight(.semibold))
                            .foregroundStyle(quotaStatusColor(primaryWindow.remainingFraction))
                    }
                    Text(primaryWindowLabel(primaryWindow, provider: provider))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            Button(action: onEdit) {
                Image(systemName: "ellipsis.circle")
            }
            .buttonStyle(.borderless)
            .help(L10n.string("account.edit"))
            .accessibilityLabel(L10n.string("account.edit"))
        }
        .padding(.top, 10)
    }
}

private struct LocalUsageLine: View {
    let summary: LocalUsageSummary

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "chart.bar.xaxis")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(L10n.string("usage.today"))
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Text(L10n.localUsageTokens(summary.totalTokens))
                .font(.caption2.monospacedDigit().weight(.medium))
            Text("·")
                .foregroundStyle(.tertiary)
            Text(L10n.localUsageSessions(summary.sessionCount))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}

private struct QuotaProgressBar: View {
    let fraction: Double?
    let tint: Color
    let height: CGFloat

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.1))
                Capsule()
                    .fill(tint)
                    .frame(width: max(0, proxy.size.width * CGFloat(fraction ?? 0)))
            }
        }
        .frame(height: height)
    }
}

private struct CompactQuotaWindowRow: View {
    let window: QuotaWindow

    var body: some View {
        HStack(spacing: 7) {
            Text(window.kind.compactLabel.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 28, alignment: .leading)
            QuotaProgressBar(
                fraction: window.remainingFraction,
                tint: quotaStatusColor(window.remainingFraction),
                height: 4
            )
            if let percentage = window.remainingPercentage {
                Text("\(percentage)%")
                    .font(.caption.monospacedDigit().weight(.medium))
                    .foregroundStyle(quotaStatusColor(window.remainingFraction))
                    .frame(width: 34, alignment: .trailing)
            } else {
                Text("—")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 34, alignment: .trailing)
            }
            Text(compactResetText(window.resetAt))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 42, alignment: .trailing)
        }
    }
}

private struct CompactQuotaBadge: View {
    let window: QuotaWindow

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
        .foregroundStyle(quotaStatusColor(window.remainingFraction))
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(quotaStatusColor(window.remainingFraction).opacity(0.12), in: Capsule())
    }
}

private func primaryQuotaWindow(
    for account: QuotaAccount,
    provider: QuotaProviderID
) -> QuotaWindow? {
    let preferredKinds: [QuotaWindowKind] = provider == .codex
        ? [.weekly, .fiveHour, .fableWeekly]
        : [.fiveHour, .weekly, .fableWeekly]
    for kind in preferredKinds {
        if let window = account.windows.first(where: { $0.kind == kind }) {
            return window
        }
    }
    return account.windows.first
}

private func primaryWindowLabel(
    _ window: QuotaWindow,
    provider: QuotaProviderID
) -> String {
    switch window.kind {
    case .fiveHour:
        return "5HOUR"
    case .weekly:
        return provider == .claude ? "ALL" : "WEEKLY"
    case .fableWeekly:
        return "FABLE"
    }
}

private func quotaStatusColor(_ fraction: Double?) -> Color {
    guard let fraction else { return .secondary }
    if fraction > 0.5 { return .green }
    if fraction > 0.2 { return .yellow }
    if fraction > 0 { return .orange }
    return .red
}

private func compactResetText(_ date: Date?) -> String {
    guard let date else { return "—" }
    let totalMinutes = max(1, Int((date.timeIntervalSinceNow / 60).rounded()))
    if totalMinutes < 60 {
        return "\(totalMinutes)m"
    }
    let totalHours = totalMinutes / 60
    if totalHours < 24 {
        return "\(totalHours)h\(totalMinutes % 60)m"
    }
    return "\(totalHours / 24)d\(totalHours % 24)h"
}


private struct LimitTypeCard: View {
    let group: QuotaGroup
    let onEdit: (UUID) -> Void
    @Environment(\.colorScheme) private var colorScheme

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
                    CompactQuotaBadge(window: row.window)
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
        .foregroundStyle(cardForeground)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 12))
    }

    private var cardForeground: Color {
        colorScheme == .dark ? .white : .black
    }

    private var cardBackground: Color {
        colorScheme == .dark
            ? Color(red: 0.16, green: 0.18, blue: 0.19)
            : Color(red: 0.94, green: 0.95, blue: 0.96)
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

@MainActor
private final class OAuthLoopbackCoordinator: ObservableObject {
    @Published var callbackURL: String?
    @Published var isActive = false
    @Published var isListening = false
    @Published var failed = false

    private var server: OAuthLoopbackCallbackServer?

    func start() throws {
        stop()
        callbackURL = nil
        failed = false
        let server = OAuthLoopbackCallbackServer(port: 1455)
        try server.start(
            onReady: { [weak self] _ in
                Task { @MainActor in
                    self?.isListening = true
                }
            },
            onCallback: { [weak self] callbackURL in
                Task { @MainActor in
                    self?.callbackURL = callbackURL
                }
            },
            onFailure: { [weak self] in
                Task { @MainActor in
                    self?.isActive = false
                    self?.isListening = false
                    self?.failed = true
                }
            }
        )
        self.server = server
        isActive = true
    }

    func stop() {
        server?.stop()
        server = nil
        isActive = false
        isListening = false
    }
}

public struct QuotaSettingsView: View {
    @ObservedObject public var model: QuotaBarModel
    private let onDone: (() -> Void)?
    private let updateAction: (@MainActor () -> Void)?
    @StateObject private var loopbackCoordinator = OAuthLoopbackCoordinator()
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
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.blue, in: RoundedRectangle(cornerRadius: 7))
                Button(L10n.string("provider.sign_in_codex")) {
                    startOAuthLogin(for: .codex)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.blue, in: RoundedRectangle(cornerRadius: 7))
            }

            if let oauthRequest {
                if oauthRequest.provider == .codex && loopbackCoordinator.isActive {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(
                            L10n.string("oauth.auto_callback_waiting"),
                            systemImage: "arrow.triangle.2.circlepath"
                        )
                        .font(.caption)
                        Text(L10n.string("oauth.auto_callback_description"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Button(L10n.string("common.cancel")) {
                            cancelOAuthLogin()
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(10)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                } else {
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
                                cancelOAuthLogin()
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    .padding(10)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                }
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
        .onChange(of: loopbackCoordinator.callbackURL) { _, callbackURL in
            guard let callbackURL, let request = oauthRequest else { return }
            callbackInput = callbackURL
            Task { await completeOAuthLogin(request) }
        }
        .onChange(of: loopbackCoordinator.failed) { _, failed in
            if failed {
                oauthError = L10n.string("error.local_callback_unavailable")
            }
        }
        .onDisappear {
            loopbackCoordinator.stop()
        }
    }

    private func startOAuthLogin(for provider: QuotaProviderID) {
        do {
            let request = try OAuthAuthorizationConfiguration.makeRequest(for: provider)
            oauthRequest = request
            callbackInput = ""
            oauthError = nil
            if provider == .codex {
                do {
                    try loopbackCoordinator.start()
                } catch {
                    loopbackCoordinator.failed = true
                    oauthError = L10n.string("error.local_callback_unavailable")
                }
            }
            NSWorkspace.shared.open(request.url)
        } catch {
            oauthError = L10n.string("error.browser_login_failed")
        }
    }

    private func completeOAuthLogin(_ request: OAuthAuthorizationRequest) async {
        isCompletingOAuth = true
        oauthError = nil
        defer {
            isCompletingOAuth = false
            loopbackCoordinator.stop()
        }
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

    private func cancelOAuthLogin() {
        loopbackCoordinator.stop()
        oauthRequest = nil
        callbackInput = ""
        oauthError = nil
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
