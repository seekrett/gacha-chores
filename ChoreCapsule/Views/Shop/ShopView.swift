import SwiftUI

struct ShopView: View {
    @EnvironmentObject var store: GameStore
    @State private var session: PullSession?
    @State private var confirmFigure: FigureDef?
    @State private var confirmTreat: Treat?
    @State private var showTreatEditor = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    BalanceBar()
                    Text("Spend Sparks on a sure thing, or roll the dice in Capsules. Your call.")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    dailyShelf
                    boosters
                    themes
                    treats
                }
                .padding()
            }
            .background(AppBackground())
            .navigationTitle("Shop")
            .fullScreenCover(item: $session) { UnboxingFlowView(session: $0) }
            .sheet(isPresented: $showTreatEditor) { TreatEditorView(addedBy: .me) }
            .confirmationDialog("Buy \(confirmFigure?.name ?? "")?", isPresented: Binding(
                get: { confirmFigure != nil }, set: { if !$0 { confirmFigure = nil } }
            ), titleVisibility: .visible) {
                if let fig = confirmFigure, let price = fig.rarity.shopPrice {
                    Button("Buy for \(price) Sparks") { buy(fig) }
                }
            } message: {
                if let fig = confirmFigure, store.state.owned[fig.id] != nil {
                    Text("You already own this one. A duplicate turns into \(fig.rarity.glitterValue) Glitter.")
                }
            }
            .confirmationDialog("Redeem \(confirmTreat?.title ?? "")?", isPresented: Binding(
                get: { confirmTreat != nil }, set: { if !$0 { confirmTreat = nil } }
            ), titleVisibility: .visible) {
                if let treat = confirmTreat {
                    Button("Spend \(treat.cost) Sparks") {
                        Haptics.success()
                        withAnimation { store.redeem(treat) }
                    }
                }
            } message: {
                Text("Go enjoy it, you earned it 💖")
            }
        }
    }

    // MARK: Sections

    private func sectionHeader(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.title3.bold())
            Text(subtitle).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var dailyShelf: some View {
        VStack(spacing: 10) {
            sectionHeader("Today's shelf", "Pick exactly the figure you want. New lineup every midnight.")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(store.dailyShelf) { fig in
                    let owned = store.state.owned[fig.id]
                    let price = fig.rarity.shopPrice ?? 0
                    VStack(spacing: 6) {
                        FigureView(figure: fig, size: 96, shiny: owned?.shiny ?? false)
                            .background(Circle().fill(fig.rarity.color.opacity(0.18)).frame(width: 110, height: 110))
                        Text(fig.name).font(.subheadline.bold()).lineLimit(1)
                        HStack(spacing: 4) {
                            RarityBadge(rarity: fig.rarity).scaleEffect(0.85)
                        }
                        Text(owned == nil ? "Not owned" : "Owned ×\(owned!.count)")
                            .font(.caption2).foregroundStyle(owned == nil ? Palette.berry : .secondary)
                        Button {
                            confirmFigure = fig
                        } label: {
                            Label("\(price)", systemImage: "sparkle").font(.subheadline.bold())
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Palette.sparks)
                        .disabled(store.state.sparks < price)
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
                }
            }
        }
    }

    private var boosters: some View {
        VStack(spacing: 10) {
            sectionHeader("Boosters", "Power-ups that help you earn more, or pull smarter.")
            VStack(spacing: 0) {
                boosterRow(icon: "bolt.fill", color: Palette.sparks, title: "Spark Boost",
                           detail: "Your next 3 chores pay ×1.5. Buy it, then go get busy.",
                           price: GameStore.boostPrice, currency: .sparks,
                           owned: store.state.doubleSparkCharges > 0 ? "\(store.state.doubleSparkCharges) left" : nil,
                           enabled: store.state.sparks >= GameStore.boostPrice) { store.buyBoost() }
                Divider().padding(.leading, 56)
                boosterRow(icon: "shield.fill", color: Palette.sky, title: "Streak Shield",
                           detail: "Protects your streak if you miss a day. Hold up to \(GameStore.maxShields).",
                           price: GameStore.shieldPrice, currency: .sparks,
                           owned: store.state.streakShields > 0 ? "\(store.state.streakShields)/\(GameStore.maxShields)" : nil,
                           enabled: store.state.sparks >= GameStore.shieldPrice && store.state.streakShields < GameStore.maxShields) { store.buyShield() }
                Divider().padding(.leading, 56)
                boosterRow(icon: "wand.and.stars", color: Palette.glitter, title: "Lucky Charm",
                           detail: "Your next capsule is guaranteed Rare or better.",
                           price: GameStore.charmPrice, currency: .sparks,
                           owned: store.state.luckyCharms > 0 ? "\(store.state.luckyCharms) ready" : nil,
                           enabled: store.state.sparks >= GameStore.charmPrice) { store.buyCharm() }
                Divider().padding(.leading, 56)
                boosterRow(icon: "ticket.fill", color: Palette.ticket, title: "Glitter → Ticket",
                           detail: "Trade duplicate Glitter for a free capsule.",
                           price: GameStore.glitterTicketCost, currency: .glitter, owned: nil,
                           enabled: store.state.glitter >= GameStore.glitterTicketCost) { store.exchangeGlitterForTicket() }
            }
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
        }
    }

    private func boosterRow(icon: String, color: Color, title: String, detail: String, price: Int, currency: Currency,
                            owned: String?, enabled: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(RoundedRectangle(cornerRadius: 10).fill(color.gradient))
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(title).font(.subheadline.bold())
                    if let owned { Tag(text: owned, color: color.adjusted(brightness: -0.2)) }
                }
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                Haptics.impact(.medium)
                withAnimation { action() }
            } label: {
                Label("\(price)", systemImage: currency.icon).font(.caption.bold())
            }
            .buttonStyle(.borderedProminent)
            .tint(currency.color)
            .disabled(!enabled)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var themes: some View {
        VStack(spacing: 10) {
            sectionHeader("Display shelves", "Make your collection look as good as it feels.")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(ShelfTheme.allCases) { theme in
                        let isOwned = store.state.ownedThemes.contains(theme)
                        let isSelected = store.state.selectedTheme == theme
                        VStack(spacing: 8) {
                            ZStack(alignment: .bottom) {
                                LinearGradient(colors: theme.colors, startPoint: .top, endPoint: .bottom)
                                RoundedRectangle(cornerRadius: 2).fill(theme.shelf).frame(height: 6).padding(.horizontal, 8).padding(.bottom, 18)
                                if let sample = Catalog.byID["dust_fluff"] {
                                    FigureView(figure: sample, size: 54).padding(.bottom, 22)
                                }
                            }
                            .frame(width: 120, height: 100)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(isSelected ? Palette.berry : .clear, lineWidth: 3))
                            Text(theme.name).font(.caption.bold())
                            if isOwned {
                                Button(isSelected ? "In use" : "Use") { withAnimation { store.selectTheme(theme) } }
                                    .font(.caption.bold())
                                    .buttonStyle(.bordered)
                                    .disabled(isSelected)
                            } else {
                                Button {
                                    Haptics.success()
                                    withAnimation { store.buyTheme(theme) }
                                } label: {
                                    Label("\(theme.price)", systemImage: "sparkle").font(.caption.bold())
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(Palette.sparks)
                                .disabled(store.state.sparks < theme.price)
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var treats: some View {
        VStack(spacing: 10) {
            HStack(alignment: .top) {
                sectionHeader("Real-life treats", "Rewards you set for yourself. Redeem, then go enjoy it for real.")
                Button { showTreatEditor = true } label: { Image(systemName: "plus.circle.fill").font(.title2) }
            }
            VStack(spacing: 0) {
                if store.state.treats.isEmpty {
                    Text("Add a treat, like a boba run, a movie night, or a new blind box IRL.")
                        .font(.subheadline).foregroundStyle(.secondary).padding()
                }
                ForEach(store.state.treats) { treat in
                    HStack(spacing: 12) {
                        Text(treat.emoji).font(.title)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(treat.title).font(.subheadline.bold())
                            if treat.addedBy == .partner {
                                Text("From \(store.partnerDisplayName)").font(.caption).foregroundStyle(.secondary)
                            } else if store.state.sparks < treat.cost {
                                Text("\(treat.cost - store.state.sparks) more Sparks to go").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button {
                            confirmTreat = treat
                        } label: {
                            Label("\(treat.cost)", systemImage: "sparkle").font(.caption.bold())
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Palette.berry)
                        .disabled(store.state.sparks < treat.cost)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .contextMenu {
                        if treat.addedBy == .me || store.partnerUnlocked {
                            Button(role: .destructive) { store.deleteTreat(treat) } label: { Label("Delete", systemImage: "trash") }
                        }
                    }
                    if treat.id != store.state.treats.last?.id { Divider().padding(.leading, 56) }
                }
            }
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))

            if !store.state.redemptions.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Recently redeemed").font(.caption.bold()).foregroundStyle(.secondary)
                    ForEach(store.state.redemptions.prefix(3)) { r in
                        HStack {
                            Text("\(r.emoji) \(r.title)").font(.caption)
                            Spacer()
                            Text(r.date, format: .dateTime.month().day()).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 4)
            }
        }
    }

    private func buy(_ fig: FigureDef) {
        guard let result = store.buyFigure(fig) else { return }
        Haptics.impact(.medium)
        session = PullSession(series: fig.series, results: [result], pickFromShelf: false)
    }
}

struct TreatEditorView: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.dismiss) private var dismiss
    let addedBy: Assigner
    @State private var title = ""
    @State private var emoji = "🎁"
    @State private var cost = 300

    private static let emojis = ["🎁", "🧋", "🍰", "🎮", "🎬", "🛍️", "💅", "📚", "🍜", "☕️", "🧸", "✈️"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Treat") {
                    TextField("e.g. Boba run", text: $title)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(Self.emojis, id: \.self) { e in
                                Text(e).font(.title2)
                                    .frame(width: 42, height: 42)
                                    .background(Circle().fill(emoji == e ? Palette.pink.opacity(0.35) : Color(.tertiarySystemFill)))
                                    .onTapGesture { emoji = e }
                            }
                        }
                    }
                }
                Section {
                    Stepper(value: $cost, in: 50...10_000, step: 50) {
                        Label("\(cost) Sparks", systemImage: "sparkle")
                    }
                } header: {
                    Text("Price")
                } footer: {
                    Text("Tip: a Standard chore earns about 30 Sparks. Price treats so they take real effort.")
                }
            }
            .navigationTitle("New treat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        store.addTreat(Treat(title: title.trimmingCharacters(in: .whitespaces), emoji: emoji, cost: cost, addedBy: addedBy))
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
