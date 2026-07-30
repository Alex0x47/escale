import AppKit
import EscaleCore
import SwiftUI
import UniformTypeIdentifiers

private struct ScreenshotGallery: Identifiable {
    let id: String
    let title: String
    let screenshots: [StoreScreenshot]
}

public struct ScreenshotsView: View {
    public init() {}

    @EnvironmentObject private var store: WorkspaceStore
    @State private var selectedLocale = "en-US"
    @State private var selectedGalleryPlatform = StorePlatform.appStore
    @State private var device = "Phone"
    @State private var importsScreenshot = false
    @State private var isFileDropTargeted = false

    private var availablePlatforms: [StorePlatform] {
        StorePlatform.allCases.filter(store.selectedAvailablePlatforms.contains)
    }

    private var activePlatform: StorePlatform {
        switch store.platformFilter {
        case .appStore:
            .appStore
        case .playStore:
            .playStore
        case .both:
            availablePlatforms.contains(selectedGalleryPlatform)
                ? selectedGalleryPlatform
                : availablePlatforms.first ?? selectedGalleryPlatform
        }
    }

    private var showsStoreSwitcher: Bool {
        store.platformFilter == .both && availablePlatforms.count > 1
    }

    private var pendingChangeCount: Int {
        store.pendingScreenshotChangeCount(for: activePlatform)
    }

    private var isSavingToStore: Bool {
        store.savingScreenshotPlatforms.contains(activePlatform)
    }

    private var isAnyStoreSaving: Bool {
        !store.savingScreenshotPlatforms.isEmpty
    }

    private var isAnyScreenshotOperationRunning: Bool {
        isAnyStoreSaving || !store.deletingScreenshotIDs.isEmpty
    }

    private var deviceOptions: [String] {
        switch activePlatform {
        case .appStore:
            ["All devices", "Phone", "Tablet", "Desktop", "TV"]
        case .playStore:
            ["All devices", "Phone", "Tablet 7″", "Tablet 10″", "TV"]
        }
    }

    private var galleries: [ScreenshotGallery] {
        let screenshots = store.selectedScreenshots.filter {
            $0.platform == activePlatform
                && canonicalStoreLocale($0.locale) == canonicalStoreLocale(selectedLocale)
                && matchesSelectedDevice($0.device)
        }
        var keys: [String] = []
        var grouped: [String: [StoreScreenshot]] = [:]
        for screenshot in screenshots {
            let galleryID = screenshot.screenshotSetID ?? screenshot.device.lowercased()
            if grouped[galleryID] == nil { keys.append(galleryID) }
            grouped[galleryID, default: []].append(screenshot)
        }
        return keys.compactMap { key in
            guard let screenshots = grouped[key], let first = screenshots.first else { return nil }
            return ScreenshotGallery(
                id: "\(activePlatform.rawValue)|\(canonicalStoreLocale(selectedLocale))|\(key)",
                title: first.device,
                screenshots: screenshots
            )
        }
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header

                if showsStoreSwitcher {
                    Picker("Screenshot store", selection: $selectedGalleryPlatform) {
                        ForEach(availablePlatforms) { platform in
                            Label(platform.rawValue, systemImage: platform.icon).tag(platform)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 340)
                    .disabled(isAnyScreenshotOperationRunning)
                    .accessibilityLabel("Screenshot store")
                }

                HStack(spacing: 7) {
                    Image(systemName: "square.and.pencil")
                    Text("Add and reorder freely, then choose Save to store. Deletions are applied immediately.")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if galleries.isEmpty {
                    EmptyState(
                        icon: "photo.badge.plus",
                        title: "No \(activePlatform.shortName) screenshots here",
                        message: "Add a PNG or JPEG for this language and device gallery."
                    )
                    .frame(maxWidth: .infinity)
                    .cardStyle()
                } else {
                    ForEach(galleries) { gallery in
                        gallerySection(gallery)
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 1_350, alignment: .leading)
        }
        .background(Theme.canvas)
        .navigationTitle("Screenshots")
        .overlay {
            if isFileDropTargeted {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Theme.accent.opacity(0.08))
                    .overlay {
                        Label(
                            "Upload to \(activePlatform.rawValue)",
                            systemImage: "arrow.down.doc.fill"
                        )
                        .font(.title3.weight(.semibold))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 14)
                        .background(.regularMaterial, in: Capsule())
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Theme.accent, style: StrokeStyle(lineWidth: 2, dash: [8]))
                    )
                    .padding(12)
                    .allowsHitTesting(false)
            }
        }
        .animation(.easeOut(duration: 0.15), value: isFileDropTargeted)
        .dropDestination(for: URL.self) { urls, _ in
            let imageURLs = urls.filter(isSupportedScreenshot)
            guard !imageURLs.isEmpty else {
                store.showToast(
                    "Choose PNG or JPEG files",
                    detail: "Other dropped file types were ignored.",
                    kind: .neutral
                )
                return false
            }
            upload(imageURLs)
            return true
        } isTargeted: {
            isFileDropTargeted = $0
        }
        .onAppear(perform: normalizeSelections)
        .onChange(of: store.selectedLocalizations.map(\.locale)) { _, _ in
            normalizeSelections()
        }
        .onChange(of: store.selectedAvailablePlatforms) { _, _ in
            normalizeSelections()
        }
        .onChange(of: store.platformFilter) { _, _ in
            normalizeSelections()
        }
        .onChange(of: activePlatform) { _, _ in
            normalizeDevice()
        }
        .fileImporter(
            isPresented: $importsScreenshot,
            allowedContentTypes: [.png, .jpeg],
            allowsMultipleSelection: true
        ) { result in
            guard case .success(let urls) = result else { return }
            upload(urls)
        }
    }

    private var header: some View {
        HStack(alignment: .bottom) {
            SectionTitle(
                "Screenshots",
                subtitle: "Build one visual story and adapt it to each store.",
                eyebrow: "Store presence"
            )
            Spacer()
            Picker("Locale", selection: $selectedLocale) {
                ForEach(store.selectedLocalizations) { localization in
                    Text(localization.language).tag(localization.locale)
                }
            }
            .frame(width: 150)
            Picker("Device", selection: $device) {
                ForEach(deviceOptions, id: \.self) { option in
                    Text(option).tag(option)
                }
            }
            .frame(width: 145)
            Button {
                importsScreenshot = true
            } label: {
                Label("Add screenshot", systemImage: "plus")
            }
            .buttonStyle(.bordered)
            .disabled(
                !store.selectedAvailablePlatforms.contains(activePlatform)
                    || device == "All devices"
                    || isAnyScreenshotOperationRunning
            )
            .help(
                device == "All devices"
                    ? "Choose a device gallery before uploading"
                    : "Upload to \(activePlatform.rawValue)"
            )
            Button {
                Task {
                    await store.saveScreenshotChanges(for: activePlatform)
                }
            } label: {
                if isSavingToStore {
                    HStack(spacing: 7) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Saving…")
                    }
                } else {
                    Label("Save to store", systemImage: "arrow.up.circle.fill")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(pendingChangeCount == 0 || isAnyScreenshotOperationRunning)
            .help(
                pendingChangeCount == 0
                    ? "There are no unsaved \(activePlatform.shortName) screenshot changes"
                    : "Apply all pending screenshot changes to \(activePlatform.rawValue)"
            )
        }
    }

    private func gallerySection(_ gallery: ScreenshotGallery) -> some View {
        let hasPendingChanges = gallery.screenshots.first.map {
            store.screenshotGalleryHasPendingChanges($0)
        } == true
        let isDeleting = gallery.screenshots.contains {
            store.deletingScreenshotIDs.contains($0.id)
        }
        let controlsDisabled = isAnyScreenshotOperationRunning
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: deviceIcon(for: gallery.title))
                    .foregroundStyle(activePlatform.tint)
                Text(gallery.title)
                    .font(.headline)
                Text("\(gallery.screenshots.count) of \(activePlatform == .appStore ? 10 : 8)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if isDeleting {
                    ProgressView()
                        .controlSize(.small)
                    Text("Deleting screenshot…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if isSavingToStore, hasPendingChanges {
                    ProgressView()
                        .controlSize(.small)
                    Text("Saving to store…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if hasPendingChanges {
                    Text("Unsaved changes")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.orange.opacity(0.12), in: Capsule())
                }
            }

            ScrollView(.horizontal, showsIndicators: true) {
                LazyHStack(alignment: .top, spacing: 8) {
                    ScreenshotInsertionTarget(
                        before: gallery.screenshots.first?.id,
                        isEnabled: !controlsDisabled,
                        onMove: moveScreenshot
                    )
                    ForEach(Array(gallery.screenshots.enumerated()), id: \.element.id) { index, screenshot in
                        ScreenshotCard(
                            screenshot: screenshot,
                            number: index + 1,
                            isBusy: controlsDisabled,
                            isPendingUpload: screenshot.localDraftURL != nil
                                && screenshot.remoteID == nil,
                            onDelete: { store.deleteScreenshot(screenshot.id) }
                        )
                        ScreenshotInsertionTarget(
                            before: gallery.screenshots.indices.contains(index + 1)
                                ? gallery.screenshots[index + 1].id
                                : nil,
                            isEnabled: !controlsDisabled,
                            onMove: moveScreenshot
                        )
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 2)
            }
        }
    }

    private func moveScreenshot(_ screenshotID: UUID, before destinationID: UUID?) {
        Task {
            await store.reorderScreenshot(screenshotID, before: destinationID)
        }
    }

    private func upload(_ urls: [URL]) {
        guard !isAnyScreenshotOperationRunning else { return }
        guard device != "All devices" else {
            store.showToast(
                "Choose a device gallery",
                detail: "Select Phone, Tablet, Desktop, or TV before uploading screenshots.",
                kind: .neutral
            )
            return
        }
        let locale = selectedLocale
        let uploadDevice = device
        let platform = activePlatform
        Task {
            for url in urls {
                await store.uploadScreenshot(
                    fileURL: url,
                    locale: locale,
                    device: uploadDevice,
                    platform: platform
                )
            }
        }
    }

    private func isSupportedScreenshot(_ url: URL) -> Bool {
        guard let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType else {
            return false
        }
        return type.conforms(to: .png) || type.conforms(to: .jpeg)
    }

    private func normalizeSelections() {
        if store.platformFilter == .appStore {
            selectedGalleryPlatform = .appStore
        } else if store.platformFilter == .playStore {
            selectedGalleryPlatform = .playStore
        }
        if !availablePlatforms.contains(selectedGalleryPlatform),
           let first = availablePlatforms.first {
            selectedGalleryPlatform = first
        }
        let locales = store.selectedLocalizations.map(\.locale)
        if !locales.contains(selectedLocale), let first = locales.first {
            selectedLocale = first
        }
        normalizeDevice()
    }

    private func normalizeDevice() {
        if !deviceOptions.contains(device) {
            device = deviceOptions.contains("Phone") ? "Phone" : deviceOptions[0]
        }
    }

    private func matchesSelectedDevice(_ remoteDevice: String) -> Bool {
        switch device {
        case "All devices":
            true
        case "Phone":
            remoteDevice == "Phone" || remoteDevice.localizedCaseInsensitiveContains("iPhone")
        case "Tablet":
            remoteDevice.localizedCaseInsensitiveContains("iPad")
                || remoteDevice.localizedCaseInsensitiveContains("Tablet")
        case "Tablet 7″":
            remoteDevice.localizedCaseInsensitiveContains("Tablet")
                && remoteDevice.localizedCaseInsensitiveContains("7")
        case "Tablet 10″":
            remoteDevice.localizedCaseInsensitiveContains("Tablet")
                && remoteDevice.localizedCaseInsensitiveContains("10")
        case "Desktop":
            remoteDevice.localizedCaseInsensitiveContains("Desktop")
        case "TV":
            remoteDevice.localizedCaseInsensitiveContains("TV")
        default:
            remoteDevice == device
        }
    }

    private func deviceIcon(for remoteDevice: String) -> String {
        if remoteDevice.localizedCaseInsensitiveContains("TV") { return "tv" }
        if remoteDevice.localizedCaseInsensitiveContains("Desktop") { return "desktopcomputer" }
        if remoteDevice.localizedCaseInsensitiveContains("iPad")
            || remoteDevice.localizedCaseInsensitiveContains("Tablet") {
            return "ipad"
        }
        return "iphone"
    }
}

private struct ScreenshotInsertionTarget: View {
    let before: UUID?
    let isEnabled: Bool
    let onMove: (UUID, UUID?) -> Void
    @State private var isTargeted = false

    var body: some View {
        ZStack {
            Color.clear
            Capsule()
                .fill(Theme.accent)
                .frame(width: isTargeted ? 5 : 2, height: isTargeted ? 410 : 390)
                .opacity(isTargeted ? 1 : 0.18)
        }
        .frame(width: 28, height: 430)
        .contentShape(Rectangle())
        .animation(.easeOut(duration: 0.12), value: isTargeted)
        .dropDestination(for: String.self) { values, _ in
            guard isEnabled,
                  let value = values.first,
                  let draggedID = UUID(uuidString: value) else {
                return false
            }
            onMove(draggedID, before)
            return true
        } isTargeted: { targeted in
            isTargeted = isEnabled && targeted
        }
        .accessibilityLabel(before == nil ? "Move screenshot to end" : "Insert screenshot here")
    }
}

private struct ScreenshotCard: View {
    let screenshot: StoreScreenshot
    let number: Int
    let isBusy: Bool
    let isPendingUpload: Bool
    let onDelete: () -> Void
    @State private var hovering = false
    @State private var confirmsDeletion = false

    private let previewWidth: CGFloat = 230

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            screenshotImage
            .frame(width: previewWidth)
            .background(Color.black.opacity(0.84))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: Color(hex: screenshot.gradientStartHex).opacity(0.2), radius: 12, y: 7)
            .scaleEffect(hovering ? 1.008 : 1)
            .animation(.easeOut(duration: 0.16), value: hovering)
            .onHover { hovering = $0 }

            HStack(spacing: 7) {
                Image(systemName: "line.3.horizontal")
                    .foregroundStyle(.tertiary)
                Text("\(number)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Text(screenshot.device)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                PlatformBadge(platform: screenshot.platform, showsName: false)
                if isPendingUpload {
                    Text("NEW")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.orange)
                }
                Button {
                    confirmsDeletion = true
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.red)
                        .frame(width: 28, height: 28)
                        .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .help("Delete screenshot")
                .accessibilityLabel("Delete screenshot \(number)")
            }
            .frame(width: previewWidth)
        }
        .padding(4)
        .opacity(isBusy ? 0.58 : 1)
        .contentShape(Rectangle())
        .draggable(screenshot.id.uuidString) {
            Label("Move screenshot \(number)", systemImage: "photo")
                .font(.headline)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.regularMaterial, in: Capsule())
        }
        .disabled(isBusy)
        .help("Drag to reorder")
        .accessibilityLabel("Screenshot \(number)")
        .accessibilityHint("Drag to change its position in the gallery")
        .alert("Delete screenshot \(number)?", isPresented: $confirmsDeletion) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive, action: onDelete)
        } message: {
            if screenshot.remoteID == nil {
                Text("This removes the unsaved screenshot from your draft. The store will not be changed.")
            } else {
                Text("This immediately and permanently deletes the screenshot from \(screenshot.platform.rawValue). This action cannot be undone.")
            }
        }
    }

    @ViewBuilder
    private var screenshotImage: some View {
        if let localURLString = screenshot.localDraftURL,
           let localURL = URL(string: localURLString),
           let image = NSImage(contentsOf: localURL) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: previewWidth)
        } else if let urlString = screenshot.remoteURL, let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: previewWidth)
                } else if phase.error != nil {
                    screenshotPlaceholder
                } else {
                    ProgressView()
                        .tint(.white)
                        .frame(width: previewWidth, height: 410)
                }
            }
        } else {
            screenshotPlaceholder
        }
    }

    private var screenshotPlaceholder: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(hex: screenshot.gradientStartHex),
                    Color(hex: screenshot.gradientEndHex)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .fill(.white.opacity(0.08))
                .frame(width: 210)
                .offset(x: 60, y: -160)
            VStack(spacing: 9) {
                Text(screenshot.title)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                Text(screenshot.caption)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.75))
                Spacer()
                phoneMockup
            }
            .padding(.top, 32)
        }
        .frame(width: previewWidth, height: 455)
    }

    private var phoneMockup: some View {
        VStack(spacing: 12) {
            Capsule()
                .fill(Color.primary.opacity(0.14))
                .frame(width: 45, height: 5)
            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Theme.accent.opacity(0.18))
                    .frame(height: 42)
                Text("Today")
                    .font(.caption.weight(.bold))
                ForEach(0..<4, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.primary.opacity(index == 3 ? 0.06 : 0.1))
                        .frame(height: 7)
                }
                Spacer()
                HStack {
                    Circle().fill(Theme.accent).frame(width: 8, height: 8)
                    Text("Daily reflection").font(.system(size: 8))
                    Spacer()
                }
            }
            .padding(13)
        }
        .padding(.top, 9)
        .frame(width: 168, height: 300, alignment: .top)
        .background(
            Color(nsColor: .textBackgroundColor),
            in: RoundedRectangle(cornerRadius: 23, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 23, style: .continuous)
                .stroke(.white.opacity(0.4), lineWidth: 4)
        )
        .shadow(color: .black.opacity(0.18), radius: 9, y: 5)
        .offset(y: 13)
    }
}
