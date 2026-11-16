import SwiftUI

struct PullSession: Identifiable {
    let id = UUID()
    let series: Series
    let results: [PullResult]
    var pickFromShelf: Bool
}

struct CapsuleView: View {
    @EnvironmentObject var store: GameStore
    @State private var seriesID = Catalog.series[0].id
    @State private var session: PullSession?
    @State private var bob = false

    private var series: Series { Catalog.series(seriesID) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    BalanceBar()
                    seriesPicker
                    hero
                    pullButtons
                    pityCard
                    lineup
                }
                .padding()
            }
            .background(AppBackground())
            .navigationTitle("Capsules")
            .fullScreenCover(item: $session) { UnboxingFlowView(session: $0) }
        }
    }

    private var seriesPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Catalog.series) { s in
                    Button {
                        withAnimation(.snappy) { seriesID = s.id }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: s.symbol)
                            Text(s.name)
                        }
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(s.id == seriesID ? AnyShapeStyle(LinearGradient(colors: s.colors, startPoint: .leading, endPoint: .trailing)) : AnyShapeStyle(Color(.secondarySystemGroupedBackground))))
                        .foregroundStyle(s.id == seriesID ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var hero: some View {
        let owned = store.ownedCount(in: series.id)
        let total = Catalog.figures(in: series.id).count
        return VStack(spacing: 10) {
            BlindBoxView(series: series, size: 170)
                .offset(y: bob ? -6 : 6)
                .onAppear {
                    withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { bob = true }
                }
            Text(series.name).font(.title2.bold()).foregroundStyle(.white)
            Text(series.tagline).font(.subheadline).foregroundStyle(.white.opacity(0.9)).multilineTextAlignment(.center)
            HStack {
                ProgressView(value: Double(owned), total: Double(total)).tint(.white)
                Text("\(owned)/\(total)").font(.caption.bold()).foregroundStyle(.white)
            }
            .padding(.horizontal, 30)
        }
        .padding(.vertical, 20)
        .padding(.horizontal)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(LinearGradient(colors: series.colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(
                    RaysShape(count: 18).fill(.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                )
        )
        .shadow(color: (series.colors.last ?? .black).opacity(0.3), radius: 14, y: 6)
    }

    private var pullButtons: some View {
        VStack(spacing: 10) {
            if store.state.luckyCharms > 0 {
                Label("Lucky Charm ready: your next capsule is Rare or better", systemImage: "wand.and.stars")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.glitter)
            }
            HStack(spacing: 10) {
                Button {
                    start(count: 1, payment: .sparks)
                } label: {
                    VStack(spacing: 2) {
                        Text("Pick a box")
                        Label("\(GameStore.singleCost)", systemImage: "sparkle").font(.caption.bold())
                    }
                    .frame(maxHeight: .infinity)
                }
                .buttonStyle(BubblyButtonStyle())
                .disabled(!store.canPull(count: 1, payment: .sparks))

                Button {
                    start(count: 10, payment: .sparks)
                } label: {
                    VStack(spacing: 2) {
                        Text("Open a case ×10")
                        Label("\(GameStore.tenCost) · Rare+ guaranteed", systemImage: "sparkle").font(.caption.bold())
                    }
                    .frame(maxHeight: .infinity)
                }
                .buttonStyle(BubblyButtonStyle(color: Palette.glitter))
                .disabled(!store.canPull(count: 10, payment: .sparks))
            }
            .fixedSize(horizontal: false, vertical: true)
            if store.state.tickets > 0 {
                Button {
                    start(count: 1, payment: .ticket)
                } label: {
                    Label("Use a ticket (\(store.state.tickets) left)", systemImage: "ticket.fill")
                }
                .buttonStyle(BubblyButtonStyle(color: Palette.ticket))
            }
            if store.state.sparks < GameStore.singleCost && store.state.tickets == 0 {
                Button {
                    store.selectedTab = .chores
                } label: {
                    Text("You need \(GameStore.singleCost - store.state.sparks) more Sparks. Go finish a chore! 💪")
                        .font(.subheadline.weight(.semibold))
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 4)
            }
        }
    }

    private var pityCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Odds & guarantees").font(.headline)
            HStack(spacing: 6) {
                ForEach(Rarity.allCases, id: \.self) { r in
                    VStack(spacing: 2) {
                        Text(r.label).font(.caption2.bold())
                        Text("\(Int(r.rate * 100))%").font(.caption.bold().monospacedDigit())
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 10).fill(r.color.opacity(0.18)))
                    .foregroundStyle(r.color.adjusted(brightness: -0.25))
                }
            }
            Label("Epic or better guaranteed within \(GameStore.epicPity - store.state.pullsSinceEpic) capsules", systemImage: "shield.lefthalf.filled")
                .font(.caption)
            Label("Secret guaranteed within \(GameStore.secretPity - store.state.pullsSinceSecret) capsules", systemImage: "star.circle")
                .font(.caption)
            Label("Duplicates turn into Glitter, which polishes figures to shiny", systemImage: "diamond.fill")
                .font(.caption)
        }
        .foregroundStyle(.secondary)
        .card()
    }

    private var lineup: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("In this series").font(.headline)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 12) {
                ForEach(Catalog.figures(in: series.id)) { fig in
                    let owned = store.state.owned[fig.id]
                    let hidden = owned == nil && fig.rarity == .secret
                    VStack(spacing: 4) {
                        FigureView(figure: fig, size: 64, silhouette: owned == nil, shiny: owned?.shiny ?? false)
                        Text(hidden ? "???" : fig.name).font(.caption2.weight(.semibold)).lineLimit(1)
                        Circle().fill(fig.rarity.color).frame(width: 6, height: 6)
                    }
                }
            }
        }
        .card()
    }

    private func start(count: Int, payment: PullPayment) {
        let results = store.pull(seriesID: series.id, count: count, payment: payment)
        guard !results.isEmpty else { return }
        Haptics.impact(.medium)
        session = PullSession(series: series, results: results, pickFromShelf: count == 1)
    }
}
