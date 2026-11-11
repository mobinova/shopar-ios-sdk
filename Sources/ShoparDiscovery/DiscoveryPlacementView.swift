import SwiftUI
import GRPC

@MainActor
public struct DiscoveryPlacementView: View {
    private let placementID: String
    private let runtime: DiscoveryRuntime
    private let onProductSelected: (DiscoveryProduct) -> Void
    private let onDealSelected: (String) -> Void
    private var style: DiscoveryStyle { runtime.configuration.style }

    @Environment(\.scenePhase) private var scenePhase
    @State private var page: DiscoveryPage?
    @State private var screenViewID = ShoparAgent.newEventID()
    @State private var pageToken = ""
    @State private var loading = true
    @State private var loadingMore = false
    @State private var errorMessage = ""
    @State private var refreshCounter = 0

    init(
        placementID: String,
        runtime: DiscoveryRuntime,
        onProductSelected: @escaping (DiscoveryProduct) -> Void = { _ in },
        onDealSelected: @escaping (String) -> Void = { _ in }
    ) {
        self.placementID = placementID
        self.runtime = runtime
        self.onProductSelected = onProductSelected
        self.onDealSelected = onDealSelected
    }

    public var body: some View {
        Group {
            if loading && page == nil {
                ProgressView().tint(style.primaryColor.shoparDiscoveryColor).frame(maxWidth: .infinity).padding()
            } else if let page {
                placementContent(page)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text(errorMessage.isEmpty ? "Shopar ürün ve fırsatları yüklenemedi." : errorMessage).font(.footnote)
                    Button("Tekrar dene") { refreshCounter += 1 }
                        .buttonStyle(ShoparDiscoveryPrimaryButtonStyle(style: style))
                }.padding()
            }
        }
        .foregroundStyle(style.textColor.shoparDiscoveryColor)
        .tint(style.primaryColor.shoparDiscoveryColor)
        .environment(\.colorScheme, style.isDark ? .dark : .light)
        .background(style.backgroundColor.shoparDiscoveryColor)
        .task(id: refreshCounter) { await loadFirstPage() }
    }

    @ViewBuilder private func placementContent(_ page: DiscoveryPage) -> some View {
        if page.items.isEmpty {
            if page.format == "full_page_feed" {
                VStack(spacing: 10) {
                    Text("Şu anda gösterilecek ürün veya fırsat yok.").font(.headline)
                    Text("Daha sonra tekrar deneyebilirsin.").font(.footnote).foregroundStyle(style.secondaryTextColor.shoparDiscoveryColor)
                    Button("Yenile") { refreshCounter += 1 }.buttonStyle(ShoparDiscoveryPrimaryButtonStyle(style: style))
                }.frame(maxWidth: .infinity).padding()
            } else {
                Color.clear.frame(height: 0)
            }
        } else {
            GeometryReader { container in
                let viewport = container.frame(in: .global)
                switch page.format {
                case "horizontal_rail":
                    ScrollView(.horizontal) {
                        LazyHStack(spacing: 12) {
                            ForEach(page.items) { item in
                                DiscoveryPlacementCard(
                                    appID: runtime.configuration.appID, placementID: placementID, page: page,
                                    screenViewID: screenViewID, item: item, runtime: runtime, style: style,
                                    viewport: viewport, foreground: scenePhase == .active,
                                    onStale: { errorMessage = $0; refreshCounter += 1 },
                                    onProductSelected: onProductSelected, onDealSelected: onDealSelected
                                ).frame(width: 260)
                            }
                            if page.hasMore { ProgressView().tint(style.primaryColor.shoparDiscoveryColor).onAppear { loadMore() } }
                        }.padding(.horizontal, 12)
                    }
                case "single_card":
                    if let item = page.items.first {
                        DiscoveryPlacementCard(
                            appID: runtime.configuration.appID, placementID: placementID, page: page,
                            screenViewID: screenViewID, item: item, runtime: runtime, style: style,
                            viewport: viewport, foreground: scenePhase == .active,
                            onStale: { errorMessage = $0; refreshCounter += 1 },
                            onProductSelected: onProductSelected, onDealSelected: onDealSelected
                        ).padding(12)
                    }
                default:
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(page.items) { item in
                                DiscoveryPlacementCard(
                                    appID: runtime.configuration.appID, placementID: placementID, page: page,
                                    screenViewID: screenViewID, item: item, runtime: runtime, style: style,
                                    viewport: viewport, foreground: scenePhase == .active,
                                    onStale: { errorMessage = $0; refreshCounter += 1 },
                                    onProductSelected: onProductSelected, onDealSelected: onDealSelected
                                )
                            }
                            if page.hasMore { ProgressView().tint(style.primaryColor.shoparDiscoveryColor).onAppear { loadMore() } }
                        }.padding(12)
                    }
                }
            }
            .frame(minHeight: page.format == "single_card" ? 360 : 0)
            if !errorMessage.isEmpty {
                Text(errorMessage).font(.caption).foregroundStyle(style.secondaryTextColor.shoparDiscoveryColor).padding(.horizontal, 12)
            }
        }
    }

    private func loadFirstPage() async {
        loading = true
        errorMessage = ""
        do {
            let result = try await runtime.placement(placementID)
            if result.outcome == "ok" || result.outcome == "placement_inactive" {
                page = result
                pageToken = result.nextPageToken
                screenViewID = ShoparAgent.newEventID()
                if result.outcome == "placement_inactive" { errorMessage = "Bu ürün alanı şu anda kullanılamıyor." }
            } else {
                page = nil
                errorMessage = "Ürün alanı güncellendi. Yenileyip tekrar dene."
            }
        } catch {
            errorMessage = discoveryErrorMessage(error)
        }
        loading = false
    }

    private func loadMore() {
        guard !loadingMore, page?.hasMore == true, !pageToken.isEmpty else { return }
        loadingMore = true
        Task {
            defer { loadingMore = false }
            guard let current = page else { return }
            do {
                let result = try await runtime.placement(placementID, pageToken: pageToken, revision: current.revision)
                if result.outcome == "placement_refresh_required" { refreshCounter += 1; return }
                page = DiscoveryPage(format: current.format, revision: current.revision, items: current.items + result.items,
                                     nextPageToken: result.nextPageToken, hasMore: result.hasMore, outcome: result.outcome)
                pageToken = result.nextPageToken
            } catch {
                errorMessage = "Daha fazla ürün veya fırsat yüklenemedi."
            }
        }
    }
}

@MainActor
private struct DiscoveryPlacementCard: View {
    let appID: String
    let placementID: String
    let page: DiscoveryPage
    let screenViewID: String
    let item: DiscoveryPlacementItem
    let runtime: DiscoveryRuntime
    let style: DiscoveryStyle
    let viewport: CGRect
    let foreground: Bool
    let onStale: (String) -> Void
    let onProductSelected: (DiscoveryProduct) -> Void
    let onDealSelected: (String) -> Void

    @Environment(\.openURL) private var openURL
    @State private var frame: CGRect = .zero
    @State private var sent = false
    @State private var impressionTask: Task<Void, Never>?
    @State private var impressionTaskID: UUID?
    @State private var busy = false

    private var visible: Bool {
        guard foreground, frame.width > 0, frame.height > 0 else { return false }
        let clipped = frame.intersection(viewport)
        guard !clipped.isNull else { return false }
        return clipped.width * clipped.height / (frame.width * frame.height) >= 0.5
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            if let url = URL(string: item.imageURL), !item.imageURL.isEmpty {
                AsyncImage(url: url) { image in image.resizable().scaledToFill() }
                    placeholder: { style.surfaceSubtleColor.shoparDiscoveryColor }
                    .frame(height: 190).frame(maxWidth: .infinity).clipped()
            }
            Text(item.title).font(.headline).foregroundStyle(style.textColor.shoparDiscoveryColor)
            Text([item.merchantName, item.sellerName].filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.subheadline).foregroundStyle(style.secondaryTextColor.shoparDiscoveryColor)
            if !item.benefitLabel.isEmpty {
                Text(item.benefitLabel).font(.title3.weight(.semibold)).foregroundStyle(style.primaryColor.shoparDiscoveryColor)
            }
            if !item.decisiveCondition.isEmpty {
                Text(item.decisiveCondition).font(.footnote).foregroundStyle(style.secondaryTextColor.shoparDiscoveryColor)
            }
            if !item.couponCode.isEmpty {
                Text("Kupon: \(item.couponCode)").font(.footnote.weight(.medium)).foregroundStyle(style.textColor.shoparDiscoveryColor)
            }
            if let price = item.priceMinorUnits {
                Text(formatPrice(price, item.currency)).font(.title3.weight(.semibold)).foregroundStyle(style.primaryColor.shoparDiscoveryColor)
            }
            Text(item.disclosureText).font(.caption).foregroundStyle(style.secondaryTextColor.shoparDiscoveryColor)
            Button { openItem() } label: {
                if busy { ProgressView().tint(style.onAccentColor.shoparDiscoveryColor) }
                else { Text(item.ctaText.isEmpty ? "Mağazaya git" : item.ctaText) }
            }.buttonStyle(ShoparDiscoveryPrimaryButtonStyle(style: style))
        }
        .padding(14)
        .background(style.surfaceColor.shoparDiscoveryColor, in: RoundedRectangle(cornerRadius: style.cardCornerRadius))
        .overlay(RoundedRectangle(cornerRadius: style.cardCornerRadius).stroke(style.borderColor.shoparDiscoveryColor))
        .background(GeometryReader { proxy in Color.clear.preference(key: DiscoveryFramePreference.self, value: proxy.frame(in: .global)) })
        .onPreferenceChange(DiscoveryFramePreference.self) { frame = $0 }
        .onAppear { updateImpressionTask() }
        .onChange(of: visible) { _ in updateImpressionTask() }
        .onDisappear { impressionTask?.cancel(); impressionTask = nil; impressionTaskID = nil }
    }

    private func updateImpressionTask() {
        guard visible, !sent, impressionTask == nil else {
            if !visible { impressionTask?.cancel(); impressionTask = nil; impressionTaskID = nil }
            return
        }
        let eventID = ShoparAgent.newEventID()
        let taskID = UUID(); impressionTaskID = taskID
        impressionTask = Task {
            do {
                try await Task.sleep(for: .seconds(1))
                while !Task.isCancelled && visible && !sent {
                    do {
                        try await runtime.recordImpression(placementID: placementID, revision: page.revision, screenViewID: screenViewID, item: item, eventID: eventID)
                        sent = true
                        break
                    } catch { if Task.isCancelled { break }; try await Task.sleep(for: .seconds(5)) }
                }
            } catch { }
            if impressionTaskID == taskID { impressionTask = nil; impressionTaskID = nil }
        }
    }

    private func openItem() {
        guard !busy else { return }
        busy = true
        Task {
            defer { busy = false }
            do {
                let result = try await runtime.openItem(placementID: placementID, revision: page.revision, screenViewID: screenViewID, item: item)
                switch result.outcome {
                case "opened":
                    guard let url = URL(string: result.redirectURL) else { onStale("Mağaza bağlantısı kullanılamıyor."); return }
                    if item.kind == "deal" { onDealSelected(item.dealID) }
                    else if let product = item.productProjection { onProductSelected(product) }
                    openURL(url)
                case "offer_changed": onStale("Fiyat veya teklif güncellendi. Ürünler yenileniyor.")
                case "offer_unavailable": onStale("Bu teklif artık kullanılamıyor. Ürünler yenileniyor.")
                default: onStale("Ürün alanı güncellendi. Yenileyip tekrar dene.")
                }
            } catch { onStale(discoveryErrorMessage(error)) }
        }
    }

    private func formatPrice(_ minor: Int64, _ currency: String) -> String {
        let value = Decimal(minor) / 100
        return "\(value.formatted(.number.precision(.fractionLength(0...2)))) \(currency)"
    }
}

private struct DiscoveryFramePreference: PreferenceKey {
    static let defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}

private func discoveryErrorMessage(_ error: Error) -> String {
    if let status = error as? GRPCStatus, status.code == .resourceExhausted {
        return "Shopar'a kısa sürede çok fazla istek gönderildi. Biraz bekleyip tekrar dene."
    }
    return "Shopar ürün ve fırsatları şu anda yüklenemiyor. Bağlantını kontrol edip tekrar dene."
}
