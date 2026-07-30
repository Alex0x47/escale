import EscaleCore
import SwiftUI

public struct SidebarView: View {
    public init() {}

    @EnvironmentObject private var store: WorkspaceStore
    @Environment(\.escaleCommercialActions) private var commercialActions
    @Environment(\.openURL) private var openURL
    @AppStorage("escale.pro-promotion.started-at.v1") private var promotionStartedAtValue = 0.0
    @State private var showsConnections = false
    @State private var isProductSelectorHovered = false
    @State private var isAppSelectorPresented = false
    @State private var showsOfficialDownloadPrompt = false
    @State private var pairingRequest: AppPairingRequest?
    @State private var selectedStoreVersion: StoreApp?
    @State private var newIOSVersionRequest: NewIOSVersionRequest?
    @State private var showingNewAndroidVersion = false

    public var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 14) {
                HStack(spacing: 10) {
                    EscaleAppIcon(size: 36)
                        .shadow(color: .black.opacity(0.16), radius: 5, y: 2)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Escale").font(.headline)
                        Text("Store operations").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { showsConnections = true } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                    .buttonStyle(.plain)
                    .help("Connections and settings")
                }

                Link(destination: URL(string: "https://litefeedback.com/roadmap/Escale")!) {
                    Label("Feedback & requests", systemImage: "bubble.left.and.bubble.right.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                .buttonStyle(.plain)
                .help("Open the Escale feedback board")
            }
            .padding(16)

            productSelector
                .padding(.horizontal, 14)
                .padding(.bottom, 14)

            Divider()

            if let app = store.selectedApp {
                VStack(spacing: 3) {
                    ForEach(AppSection.allCases) { section in
                        SectionRow(section: section, selected: section == store.selectedSection)
                            .contentShape(Rectangle())
                            .onTapGesture { store.selectedSection = section }
                    }
                }
                .padding(10)

                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("STORE VERSIONS")
                            .font(.caption2.weight(.bold))
                            .tracking(0.8)
                            .foregroundStyle(.secondary)
                        if let ios = app.appStoreApp {
                            VStack(spacing: 4) {
                                StoreVersionRow(app: ios) { selectedStoreVersion = ios }
                                NewStoreVersionButton(
                                    platform: .appStore,
                                    isDisabled: ios.hasEditableMetadataVersion
                                ) {
                                    openNewIOSVersion(ios)
                                }
                                .help(
                                    ios.hasEditableMetadataVersion
                                        ? "An editable App Store version already exists"
                                        : "Create a new editable App Store version"
                                )
                            }
                        }
                        if let android = app.playStoreApp {
                            VStack(spacing: 4) {
                                StoreVersionRow(app: android) { selectedStoreVersion = android }
                                NewStoreVersionButton(platform: .playStore) {
                                    openNewAndroidVersion()
                                }
                                .help("Upload a signed bundle and create a Google Play draft")
                            }
                        }
                        if app.linkedCount == 1 {
                            Button {
                                pairingRequest = AppPairingRequest(appID: app.id)
                            } label: {
                                HStack(spacing: 7) {
                                    Image(systemName: "link.badge.plus")
                                        .font(.caption.weight(.semibold))
                                    Text("Pair this app")
                                        .font(.caption.weight(.semibold))
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption2.weight(.bold))
                                }
                                .foregroundStyle(Theme.accent)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 7)
                                .background(Theme.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help(
                                app.appStoreApp == nil
                                    ? "Pair this product with its App Store record"
                                    : "Pair this product with its Google Play record"
                            )
                        }
                    }
                    .padding(14)
                }
            } else {
                Spacer()
            }

            Divider()
            Button { showsConnections = true } label: {
                HStack(spacing: 8) {
                    connectionDot(.appStore)
                    connectionDot(.playStore)
                    Text("Stores connected")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("Manage")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Theme.accent)
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
            .help("Connect or disconnect store accounts")

            if store.entitlements.plan != .pro {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let startedAt = promotionStartedAt
                    let remaining = max(
                        0,
                        Self.promotionDuration - context.date.timeIntervalSince(startedAt)
                    )
                    if remaining > 0 {
                        Button {
                            openPromotion(startedAt: startedAt)
                        } label: {
                            ProPromotionBanner(remaining: remaining)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 10)
                        .padding(.bottom, 10)
                        .help("Get 30% off Escale Pro")
                    }
                }
            }
        }
        .background(Theme.sidebar)
        .onAppear {
            if promotionStartedAtValue == 0 {
                promotionStartedAtValue = Date().timeIntervalSince1970
            }
        }
        .alert("Download the official Escale app", isPresented: $showsOfficialDownloadPrompt) {
            Button("Not now", role: .cancel) {}
            Button("Open download page") {
                openURL(EscaleLinks.officialDownloadPage)
            }
        } message: {
            Text("Pro purchases and licence activation are available only in the official Escale download. Your Community workspace will remain available.")
        }
        .sheet(isPresented: $showsConnections) {
            SettingsView().environmentObject(store).frame(width: 680, height: 650)
        }
        .sheet(item: $pairingRequest) { request in
            AppPairingView(appID: request.appID)
                .environmentObject(store)
        }
        .sheet(item: $selectedStoreVersion) { app in
            StoreVersionDetailsSheet(app: app)
                .frame(width: 680, height: 650)
        }
        .sheet(item: $newIOSVersionRequest) { request in
            NewIOSVersionSheet(initialVersion: request.suggestedVersion)
                .environmentObject(store)
        }
        .sheet(isPresented: $showingNewAndroidVersion) {
            NewAndroidVersionSheet()
                .environmentObject(store)
        }
    }

    private static let promotionDuration: TimeInterval = 12 * 60 * 60
    private var promotionStartedAt: Date {
        guard promotionStartedAtValue > 0 else { return Date() }
        return Date(timeIntervalSince1970: promotionStartedAtValue)
    }

    private func openNewIOSVersion(_ app: StoreApp) {
        guard !app.hasEditableMetadataVersion else { return }
        newIOSVersionRequest = NewIOSVersionRequest(
            suggestedVersion: suggestedNextAppStoreVersion(from: app.version)
        )
    }

    private func openNewAndroidVersion() {
        showingNewAndroidVersion = true
    }

    private func openPromotion(startedAt: Date) {
        guard let promotionCheckoutURL = commercialActions?.promotionCheckoutURL else {
            showsOfficialDownloadPrompt = true
            return
        }

        Task {
            guard let url = await promotionCheckoutURL(startedAt) else {
                store.showToast(
                    "The launch offer is unavailable",
                    detail: "Check your connection and try again before the timer expires.",
                    kind: .error
                )
                return
            }
            openURL(url)
        }
    }

    @ViewBuilder
    private var productSelector: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("CURRENT APP")
                    .font(.caption2.weight(.bold))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
            }

            if let selectedApp = store.selectedApp {
                Button {
                    isAppSelectorPresented.toggle()
                } label: {
                    HStack(spacing: 11) {
                        AppMark(app: selectedApp, size: 42)
                            .frame(width: 42, height: 42)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(selectedApp.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            HStack(spacing: 5) {
                                if selectedApp.appStoreApp != nil { PlatformBadge(platform: .appStore, showsName: false) }
                                if selectedApp.playStoreApp != nil { PlatformBadge(platform: .playStore, showsName: false) }
                                Text(selectedApp.linkedCount == 2 ? "Paired" : "Unpaired")
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(selectedApp.linkedCount == 2 ? .green : .orange)
                            }
                        }
                        Spacer()
                        VStack(spacing: 2) {
                            Text("Switch")
                                .font(.system(size: 9, weight: .semibold))
                            Image(systemName: "chevron.down")
                                .font(.system(size: 9, weight: .bold))
                        }
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(Theme.accent.opacity(0.1), in: Capsule())
                    }
                    .padding(.horizontal, 11)
                    .frame(maxWidth: .infinity, minHeight: 64, maxHeight: 64)
                    .background(
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .fill(isProductSelectorHovered ? Theme.accent.opacity(0.055) : Theme.card)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .stroke(isProductSelectorHovered ? Theme.accent.opacity(0.6) : Theme.accent.opacity(0.28), lineWidth: isProductSelectorHovered ? 1.5 : 1)
                    )
                    .shadow(color: .black.opacity(isProductSelectorHovered ? 0.09 : 0.045), radius: 7, y: 3)
                    .clipped()
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { isProductSelectorHovered = $0 }
                .help("Choose a different app workspace")
                .popover(isPresented: $isAppSelectorPresented, arrowEdge: .trailing) {
                    appSelectorPopover
                }
            } else {
                Text("No apps imported")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .cardStyle(cornerRadius: 12)
            }
        }
    }

    private var appSelectorPopover: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Switch app").font(.headline)
                Text("Choose the product workspace to manage.").font(.caption).foregroundStyle(.secondary)
            }
            .padding(14)
            Divider()
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(store.workspace.apps) { app in
                        Button {
                            store.selectedAppID = app.id
                            store.selectedSection = .overview
                            isAppSelectorPresented = false
                        } label: {
                            HStack(spacing: 11) {
                                AppMark(app: app, size: 36)
                                    .frame(width: 36, height: 36)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(app.name)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    Text(app.appStoreApp?.bundleID ?? app.playStoreApp?.bundleID ?? "No store identifier")
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                if app.id == store.selectedAppID {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Theme.accent)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(app.id == store.selectedAppID ? Theme.accent.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(7)
            }
            .frame(maxHeight: 430)
        }
        .frame(width: 330)
        .background(Theme.card)
    }

    @ViewBuilder
    private func connectionDot(_ platform: StorePlatform) -> some View {
        let connected = store.workspace.connections.first(where: { $0.platform == platform })?.state == .connected
        Circle().fill(connected ? platform.tint : Color.secondary).frame(width: 7, height: 7)
    }
}

private struct ProPromotionBanner: View {
    let remaining: TimeInterval

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Label("12-HOUR OFFER", systemImage: "sparkles")
                    .font(.caption2.weight(.heavy))
                    .tracking(0.7)
                Spacer()
                Text("-30%")
                    .font(.caption.weight(.heavy))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(.white.opacity(0.2), in: Capsule())
            }

            Text("Unlock Escale Pro")
                .font(.subheadline.weight(.bold))

            HStack(spacing: 6) {
                Image(systemName: "clock.fill")
                Text("Ends in \(formattedRemaining)")
                    .monospacedDigit()
                Spacer()
                Image(systemName: "arrow.right.circle.fill")
                    .font(.system(size: 17, weight: .semibold))
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white.opacity(0.9))
        }
        .foregroundStyle(.white)
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Color(hex: 0xFF6B35), Color(hex: 0x7C3AED)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.white.opacity(0.18))
        )
        .shadow(color: Color(hex: 0x7C3AED).opacity(0.22), radius: 12, y: 5)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("30 percent off Escale Pro")
        .accessibilityValue("Offer ends in \(formattedRemaining)")
    }

    private var formattedRemaining: String {
        let seconds = max(0, Int(remaining.rounded(.down)))
        return String(
            format: "%02d:%02d:%02d",
            seconds / 3_600,
            (seconds % 3_600) / 60,
            seconds % 60
        )
    }
}

private struct SectionRow: View {
    let section: AppSection
    let selected: Bool

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: section.icon)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 20)
                .foregroundStyle(selected ? Theme.accent : .secondary)
            Text(section.rawValue).font(.subheadline.weight(selected ? .semibold : .regular))
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(selected ? Theme.accent.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

private struct StoreVersionRow: View {
    let app: StoreApp
    let action: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: action) {
                HStack(spacing: 8) {
                    Image(systemName: app.platform.icon).foregroundStyle(app.platform.tint).frame(width: 16)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(app.platform.shortName) · \(app.version)").font(.caption.weight(.semibold))
                        Text(app.state.rawValue).font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Circle().fill(app.state.color).frame(width: 7, height: 7)
                }
                .padding(.leading, 8)
                .padding(.vertical, 7)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Show \(app.platform.rawValue) version details")

            if let consoleURL = app.developerConsoleURL {
                Link(destination: consoleURL) {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 26, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open in \(app.platform.developerConsoleName)")
                .help("Open in \(app.platform.developerConsoleName)")
            }
        }
        .background(Color.primary.opacity(0.001), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct NewStoreVersionButton: View {
    let platform: StorePlatform
    var isDisabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(
                "New \(platform.shortName) version",
                systemImage: "plus.circle.fill"
            )
            .font(.caption2.weight(.semibold))
            .foregroundStyle(isDisabled ? Color.secondary : platform.tint)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(
                (isDisabled ? Color.secondary : platform.tint).opacity(0.08),
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .padding(.leading, 24)
    }
}

private struct StoreVersionDetailsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let app: StoreApp

    private struct DetailField: Identifiable {
        let label: String
        let value: String
        var id: String { label }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: app.platform.icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(app.platform.tint)
                    .frame(width: 44, height: 44)
                    .background(app.platform.tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(app.platform.shortName) · \(app.version)")
                        .font(.title2.weight(.bold))
                    Text("\(app.name) · Latest data returned by \(app.platform.rawValue)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                StatusPill(state: app.state)
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .background(Color.primary.opacity(0.06), in: Circle())
                .help("Close")
            }
            .padding(22)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    detailSection("VERSION", fields: versionFields)

                    if !releaseFields.isEmpty {
                        detailSection(
                            app.platform == .appStore ? "APP STORE RELEASE" : "GOOGLE PLAY RELEASE",
                            fields: releaseFields
                        )
                    }

                    if let notes = app.versionDetails?.releaseNotes, !notes.isEmpty {
                        releaseNotesSection(notes)
                    }

                    Label(
                        "These values reflect the most recent successful store sync.",
                        systemImage: "arrow.triangle.2.circlepath"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
                }
                .padding(22)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Theme.canvas)
    }

    private var versionFields: [DetailField] {
        var fields = [
            DetailField(label: app.platform == .appStore ? "Version" : "Latest build", value: app.version),
            DetailField(label: "Status", value: app.state.rawValue),
            DetailField(
                label: app.platform == .appStore ? "Bundle identifier" : "Package name",
                value: app.bundleID
            ),
            DetailField(
                label: app.platform == .appStore ? "Apple app ID" : "Store identifier",
                value: app.storeID
            )
        ]
        append(app.remoteState.map(displayAPIValue), label: "API status", to: &fields)
        append(app.primaryLocale, label: "Primary locale", to: &fields)
        append(app.versionID, label: "Version resource ID", to: &fields)
        append(app.appInfoID, label: "App info resource ID", to: &fields)
        return fields
    }

    private var releaseFields: [DetailField] {
        guard let details = app.versionDetails else { return [] }
        var fields: [DetailField] = []

        if app.platform == .appStore {
            append(details.platformName.map(displayAPIValue), label: "Platform", to: &fields)
            append(details.releaseType.map(displayAPIValue), label: "Release type", to: &fields)
            append(details.reviewType.map(displayAPIValue), label: "Review type", to: &fields)
            append(details.createdDate.map(formattedDate), label: "Created", to: &fields)
            append(details.earliestReleaseDate.map(formattedDate), label: "Earliest release", to: &fields)
            append(details.copyright, label: "Copyright", to: &fields)
            append(details.downloadable.map(yesNo), label: "Downloadable", to: &fields)
            append(details.usesIDFA.map(yesNo), label: "Uses IDFA", to: &fields)
        } else {
            append(details.track.map(displayAPIValue), label: "Track", to: &fields)
            append(details.releaseName, label: "Release name", to: &fields)
            append(details.versionCodes?.joined(separator: ", "), label: "Version codes", to: &fields)
            append(
                details.userFraction.map {
                    $0.formatted(.percent.precision(.fractionLength(0...2)))
                },
                label: "Staged rollout",
                to: &fields
            )
            append(
                details.inAppUpdatePriority.map { "\($0) of 5" },
                label: "In-app update priority",
                to: &fields
            )
            append(details.countryTargeting.map(countryTargeting), label: "Country targeting", to: &fields)
            append(details.bundleSHA1, label: "Bundle SHA-1", to: &fields)
            append(details.bundleSHA256, label: "Bundle SHA-256", to: &fields)
        }

        return fields
    }

    private func detailSection(_ title: String, fields: [DetailField]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.caption2.weight(.bold))
                .tracking(0.75)
                .foregroundStyle(.secondary)
                .padding(.bottom, 10)
            VStack(spacing: 0) {
                ForEach(Array(fields.enumerated()), id: \.element.id) { index, field in
                    HStack(alignment: .firstTextBaseline, spacing: 18) {
                        Text(field.label)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 145, alignment: .leading)
                        Text(field.value)
                            .font(.subheadline)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    if index < fields.count - 1 {
                        Divider().padding(.leading, 173)
                    }
                }
            }
            .background(Theme.card.opacity(0.75), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(Theme.border))
        }
    }

    private func releaseNotesSection(_ notes: [StoreVersionReleaseNote]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("RELEASE NOTES")
                .font(.caption2.weight(.bold))
                .tracking(0.75)
                .foregroundStyle(.secondary)
            ForEach(Array(notes.enumerated()), id: \.offset) { _, note in
                VStack(alignment: .leading, spacing: 7) {
                    Text(localizedLanguage(note.language))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(app.platform.tint)
                    Text(note.text)
                        .font(.subheadline)
                        .lineSpacing(3)
                        .textSelection(.enabled)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.card.opacity(0.75), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(Theme.border))
            }
        }
    }

    private func append(_ value: String?, label: String, to fields: inout [DetailField]) {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        fields.append(DetailField(label: label, value: value))
    }

    private func formattedDate(_ date: Date) -> String {
        date.formatted(date: .long, time: .shortened)
    }

    private func yesNo(_ value: Bool) -> String {
        value ? "Yes" : "No"
    }

    private func countryTargeting(_ targeting: StoreCountryTargeting) -> String {
        var parts = targeting.countries.sorted()
        if targeting.includesRestOfWorld { parts.append("Rest of world") }
        return parts.isEmpty ? "No countries returned" : parts.joined(separator: ", ")
    }

    private func localizedLanguage(_ identifier: String) -> String {
        let name = Locale.current.localizedString(forIdentifier: identifier) ?? identifier
        return "\(name) · \(identifier)"
    }

    private func displayAPIValue(_ value: String) -> String {
        switch value {
        case "IOS": return "iOS"
        case "APP_STORE": return "App Store"
        case "inProgress": return "In progress"
        case "statusUnspecified": return "Unspecified"
        default:
            return value
                .replacingOccurrences(of: "_", with: " ")
                .lowercased()
                .capitalized
        }
    }
}
