import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var store: WorkspaceStore
    @State private var showsConnections = false
    @State private var isProductSelectorHovered = false
    @State private var isAppSelectorPresented = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 14) {
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(LinearGradient(colors: [Theme.accent, Color(hex: 0x978BFF)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        Image(systemName: "helm").font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
                    }
                    .frame(width: 36, height: 36)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Gouvernail").font(.headline)
                        Text("Store operations").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { showsConnections = true } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                    .buttonStyle(.plain)
                    .help("Connections and settings")
                }

                Link(destination: URL(string: "https://litefeedback.com/roadmap/Gouvernail")!) {
                    Label("Feedback & requests", systemImage: "bubble.left.and.bubble.right.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                .buttonStyle(.plain)
                .help("Open the Gouvernail feedback board")
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
                        if let ios = app.appStoreApp { StoreVersionRow(app: ios) }
                        if let android = app.playStoreApp { StoreVersionRow(app: android) }
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

            Link(destination: URL(string: "https://acceptmy.app/")!) {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(Color.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Avoid App Review surprises")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                        Text("Preflight your app with AcceptMy.app")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "arrow.up.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white.opacity(0.85))
                }
                .padding(10)
                .background(
                    LinearGradient(
                        colors: [Color(hex: 0x29215A), Color(hex: 0x5E4FBC)],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
            .help("Open AcceptMy.app")
        }
        .background(Theme.sidebar)
        .sheet(isPresented: $showsConnections) {
            SettingsView().environmentObject(store).frame(width: 680, height: 650)
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

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: app.platform.icon).foregroundStyle(app.platform.tint).frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(app.platform.shortName) · \(app.version)").font(.caption.weight(.semibold))
                Text(app.state.rawValue).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Circle().fill(app.state.color).frame(width: 7, height: 7)
        }
    }
}
