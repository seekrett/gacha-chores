import SwiftUI

struct CollectionView: View {
    @EnvironmentObject var store: GameStore
    @State private var selected: FigureDef?

    private var theme: ShelfTheme { store.state.selectedTheme }
    private var textColor: Color { theme.isDark ? .white : Palette.ink }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    summary
                    ForEach(Catalog.series) { series in
                        seriesShelf(series)
                    }
                }
                .padding()
            }
            .background(
                LinearGradient(colors: theme.colors, startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            )
            .overlay(alignment: .top) {
                if theme == .starry || theme == .neon {
                    StarField().ignoresSafeArea().allowsHitTesting(false)
                }
            }
            .navigationTitle("Collection")
            .toolbarColorScheme(theme.isDark ? .dark : .light, for: .navigationBar)
            .sheet(item: $selected) { FigureDetailView(figure: $0) }
        }
    }

    private var summary: some View {
        let owned = Catalog.figures.filter { store.state.owned[$0.id] != nil }.count
        let shiny = store.state.owned.values.filter(\.shiny).count
        return HStack(spacing: 18) {
            stat("\(owned)/\(Catalog.figures.count)", "Collected")
            stat("\(shiny)", "Shiny")
            stat("\(store.state.claimedSeriesRewards.count)", "Series done")
            stat("\(store.state.glitter)", "Glitter")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 20).fill(.ultraThinMaterial))
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title3.bold().monospacedDigit())
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func seriesShelf(_ series: Series) -> some View {
        let figures = Catalog.figures(in: series.id)
        let owned = store.ownedCount(in: series.id)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: series.symbol)
                    .foregroundStyle(LinearGradient(colors: series.colors, startPoint: .top, endPoint: .bottom))
                Text(series.name).font(.headline)
                Spacer()
                Text("\(owned)/\(figures.count)").font(.subheadline.bold().monospacedDigit())
            }
            .foregroundStyle(textColor)

            if store.canClaimSeries(series.id) {
                Button {
                    Haptics.success()
                    withAnimation { store.claimSeries(series.id) }
                } label: {
                    Label("Series complete! Claim \(series.completionReward) Sparks + 2 tickets", systemImage: "trophy.fill")
                        .font(.subheadline.bold())
                }
                .buttonStyle(BubblyButtonStyle(color: Palette.sparks))
            } else if store.state.claimedSeriesRewards.contains(series.id) {
                Label("Series master", systemImage: "trophy.fill")
                    .font(.caption.bold())
                    .foregroundStyle(Palette.sparks)
            }

            VStack(spacing: 0) {
                ForEach(0..<2, id: \.self) { row in
                    HStack(spacing: 0) {
                        ForEach(figures[(row * 4)..<min(row * 4 + 4, figures.count)]) { fig in
                            cell(fig)
                        }
                    }
                    // shelf plank
                    RoundedRectangle(cornerRadius: 3)
                        .fill(theme.shelf.gradient)
                        .frame(height: 8)
                        .shadow(color: theme == .neon ? theme.shelf : .black.opacity(0.2), radius: theme == .neon ? 6 : 2, y: 2)
                        .padding(.bottom, 14)
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)
            .background(RoundedRectangle(cornerRadius: 20).fill(theme.isDark ? Color.white.opacity(0.06) : Color.white.opacity(0.45)))
        }
    }

    private func cell(_ fig: FigureDef) -> some View {
        let owned = store.state.owned[fig.id]
        return Button {
            selected = fig
        } label: {
            VStack(spacing: 2) {
                FigureView(figure: fig, size: 74, silhouette: owned == nil, shiny: owned?.shiny ?? false)
                    .overlay(alignment: .topTrailing) {
                        if let owned, owned.count > 1 {
                            Text("×\(owned.count)")
                                .font(.caption2.bold())
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(Capsule().fill(Palette.berry))
                                .foregroundStyle(.white)
                        }
                    }
                Text(owned == nil && fig.rarity == .secret ? "???" : fig.name)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(textColor.opacity(owned == nil ? 0.5 : 1))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}

private struct StarField: View {
    private struct Star { let x: CGFloat, y: CGFloat, r: CGFloat, o: Double }
    private static let stars: [Star] = (0..<60).map { i in
        var rng = SeededRNG(seed: UInt64(i + 1))
        return Star(x: CGFloat(Double(rng.next() % 1000) / 1000), y: CGFloat(Double(rng.next() % 1000) / 1000),
                    r: CGFloat(1 + Double(rng.next() % 20) / 10), o: 0.3 + Double(rng.next() % 60) / 100)
    }

    var body: some View {
        Canvas { ctx, size in
            for s in Self.stars {
                ctx.fill(Path(ellipseIn: CGRect(x: s.x * size.width, y: s.y * size.height, width: s.r, height: s.r)),
                         with: .color(.white.opacity(s.o)))
            }
        }
    }
}

struct FigureDetailView: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.dismiss) private var dismiss
    let figure: FigureDef
    @State private var float = false
    @State private var justPolished = false

    private var owned: OwnedFigure? { store.state.owned[figure.id] }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(RadialGradient(colors: [figure.rarity.color.opacity(0.45), .clear], center: .center, startRadius: 10, endRadius: 160))
                            .frame(width: 320, height: 320)
                        FigureView(figure: figure, size: 240, silhouette: owned == nil, shiny: owned?.shiny ?? false)
                            .offset(y: float ? -6 : 6)
                    }
                    .onAppear {
                        withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) { float = true }
                    }

                    RarityBadge(rarity: figure.rarity)
                    Text(owned == nil && figure.rarity == .secret ? "???" : figure.name).font(.largeTitle.bold())
                    Text(figure.series.name).font(.subheadline).foregroundStyle(.secondary)

                    if let owned {
                        Text(figure.flavor)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)

                        HStack(spacing: 18) {
                            VStack {
                                Text("\(owned.count)").font(.title3.bold())
                                Text("Owned").font(.caption).foregroundStyle(.secondary)
                            }
                            VStack {
                                Text(owned.firstObtained, format: .dateTime.month().day().year()).font(.subheadline.bold())
                                Text("First found").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .card()

                        if owned.shiny {
                            Label("Polished to shiny", systemImage: "sparkles")
                                .font(.headline)
                                .foregroundStyle(LinearGradient(colors: Palette.rainbow, startPoint: .leading, endPoint: .trailing))
                        } else {
                            Button {
                                Haptics.success()
                                withAnimation(.spring) { store.polish(figure.id); justPolished = true }
                            } label: {
                                Label("Polish to shiny · \(GameStore.polishCost) Glitter", systemImage: "diamond.fill")
                            }
                            .buttonStyle(BubblyButtonStyle(color: Palette.glitter))
                            .disabled(store.state.glitter < GameStore.polishCost)
                            Text("You have \(store.state.glitter) Glitter. Duplicates give you more.")
                                .font(.caption).foregroundStyle(.secondary)
                        }

                        ShareLink(item: renderedImage, preview: SharePreview(figure.name, image: renderedImage)) {
                            Label("Show it off", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.bordered)
                    } else {
                        Text(figure.rarity == .secret
                             ? "A secret figure. Only the luckiest (and tidiest) will find it."
                             : "Not found yet. Open \(figure.series.name) capsules, or watch for it on the shop's daily shelf.")
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)
                    }
                }
                .padding()
            }
            .overlay { if justPolished { ConfettiView(count: 50) } }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    @MainActor
    private var renderedImage: Image {
        let view = VStack(spacing: 8) {
            FigureView(figure: figure, size: 300, shiny: owned?.shiny ?? false)
            Text(figure.name).font(.system(size: 28, weight: .bold, design: .rounded))
            Text("\(figure.rarity.label) · \(figure.series.name)").font(.system(size: 16, design: .rounded))
        }
        .padding(30)
        .background(LinearGradient(colors: figure.series.colors.map { $0.opacity(0.35) }, startPoint: .top, endPoint: .bottom))
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        if let ui = renderer.uiImage { return Image(uiImage: ui) }
        return Image(systemName: "sparkles")
    }
}
