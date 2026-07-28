import EscaleCore
import SwiftUI

public struct ReviewsView: View {
    public init() {}

    @EnvironmentObject private var store: WorkspaceStore
    @State private var selectedReviewID: UUID?
    @State private var ratingFilter = 0
    @State private var responseFilter = "All"
    @State private var search = ""

    private var visibleReviews: [CustomerReview] {
        store.selectedReviews.filter { review in
            store.platformFilter.platforms.contains(review.platform)
                && (ratingFilter == 0 || review.rating == ratingFilter)
                && (responseFilter == "All" || (responseFilter == "Unanswered" && review.response == nil) || (responseFilter == "Answered" && review.response != nil))
                && (search.isEmpty || review.title.localizedCaseInsensitiveContains(search) || review.body.localizedCaseInsensitiveContains(search))
        }
    }

    private var loadedAverageRating: String {
        let reviews = store.selectedReviews.filter { store.platformFilter.platforms.contains($0.platform) }
        guard !reviews.isEmpty else { return "—" }
        let average = Double(reviews.map(\.rating).reduce(0, +)) / Double(reviews.count)
        return average.formatted(.number.precision(.fractionLength(1)))
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HSplitView {
                reviewList.frame(minWidth: 395, idealWidth: 450, maxWidth: 520)
                if let review = visibleReviews.first(where: { $0.id == selectedReviewID }) ?? visibleReviews.first {
                    ReviewDetail(review: review)
                        .id(review.id)
                } else {
                    EmptyState(icon: "text.bubble", title: "No matching reviews", message: "Adjust your filters to see more customer feedback.")
                }
            }
        }
        .background(Theme.canvas)
        .navigationTitle("Customer reviews")
        .onAppear { if selectedReviewID == nil { selectedReviewID = visibleReviews.first?.id } }
    }

    private var header: some View {
        HStack(alignment: .bottom, spacing: 18) {
            SectionTitle("Customer reviews", subtitle: "Listen and respond across both stores.", eyebrow: "Reputation")
            Spacer()
            HStack(spacing: 5) {
                Text(loadedAverageRating).font(.title2.weight(.bold).monospacedDigit())
                Image(systemName: "star.fill").foregroundStyle(.orange)
                Text("· \(store.selectedReviews.filter { store.platformFilter.platforms.contains($0.platform) }.count) loaded reviews")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(24)
    }

    private var reviewList: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                TextField("Search reviews", text: $search)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Picker("Rating", selection: $ratingFilter) {
                        Text("All ratings").tag(0)
                        ForEach((1...5).reversed(), id: \.self) { Text("\($0) stars").tag($0) }
                    }
                    Picker("Response", selection: $responseFilter) {
                        Text("All").tag("All")
                        Text("Unanswered").tag("Unanswered")
                        Text("Answered").tag("Answered")
                    }
                }
            }
            .padding(14)
            Divider()
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(visibleReviews) { review in
                        ReviewRow(review: review, selected: selectedReviewID == review.id)
                            .contentShape(Rectangle())
                            .onTapGesture { selectedReviewID = review.id }
                        Divider().padding(.leading, 62)
                    }
                }
            }
        }
        .background(Theme.sidebar.opacity(0.42))
    }
}

private struct ReviewRow: View {
    let review: CustomerReview
    let selected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            ZStack {
                Circle().fill(review.platform.tint.opacity(0.12))
                Text(review.author.prefix(1)).font(.subheadline.weight(.bold)).foregroundStyle(review.platform.tint)
            }
            .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    HStack(spacing: 2) {
                        ForEach(1...5, id: \.self) { star in
                            Image(systemName: star <= review.rating ? "star.fill" : "star").foregroundStyle(star <= review.rating ? .orange : .secondary.opacity(0.35))
                        }
                    }
                    .font(.system(size: 9))
                    Spacer()
                    Text(review.date, style: .relative).font(.caption2).foregroundStyle(.secondary)
                }
                Text(review.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(review.body).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                HStack(spacing: 6) {
                    PlatformBadge(platform: review.platform, showsName: false)
                    Text("\(review.countryCode) · v\(review.version)").font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                    if review.response == nil { Text("Reply").font(.caption2.weight(.semibold)).foregroundStyle(Theme.accent) }
                }
            }
        }
        .padding(13)
        .background(selected ? Theme.accent.opacity(0.09) : .clear)
    }
}

private struct ReviewDetail: View {
    @EnvironmentObject private var store: WorkspaceStore
    let review: CustomerReview
    @State private var response = ""
    @State private var isSending = false
    @State private var isDrafting = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 3) {
                            ForEach(1...5, id: \.self) { star in
                                Image(systemName: star <= review.rating ? "star.fill" : "star").foregroundStyle(star <= review.rating ? .orange : .secondary.opacity(0.3))
                            }
                        }
                        Text(review.title).font(.title2.weight(.bold))
                        Text("By \(review.author) · \(review.countryCode) · Version \(review.version)").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    PlatformBadge(platform: review.platform)
                }
                Text(review.body)
                    .font(.body).lineSpacing(5)
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                if let existing = review.response {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack { Label("Your response", systemImage: "checkmark.circle.fill").font(.subheadline.weight(.semibold)).foregroundStyle(.green); Spacer(); Text("Published").font(.caption).foregroundStyle(.secondary) }
                        Text(existing).font(.subheadline).lineSpacing(3)
                    }
                    .padding(18)
                    .background(.green.opacity(0.055), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(.green.opacity(0.14)))
                } else {
                    replyComposer
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("CUSTOMER CONTEXT").font(.caption2.weight(.bold)).tracking(0.7).foregroundStyle(.secondary)
                    HStack(spacing: 13) {
                        contextItem(icon: "shippingbox", title: review.platform.rawValue, detail: "Public review")
                        contextItem(icon: "clock", title: review.date.formatted(date: .abbreviated, time: .shortened), detail: "Submitted")
                        contextItem(icon: "person.crop.circle", title: review.author, detail: "Customer")
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 820, alignment: .leading)
        }
    }

    private var replyComposer: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Write a response").font(.headline)
                Spacer()
                Button {
                    isDrafting = true
                    Task {
                        if let draft = await store.draftReviewReply(to: review.id) {
                            response = draft
                        }
                        isDrafting = false
                    }
                } label: {
                    if isDrafting { ProgressView().controlSize(.small) } else { Label("Draft with AI", systemImage: "sparkles") }
                }
                .buttonStyle(.bordered).disabled(isDrafting || isSending)
            }
            TextField("Thank the customer or offer help…", text: $response, axis: .vertical)
                .textFieldStyle(.plain).lineLimit(5...10)
                .padding(13).frame(minHeight: 115, alignment: .topLeading)
                .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(Theme.border))
            HStack {
                Text("Responses are public and processed by the store.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("\(response.count) / 350").font(.caption.monospacedDigit()).foregroundStyle(response.count > 350 ? .red : .secondary)
                Button {
                    isSending = true
                    Task {
                        await store.reply(to: review.id, text: response)
                        isSending = false
                    }
                } label: {
                    if isSending { ProgressView().controlSize(.small) } else { Label("Send reply", systemImage: "paperplane.fill") }
                }
                .buttonStyle(.borderedProminent).disabled(response.isEmpty || response.count > 350 || isSending || isDrafting)
            }
        }
        .padding(18)
        .cardStyle()
    }

    private func contextItem(icon: String, title: String, detail: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon).foregroundStyle(Theme.accent).frame(width: 28, height: 28).background(Theme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 1) { Text(title).font(.caption.weight(.semibold)); Text(detail).font(.caption2).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
