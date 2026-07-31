import EscaleCore
import SwiftUI

public struct PricingView: View {
    public init() {}

    @EnvironmentObject private var store: WorkspaceStore
    @State private var selectedProductID: UUID?
    @State private var search = ""
    @State private var basePriceDraft = ""
    @State private var basePriceDraftProductID: UUID?
    @State private var basePriceValidationMessage: String?
    @FocusState private var isBasePriceFocused: Bool
    @AppStorage(EscalePreferences.preferredPricingIndexKey)
    private var preferredPricingIndexValue = PricingIndex.worldwidePPP.rawValue

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let productID = activeProductID {
                pricingWorkspace(productID: productID)
            } else {
                EmptyState(
                    icon: "tag.slash",
                    title: emptyProductsTitle,
                    message: emptyProductsMessage
                )
            }
        }
        .background(Theme.canvas)
        .navigationTitle("PPP pricing")
        .onAppear {
            selectFirstAvailableProductIfNeeded()
            applyPreferredPricingIndex(to: activeProductID)
        }
        .onChange(of: store.selectedAppID) { _, _ in selectFirstAvailableProductIfNeeded(force: true) }
        .onChange(of: store.platformFilter) { _, _ in selectFirstAvailableProductIfNeeded() }
        .onChange(of: filteredProductIDs) { _, _ in selectFirstAvailableProductIfNeeded() }
        .onChange(of: activeProductID) { _, productID in
            applyPreferredPricingIndex(to: productID)
        }
        .onChange(of: preferredPricingIndexValue) { _, _ in
            applyPreferredPricingIndex(to: activeProductID)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 18) {
            SectionTitle("Purchasing power pricing", subtitle: "Make your products more affordable without flattening every market.", eyebrow: "Monetization")
            Spacer()
            Picker("Product", selection: Binding(get: { activeProductID }, set: { selectedProductID = $0 })) {
                ForEach(filteredProducts) { product in
                    Label(productPickerTitle(product), systemImage: productPickerIcon(product))
                        .tag(Optional(product.id))
                }
            }
            .frame(width: 320)
            .help("Products from \(selectedStoreName)")
        }
        .padding(24)
    }

    private var filteredProducts: [StoreProduct] {
        store.selectedProducts.filter { product in
            !product.platforms.isDisjoint(with: store.platformFilter.platforms)
        }
    }

    private var filteredProductIDs: [UUID] {
        filteredProducts.map(\.id)
    }

    private var activeProductID: UUID? {
        if let selectedProductID, filteredProductIDs.contains(selectedProductID) {
            return selectedProductID
        }
        return filteredProductIDs.first
    }

    private var selectedStoreName: String {
        switch store.platformFilter {
        case .both: "connected stores"
        case .appStore: "App Store"
        case .playStore: "Google Play"
        }
    }

    private var emptyProductsTitle: String {
        switch store.platformFilter {
        case .both: "No products"
        case .appStore: "No App Store products"
        case .playStore: "No Google Play products"
        }
    }

    private var emptyProductsMessage: String {
        switch store.platformFilter {
        case .both:
            "Sync an in-app purchase or subscription to calculate fair regional prices."
        case .appStore:
            "Sync an App Store in-app purchase or subscription to calculate fair regional prices."
        case .playStore:
            "Sync a Google Play in-app product or subscription to calculate fair regional prices."
        }
    }

    private func selectFirstAvailableProductIfNeeded(force: Bool = false) {
        if force || selectedProductID.map({ !filteredProductIDs.contains($0) }) ?? true {
            selectedProductID = filteredProductIDs.first
        }
    }

    private func applyPreferredPricingIndex(to productID: UUID?) {
        guard let productID else { return }
        let product = store.productBinding(id: productID)
        let preferredIndex = EscalePreferences.preferredPricingIndex(from: preferredPricingIndexValue)
        guard product.wrappedValue.effectivePricingIndex != preferredIndex else { return }

        var updatedProduct = product.wrappedValue
        updatedProduct.pricingIndex = preferredIndex
        updatedProduct.pricingCalculatedAt = nil
        updatedProduct.pricingSourceSummary = nil
        product.wrappedValue = updatedProduct
    }

    private func productPickerTitle(_ product: StoreProduct) -> String {
        let platforms = product.platforms.sorted { $0.rawValue < $1.rawValue }
        let platformLabel = platforms.map(\.shortName).joined(separator: " + ")
        return platformLabel.isEmpty ? product.name : "\(product.name) · \(platformLabel)"
    }

    private func productPickerIcon(_ product: StoreProduct) -> String {
        guard product.platforms.count == 1, let platform = product.platforms.first else {
            return "rectangle.2.swap"
        }
        return platform.icon
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
                    set: {
                        product.wrappedValue.pricingIndex = $0
                        product.wrappedValue.pricingCalculatedAt = nil
                        product.wrappedValue.pricingSourceSummary = nil
                    }
                )) {
                    ForEach(PricingIndex.allCases) { index in Text(index.title).tag(index) }
                }
                .labelsHidden()
                Text(product.wrappedValue.effectivePricingIndex.detail).font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 9) {
                Label("\(product.wrappedValue.regions.count) markets previewed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                Label("\(product.wrappedValue.platforms.count) connected store \(product.wrappedValue.platforms.count == 1 ? "catalog" : "catalogs")", systemImage: "rectangle.2.swap").foregroundStyle(Theme.accent)
            }
            .font(.caption.weight(.medium))
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
            .buttonStyle(.borderedProminent)
            .disabled(store.calculatingProductIDs.contains(product.wrappedValue.id))
            OfficialDistributionCallout(
                title: "Apply approved prices automatically",
                detail: "Preview and review suggestions here, then use the official distribution to write regional prices to App Store Connect and Google Play."
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

}
