import EscaleCore
import SwiftUI
import UniformTypeIdentifiers

public struct ScreenshotsView: View {
    public init() {}

    @EnvironmentObject private var store: WorkspaceStore
    @State private var selectedLocale = "en-US"
    @State private var device = "Phone"
    @State private var importsScreenshot = false

    private var visibleScreenshots: [StoreScreenshot] {
        store.selectedScreenshots.filter { screenshot in
            store.platformFilter.platforms.contains(screenshot.platform) && screenshot.locale == selectedLocale && matchesDevice(screenshot.device)
        }
    }

    private func matchesDevice(_ remoteDevice: String) -> Bool {
        switch device {
        case "All devices": true
        case "Phone": remoteDevice == "Phone" || remoteDevice.localizedCaseInsensitiveContains("iPhone")
        case "Tablet": remoteDevice.localizedCaseInsensitiveContains("iPad") || remoteDevice.localizedCaseInsensitiveContains("Tablet")
        case "Desktop": remoteDevice.localizedCaseInsensitiveContains("Desktop")
        case "TV": remoteDevice.localizedCaseInsensitiveContains("TV")
        default: remoteDevice == device
        }
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 23) {
                HStack(alignment: .bottom) {
                    SectionTitle("Screenshots", subtitle: "Build one visual story and adapt it to each store.", eyebrow: "Store presence")
                    Spacer()
                    Picker("Locale", selection: $selectedLocale) {
                        ForEach(store.selectedLocalizations) { localization in
                            Text(localization.language).tag(localization.locale)
                        }
                    }
                    .frame(width: 150)
                    Picker("Device", selection: $device) {
                        Text("All devices").tag("All devices")
                        Text("Phone").tag("Phone")
                        Text("Tablet").tag("Tablet")
                        Text("Desktop").tag("Desktop")
                        Text("TV").tag("TV")
                    }
                    .frame(width: 145)
                    Button {
                        importsScreenshot = true
                    } label: {
                        Label("Add screenshot", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                }

                HStack(spacing: 7) {
                    Image(systemName: "arrow.left.and.right")
                    Text("Assets are read from the live store. Upload or delete frames here, then sync to confirm processing.")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if visibleScreenshots.isEmpty {
                    EmptyState(icon: "photo.badge.plus", title: "No screenshots here", message: "Add a frame for this store, language, and device.")
                        .frame(maxWidth: .infinity)
                        .cardStyle()
                } else {
                    ScrollView(.horizontal, showsIndicators: true) {
                        LazyHStack(alignment: .top, spacing: 18) {
                            ForEach(Array(visibleScreenshots.enumerated()), id: \.element.id) { index, screenshot in
                                ScreenshotCard(screenshot: screenshot, number: index + 1) {
                                    store.deleteScreenshot(screenshot.id)
                                }
                            }
                            addCard
                        }
                        .padding(.bottom, 14)
                    }
                }

                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 9) {
                        Label("Store asset upload", systemImage: "arrow.up.circle")
                            .font(.headline).foregroundStyle(Theme.accent)
                        Text("Upload a PNG or JPEG to the selected store and locale. Escale uses each store’s native asset-upload transaction and refreshes the live gallery afterward.")
                            .font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Button("Upload another") {
                        importsScreenshot = true
                    }
                    .labelStyle(.titleAndIcon)
                    .buttonStyle(.bordered)
                }
                .padding(20)
                .background(LinearGradient(colors: [Theme.accent.opacity(0.1), Color.cyan.opacity(0.05)], startPoint: .leading, endPoint: .trailing), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.accent.opacity(0.16)))
            }
            .padding(28)
            .frame(maxWidth: 1350, alignment: .leading)
        }
        .background(Theme.canvas)
        .navigationTitle("Screenshots")
        .onAppear {
            if !store.selectedLocalizations.contains(where: { $0.locale == selectedLocale }), let locale = store.selectedLocalizations.first?.locale {
                selectedLocale = locale
            }
        }
        .onChange(of: store.selectedLocalizations.map(\.locale)) { _, locales in
            if !locales.contains(selectedLocale), let locale = locales.first {
                selectedLocale = locale
            }
        }
        .fileImporter(isPresented: $importsScreenshot, allowedContentTypes: [.png, .jpeg], allowsMultipleSelection: false) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            Task { await store.uploadScreenshot(fileURL: url, locale: selectedLocale, device: device == "All devices" ? "Phone" : device) }
        }
    }

    private var addCard: some View {
        Button { importsScreenshot = true } label: {
            VStack(spacing: 12) {
                Image(systemName: "plus").font(.system(size: 24, weight: .semibold))
                Text("Add frame").font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(Theme.accent)
            .frame(width: 218, height: 455)
            .background(Theme.accent.opacity(0.045), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Theme.accent.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [6])))
        }
        .buttonStyle(.plain)
    }
}

private struct ScreenshotCard: View {
    let screenshot: StoreScreenshot
    let number: Int
    let onDelete: () -> Void
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topTrailing) {
                if let urlString = screenshot.remoteURL, let url = URL(string: urlString), url.scheme?.hasPrefix("http") == true {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image { image.resizable().scaledToFill() }
                        else if phase.error != nil { screenshotPlaceholder }
                        else { ProgressView().tint(.white) }
                    }
                } else {
                    screenshotPlaceholder
                }
                if hovering {
                    Menu {
                        Button("Duplicate", systemImage: "plus.square.on.square") {}
                        Divider()
                        Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
                    } label: {
                        Image(systemName: "ellipsis").foregroundStyle(.white).padding(9).background(.black.opacity(0.2), in: Circle())
                    }
                    .menuStyle(.borderlessButton)
                    .padding(10)
                }
            }
            .frame(width: 218, height: 455)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: Color(hex: screenshot.gradientStartHex).opacity(0.22), radius: 14, y: 8)
            .scaleEffect(hovering ? 1.012 : 1)
            .animation(.easeOut(duration: 0.16), value: hovering)
            .onHover { hovering = $0 }
            HStack {
                Text("\(number)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Text(screenshot.device).font(.caption.weight(.semibold))
                Spacer()
                PlatformBadge(platform: screenshot.platform, showsName: false)
            }
            .frame(width: 218)
        }
    }

    private var screenshotPlaceholder: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: screenshot.gradientStartHex), Color(hex: screenshot.gradientEndHex)], startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle().fill(.white.opacity(0.08)).frame(width: 210).offset(x: 60, y: -160)
            VStack(spacing: 9) {
                Text(screenshot.title).font(.system(size: 20, weight: .bold, design: .rounded)).multilineTextAlignment(.center).foregroundStyle(.white).padding(.horizontal, 14)
                Text(screenshot.caption).font(.caption).foregroundStyle(.white.opacity(0.75))
                Spacer()
                phoneMockup
            }
            .padding(.top, 32)
        }
    }

    private var phoneMockup: some View {
        VStack(spacing: 12) {
            Capsule().fill(Color.primary.opacity(0.14)).frame(width: 45, height: 5)
            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 6).fill(Theme.accent.opacity(0.18)).frame(height: 42)
                Text("Today").font(.caption.weight(.bold))
                ForEach(0..<4, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 3).fill(Color.primary.opacity(index == 3 ? 0.06 : 0.1)).frame(height: 7)
                }
                Spacer()
                HStack { Circle().fill(Theme.accent).frame(width: 8, height: 8); Text("Daily reflection").font(.system(size: 8)); Spacer() }
            }
            .padding(13)
        }
        .padding(.top, 9)
        .frame(width: 168, height: 300, alignment: .top)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 23, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 23, style: .continuous).stroke(.white.opacity(0.4), lineWidth: 4))
        .shadow(color: .black.opacity(0.18), radius: 9, y: 5)
        .offset(y: 13)
    }
}
