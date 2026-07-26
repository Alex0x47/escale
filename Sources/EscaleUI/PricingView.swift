import EscaleCore
import SwiftUI

public struct PricingView: View {
    public init() {}

    @EnvironmentObject private var store: WorkspaceStore
    @State private var selectedProductID: UUID?
    @State private var search = ""
    @State private var isApplying = false
    @State private var showingMigrationConfirmation = false
    @State private var showingAppleDecreaseConfirmation = false
    @State private var proFeature: EscaleFeature?
    @State private var basePriceDraft = ""
    @State private var basePriceDraftProductID: UUID?
    @State private var basePriceValidationMessage: String?
    @FocusState private var isBasePriceFocused: Bool

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let productID = selectedProductID ?? store.selectedProducts.first?.id {
                pricingWorkspace(productID: productID)
            } else {
                EmptyState(icon: "tag.slash", title: "No products", message: "Sync an in-app purchase or subscription to calculate fair regional prices.")
            }
        }
        .background(Theme.canvas)
        .navigationTitle("PPP pricing")
        .onAppear { if selectedProductID == nil { selectedProductID = store.selectedProducts.first?.id } }
        .confirmationDialog(
            "Move existing subscribers to the new prices?",
            isPresented: $showingMigrationConfirmation,
            titleVisibility: .visible
        ) {
            Button("Apply and migrate subscribers", role: .destructive) { applySelectedProduct() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The stores may notify subscribers, and price increases can require consent. This cannot be silently undone by Escale.")
        }
        .confirmationDialog(
            "Apple will lower prices for existing subscribers",
            isPresented: $showingAppleDecreaseConfirmation,
            titleVisibility: .visible
        ) {
            Button("Schedule price decreases") { applySelectedProduct() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(appleDecreaseConfirmationMessage)
        }
        .sheet(item: $proFeature) { feature in
            ProFeatureSheet(feature: feature)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 18) {
            SectionTitle("Purchasing power pricing", subtitle: "Make your products more affordable without flattening every market.", eyebrow: "Monetization")
            Spacer()
            Picker("Product", selection: Binding(get: { selectedProductID ?? store.selectedProducts.first?.id }, set: { selectedProductID = $0 })) {
                ForEach(store.selectedProducts) { product in Text(product.name).tag(Optional(product.id)) }
            }
            .frame(width: 280)
        }
        .padding(24)
    }

    private func pricingWorkspace(productID: UUID) -> some View {
        let product = store.productBinding(id: productID)
        return HSplitView {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    productSummary(product: product)
                    HStack {
                        TextField("Search markets", text: $search).textFieldStyle(.roundedBorder).frame(maxWidth: 260)
                        Spacer()
                        Text(product.wrappedValue.pricingSourceSummary ?? "Choose an index, then calculate against current store regions").font(.caption).foregroundStyle(.secondary)
                    }
                    regionTable(product: product)
                }
                .padding(24)
            }
            pricingInspector(product: product)
                .id(productID)
                .frame(minWidth: 290, idealWidth: 330, maxWidth: 370)
        }
    }

    private func productSummary(product: Binding<StoreProduct>) -> some View {
        HStack(spacing: 16) {
            Image(systemName: "crown.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.orange)
                .frame(width: 52, height: 52)
                .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(product.wrappedValue.name).font(.headline)
                Text(product.wrappedValue.productID).font(.caption.monospaced()).foregroundStyle(.secondary)
            }
            Spacer()
            ForEach(product.wrappedValue.platforms.sorted(by: { $0.rawValue < $1.rawValue })) { PlatformBadge(platform: $0) }
            Divider().frame(height: 34)
            VStack(alignment: .trailing, spacing: 2) {
                Text("$\(product.wrappedValue.basePrice, specifier: "%.2f")").font(.title3.weight(.bold).monospacedDigit())
                Text("USD base price").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(17)
        .cardStyle()
    }

    private func regionTable(product: Binding<StoreProduct>) -> some View {
        let indices = product.wrappedValue.regions.indices
            .filter { index in
                search.isEmpty || product.wrappedValue.regions[index].country.localizedCaseInsensitiveContains(search)
            }
            .sorted { lhs, rhs in
                let left = product.wrappedValue.regions[lhs]
                let right = product.wrappedValue.regions[rhs]
                if left.code == "US" { return right.code != "US" }
                if right.code == "US" { return false }
                return left.country < right.country
            }
        return VStack(spacing: 0) {
            HStack {
                Text("MARKET").frame(maxWidth: .infinity, alignment: .leading)
                Text("PPP INDEX").frame(width: 90, alignment: .trailing)
                Text("CURRENT").frame(width: 105, alignment: .trailing)
                Text("SUGGESTED").frame(width: 112, alignment: .trailing)
                Text("APPLY").frame(width: 58, alignment: .trailing)
            }
            .font(.caption2.weight(.bold)).tracking(0.5).foregroundStyle(.secondary)
            .padding(.horizontal, 15).padding(.vertical, 12)
            Divider()
            ForEach(indices, id: \.self) { index in
                let region = product.regions[index]
                HStack {
                    HStack(spacing: 10) {
                        Text(region.wrappedValue.flag).font(.title3)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(region.wrappedValue.country).font(.subheadline.weight(.medium))
                                if region.wrappedValue.code == "US" {
                                    Text("BASE")
                                        .font(.system(size: 8, weight: .bold))
                                        .tracking(0.4)
                                        .foregroundStyle(Theme.accent)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 2)
                                        .background(Theme.accent.opacity(0.1), in: Capsule())
                                }
                            }
                            Text(region.wrappedValue.currency).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Text("\(Int(region.wrappedValue.pppIndex * 100))%")
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 90, alignment: .trailing)
                    Text("\(region.wrappedValue.currentPrice, specifier: "%.2f")")
                        .font(.subheadline.monospacedDigit()).frame(width: 105, alignment: .trailing)
                    Text("\(region.wrappedValue.suggestedPrice, specifier: "%.2f")")
                        .font(.subheadline.weight(.semibold).monospacedDigit()).foregroundStyle(region.wrappedValue.suggestedPrice < region.wrappedValue.currentPrice ? .green : .primary).frame(width: 112, alignment: .trailing)
                    Toggle("", isOn: region.enabled).labelsHidden().toggleStyle(.switch).controlSize(.mini).frame(width: 58, alignment: .trailing)
                }
                .padding(.horizontal, 15).padding(.vertical, 11)
                if index != indices.last { Divider().padding(.leading, 55) }
            }
        }
        .cardStyle()
    }

    private func pricingInspector(product: Binding<StoreProduct>) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("PRICING RULE").font(.caption2.weight(.bold)).tracking(0.7).foregroundStyle(.secondary)
                Text("Fair local pricing").font(.title3.weight(.bold))
                Text("Suggestions use purchasing power, then snap to the nearest store-friendly price point.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Text("Base market").font(.caption.weight(.semibold))
                HStack { Text("🇺🇸"); Text("United States"); Spacer(); Text("USD").foregroundStyle(.secondary) }
                    .font(.subheadline).padding(11).background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 9))
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack { Text("Proposed base price").font(.caption.weight(.semibold)); Spacer(); Text("USD").font(.caption).foregroundStyle(.secondary) }
                TextField("Base price", text: $basePriceDraft)
                    .textFieldStyle(.roundedBorder)
                    .focused($isBasePriceFocused)
                    .onSubmit {
                        guard commitBasePriceDraft(to: product) else { return }
                        isBasePriceFocused = false
                        Task { await store.calculatePPP(productID: product.wrappedValue.id) }
                    }
                    .onChange(of: basePriceDraft) { _, _ in
                        basePriceValidationMessage = nil
                    }
                if let basePriceValidationMessage {
                    Label(basePriceValidationMessage, systemImage: "exclamationmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let unitedStates = product.wrappedValue.regions.first(where: { $0.code == "US" }) {
                    HStack {
                        Text("Current US price")
                        Spacer()
                        Text("$\(unitedStates.currentPrice, specifier: "%.2f")")
                            .monospacedDigit()
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Pricing index").font(.caption.weight(.semibold))
                Picker("Pricing index", selection: Binding(
                    get: { product.wrappedValue.effectivePricingIndex },
                    set: { product.wrappedValue.pricingIndex = $0; product.wrappedValue.pricingCalculatedAt = nil }
                )) {
                    ForEach(PricingIndex.allCases) { index in Text(index.title).tag(index) }
                }
                .labelsHidden()
                Text(product.wrappedValue.effectivePricingIndex.detail).font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if product.wrappedValue.isSubscription {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Current subscribers").font(.caption.weight(.semibold))
                    Picker("Current subscribers", selection: Binding(
                        get: { product.wrappedValue.effectiveSubscriberPricePolicy },
                        set: { product.wrappedValue.subscriberPricePolicy = $0 }
                    )) {
                        ForEach(SubscriberPricePolicy.allCases) { policy in Text(policy.title).tag(policy) }
                    }
                    .labelsHidden()
                    Text(subscriberPolicyDetail(product.wrappedValue))
                        .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if product.wrappedValue.effectiveSubscriberPricePolicy == .preserve,
                       appStoreDecreaseCount(product.wrappedValue) > 0 {
                        Label(
                            "\(appStoreDecreaseCount(product.wrappedValue)) selected App Store decrease\(appStoreDecreaseCount(product.wrappedValue) == 1 ? "" : "s") will also apply to existing subscribers",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 9) {
                Label("\(product.wrappedValue.regions.filter(\.enabled).count) markets selected", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                Label("\(product.wrappedValue.platforms.count) connected store \(product.wrappedValue.platforms.count == 1 ? "catalog" : "catalogs")", systemImage: "rectangle.2.swap").foregroundStyle(Theme.accent)
                if product.wrappedValue.isSubscription {
                    Label(
                        subscriberPolicyBadge(product.wrappedValue),
                        systemImage: product.wrappedValue.effectiveSubscriberPricePolicy == .preserve ? "person.2.slash" : "person.2.badge.gearshape"
                    )
                    .foregroundStyle(.secondary)
                    if product.wrappedValue.platforms.contains(.appStore) {
                        Label("App Store changes start two days after applying", systemImage: "calendar.badge.clock").foregroundStyle(.secondary)
                    }
                }
            }
            .font(.caption.weight(.medium))
            if let progress = store.pricingApplyProgressByProductID[product.wrappedValue.id] {
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Label(progress.platform.rawValue, systemImage: progress.platform.icon)
                            .font(.caption.weight(.semibold))
                        Spacer()
                        Text("\(progress.completed) / \(progress.total)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    ProgressView(value: progress.fraction)
                        .progressViewStyle(.linear)
                    Text(progress.detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(11)
                .background(Theme.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Theme.accent.opacity(0.15)))
            }
            Spacer()
            Button {
                guard commitBasePriceDraft(to: product) else { return }
                isBasePriceFocused = false
                Task { await store.calculatePPP(productID: product.wrappedValue.id) }
            } label: {
                if store.calculatingProductIDs.contains(product.wrappedValue.id) {
                    HStack { ProgressView().controlSize(.small); Text("Calculating all markets…") }.frame(maxWidth: .infinity)
                } else { Label("Calculate pricing", systemImage: "function").frame(maxWidth: .infinity) }
            }
            .buttonStyle(.bordered).disabled(store.calculatingProductIDs.contains(product.wrappedValue.id))
            Button {
                guard store.hasAccess(to: .applyRegionalPricing) else {
                    proFeature = .applyRegionalPricing
                    return
                }
                guard product.wrappedValue.pricingCalculatedAt != nil,
                      basePriceDraftMatches(product.wrappedValue) else { return }
                selectedProductID = product.wrappedValue.id
                if product.wrappedValue.isSubscription && product.wrappedValue.effectiveSubscriberPricePolicy == .migrate {
                    showingMigrationConfirmation = true
                } else if appStoreDecreaseCount(product.wrappedValue) > 0 {
                    showingAppleDecreaseConfirmation = true
                } else {
                    applySelectedProduct()
                }
            } label: {
                if isApplying {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        if let progress = store.pricingApplyProgressByProductID[product.wrappedValue.id] {
                            Text(progress.total > 1
                                 ? "Applying \(progress.completed) of \(progress.total)…"
                                 : "Applying pricing…")
                        } else {
                            Text("Finishing pricing…")
                        }
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    Label(
                        store.hasAccess(to: .applyRegionalPricing)
                            ? applyButtonTitle(product.wrappedValue)
                            : "\(applyButtonTitle(product.wrappedValue)) · Pro",
                        systemImage: store.hasAccess(to: .applyRegionalPricing)
                            ? "arrow.up.circle.fill"
                            : "lock.fill"
                    )
                    .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(
                isApplying
                    || product.wrappedValue.pricingCalculatedAt == nil
                    || !basePriceDraftMatches(product.wrappedValue)
            )
        }
        .padding(22)
        .background(Theme.sidebar.opacity(0.6))
        .onAppear {
            synchronizeBasePriceDraft(with: product.wrappedValue, force: true)
        }
        .onChange(of: isBasePriceFocused) { _, isFocused in
            if !isFocused, basePriceDraftProductID == product.wrappedValue.id {
                _ = commitBasePriceDraft(to: product)
            }
        }
        .onChange(of: product.wrappedValue.basePrice) { _, newValue in
            if !isBasePriceFocused, basePriceDraftProductID == product.wrappedValue.id {
                basePriceDraft = formattedBasePrice(newValue)
            }
        }
    }

    private func synchronizeBasePriceDraft(with product: StoreProduct, force: Bool = false) {
        guard force || basePriceDraftProductID != product.id || !isBasePriceFocused else { return }
        basePriceDraftProductID = product.id
        basePriceDraft = formattedBasePrice(product.basePrice)
        basePriceValidationMessage = nil
    }

    @discardableResult
    private func commitBasePriceDraft(to product: Binding<StoreProduct>) -> Bool {
        guard basePriceDraftProductID == product.wrappedValue.id,
              let value = storePriceValue(from: basePriceDraft) else {
            basePriceValidationMessage = "Enter a valid price greater than zero."
            return false
        }

        var updatedProduct = product.wrappedValue
        if abs(updatedProduct.basePrice - value) > 0.000_001 {
            updatedProduct.basePrice = value
            updatedProduct.pricingCalculatedAt = nil
            product.wrappedValue = updatedProduct
        }
        basePriceDraft = formattedBasePrice(value)
        basePriceValidationMessage = nil
        return true
    }

    private func formattedBasePrice(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.usesGroupingSeparator = false
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
    }

    private func basePriceDraftMatches(_ product: StoreProduct) -> Bool {
        guard basePriceDraftProductID == product.id,
              let value = storePriceValue(from: basePriceDraft) else { return false }
        return abs(value - product.basePrice) <= 0.000_001
    }

    private func applyButtonTitle(_ product: StoreProduct) -> String {
        let stores = product.platforms.sorted(by: { $0.rawValue < $1.rawValue }).map(\.rawValue)
        return stores.isEmpty ? "No linked store" : "Apply new pricing"
    }

    private func appStoreDecreaseCount(_ product: StoreProduct) -> Int {
        guard product.isSubscription, product.platforms.contains(.appStore) else { return 0 }
        return product.regions.filter {
            $0.enabled && $0.suggestedPrice < $0.currentPrice - 0.000_001
        }.count
    }

    private func subscriberPolicyDetail(_ product: StoreProduct) -> String {
        guard product.effectiveSubscriberPricePolicy == .preserve else {
            return "Existing cohorts are moved to the new prices. Stores may notify customers or require consent for increases."
        }
        if product.platforms.contains(.appStore), product.platforms.contains(.playStore) {
            return "Apple preserves existing prices for increases only; decreases automatically reach existing subscribers. Google Play keeps legacy price cohorts."
        }
        if product.platforms.contains(.appStore) {
            return "Apple preserves existing subscriber prices for increases only. Price decreases automatically apply to existing subscribers."
        }
        return "Google Play keeps legacy subscriber price cohorts while new subscribers receive the new prices."
    }

    private func subscriberPolicyBadge(_ product: StoreProduct) -> String {
        guard product.effectiveSubscriberPricePolicy == .preserve else { return "Subscriber migration selected" }
        return product.platforms.contains(.appStore)
            ? "Increases preserved · decreases pass through"
            : "Existing price cohorts preserved"
    }

    private var appleDecreaseConfirmationMessage: String {
        guard let productID = selectedProductID,
              let product = store.selectedProducts.first(where: { $0.id == productID }) else {
            return "App Store Connect does not allow a higher legacy subscription price to be preserved when the new price is lower."
        }
        let count = appStoreDecreaseCount(product)
        return "\(count) selected market\(count == 1 ? "" : "s") will decrease. Apple requires existing subscriptions in those markets to renew at the lower price; preservation continues to apply to price increases."
    }

    private func applySelectedProduct() {
        guard store.hasAccess(to: .applyRegionalPricing) else {
            proFeature = .applyRegionalPricing
            return
        }
        guard let productID = selectedProductID ?? store.selectedProducts.first?.id else { return }
        isApplying = true
        Task {
            await store.applyPPP(productID: productID)
            isApplying = false
        }
    }
}
