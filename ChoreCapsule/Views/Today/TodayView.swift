import SwiftUI

struct TodayView: View {
    @EnvironmentObject var store: GameStore
    @EnvironmentObject var sync: PartnerSync
    @State private var completing: Chore?
    @State private var showSettings = false
    @State private var showPartner = false
    @State private var showHow = false

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
        let part = hour < 12 ? "Good morning" : hour < 18 ? "Good afternoon" : "Good evening"
        return store.state.userName.isEmpty ? part : "\(part), \(store.state.userName)"
    }

    private var upNext: [Chore] {
        store.state.chores
            .filter { !$0.isArchived && !$0.isDone() }
            .sorted { a, b in
                let da = a.effectiveDeadline() ?? .distantFuture
                let db = b.effectiveDeadline() ?? .distantFuture
                if da != db { return da < db }
                return a.difficulty.basePoints > b.difficulty.basePoints
            }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    HeaderCard()
                    if store.isStreakAtRisk { streakRiskCard }
                    if store.state.doubleSparkCharges > 0 { boostBanner }
                    if !store.canEarnSparks { verifyFirstCard }
                    if !store.pendingSubmissions.isEmpty { pendingCard }
                    QuestsCard()
                    upNextCard
                    if store.affordablePulls > 0 { capsuleCTA }
                    recentCard
                }
                .padding()
            }
            .background(AppBackground())
            .navigationTitle(greeting)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { showHow = true } label: { Image(systemName: "questionmark.circle") }
                    Button { store.selectedTab = .partner } label: {
                        Image(systemName: "person.2.fill")
                            .overlay(alignment: .topTrailing) {
                                if !sync.reviewsToDo.isEmpty {
                                    Text("\(sync.reviewsToDo.count)")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 4).padding(.vertical, 1)
                                        .background(Capsule().fill(.red))
                                        .offset(x: 8, y: -6)
                                }
                            }
                    }
                    Button { showSettings = true } label: { Image(systemName: "gearshape.fill") }
                }
            }
            .sheet(item: $completing) { CompleteChoreView(chore: $0) }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .sheet(isPresented: $showPartner) { PartnerView() }
            .sheet(isPresented: $showHow) { HowItWorksView() }
        }
    }

    private var streakRiskCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "flame.fill").font(.title).foregroundStyle(.orange.gradient)
                .symbolEffect(.bounce, options: .repeating.speed(0.4))
            VStack(alignment: .leading, spacing: 2) {
                Text("Keep your \(store.state.streak)-day streak alive").font(.headline)
                Text("Finish any chore today. Tomorrow's bonus grows to +\(min(store.state.streak, 10) * 5)%.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .card()
    }

    private var boostBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "bolt.fill").font(.title2).foregroundStyle(Palette.sparks.gradient)
            VStack(alignment: .leading) {
                Text("Spark Boost active").font(.headline)
                Text("Your next \(store.state.doubleSparkCharges) chore\(store.state.doubleSparkCharges == 1 ? "" : "s") pay ×1.5")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .card()
    }

    private var verifyFirstCard: some View {
        Button { store.selectedTab = .partner } label: {
            HStack(spacing: 12) {
                Image(systemName: "lock.shield.fill").font(.title).foregroundStyle(.orange.gradient)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Add a partner to start earning").font(.headline)
                    Text("Chores only pay once they're verified, and this iPhone can't check photos with AI. Tap to invite an accountability partner.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
        .card()
    }

    private var pendingCard: some View {
        Button { store.selectedTab = .partner } label: {
            HStack(spacing: 12) {
                Image(systemName: "hourglass").font(.title2).foregroundStyle(Palette.lavender)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(store.pendingSubmissions.count) waiting for \(store.partnerDisplayName)").font(.headline)
                    let held = store.pendingSubmissions.reduce(0) { $0 + $1.breakdown.total }
                    Text(store.hasOnlinePartner
                         ? "\(held) Sparks unlock when they approve on their phone."
                         : store.hasPartner
                            ? "\(held) Sparks unlock when they approve. Tap to hand over the phone."
                            : "\(held) Sparks are held until you add a partner.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
        .card()
    }

    private var upNextCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Up next").font(.headline)
                Spacer()
                Button("All chores") { store.selectedTab = .chores }.font(.subheadline)
            }
            if upNext.isEmpty {
                HStack {
                    Text("🎉").font(.largeTitle)
                    VStack(alignment: .leading) {
                        Text("All caught up!").font(.headline)
                        Text("Add a new chore or go admire your collection.").font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            } else {
                ForEach(upNext.prefix(4)) { chore in
                    Button { completing = chore } label: { ChoreRow(chore: chore) }
                        .buttonStyle(.plain)
                    if chore.id != upNext.prefix(4).last?.id { Divider() }
                }
            }
        }
        .card()
    }

    private var capsuleCTA: some View {
        Button { store.selectedTab = .capsules } label: {
            HStack(spacing: 14) {
                BlindBoxView(series: Catalog.series[Self.ctaSeriesIndex], size: 64)
                VStack(alignment: .leading, spacing: 2) {
                    Text("You can open \(store.affordablePulls) capsule\(store.affordablePulls == 1 ? "" : "s")!")
                        .font(.headline)
                    Text("Who's hiding inside? 👀").font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
        .card()
    }

    private static var ctaSeriesIndex: Int { GameStore.dayNumber % Catalog.series.count }

    private var recentCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recent activity").font(.headline)
            if store.state.ledger.isEmpty {
                Text("Nothing yet. Finish a chore to get started!").foregroundStyle(.secondary)
            }
            ForEach(store.state.ledger.prefix(6)) { entry in
                HStack {
                    Text(entry.text).font(.subheadline).lineLimit(1)
                    Spacer()
                    if entry.amount != 0 {
                        HStack(spacing: 2) {
                            Text(entry.amount > 0 ? "+\(entry.amount)" : "\(entry.amount)")
                            Image(systemName: entry.currency.icon)
                        }
                        .font(.subheadline.bold())
                        .foregroundStyle(entry.amount > 0 ? entry.currency.color : .secondary)
                    }
                }
            }
        }
        .card()
    }
}

struct HeaderCard: View {
    @EnvironmentObject var store: GameStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sparks").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        Image(systemName: "sparkle")
                        Text(store.state.sparks, format: .number)
                            .contentTransition(.numericText(value: Double(store.state.sparks)))
                    }
                    .font(.system(size: 40, weight: .heavy, design: .rounded))
                    .foregroundStyle(LinearGradient(colors: [Palette.sparks, Palette.berry], startPoint: .leading, endPoint: .trailing))
                }
                Spacer()
                VStack(spacing: 2) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(store.state.streak > 0 ? AnyShapeStyle(LinearGradient(colors: [.yellow, .orange, .red], startPoint: .top, endPoint: .bottom)) : AnyShapeStyle(Color.gray.opacity(0.4)))
                    Text("\(store.state.streak) day\(store.state.streak == 1 ? "" : "s")").font(.caption.bold())
                    if store.state.streakShields > 0 {
                        HStack(spacing: 1) {
                            ForEach(0..<store.state.streakShields, id: \.self) { _ in
                                Image(systemName: "shield.fill").font(.system(size: 9))
                            }
                        }
                        .foregroundStyle(Palette.sky)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                let p = store.levelProgress
                HStack {
                    Text("Level \(store.state.level)").font(.subheadline.bold())
                    Spacer()
                    Text("\(p.needed - p.current) to level \(store.state.level + 1) 🎟️")
                        .font(.caption).foregroundStyle(.secondary)
                }
                ProgressView(value: Double(p.current), total: Double(max(p.needed, 1)))
                    .tint(Palette.berry)
            }

            HStack(spacing: 8) {
                CurrencyPill(currency: .tickets, amount: store.state.tickets)
                CurrencyPill(currency: .glitter, amount: store.state.glitter)
                if store.state.luckyCharms > 0 {
                    Tag(text: "\(store.state.luckyCharms) charm", icon: "wand.and.stars", color: Palette.glitter)
                }
                Spacer()
            }
        }
        .card()
    }
}

struct QuestsCard: View {
    @EnvironmentObject var store: GameStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Daily quests").font(.headline)
                Spacer()
                Text("Resets at midnight").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(store.todaysQuests) { quest in
                let progress = min(store.progress(quest), quest.target)
                HStack(spacing: 12) {
                    Image(systemName: quest.icon)
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(Palette.lavender.gradient))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(quest.title).font(.subheadline.weight(.semibold))
                        ProgressView(value: Double(progress), total: Double(quest.target))
                            .tint(Palette.mint)
                    }
                    Group {
                        if store.isClaimed(quest) {
                            Image(systemName: "checkmark.circle.fill").font(.title2).foregroundStyle(Palette.mint)
                        } else if progress >= quest.target {
                            Button {
                                Haptics.success()
                                withAnimation { store.claim(quest) }
                            } label: {
                                Text("+\(quest.reward)").font(.subheadline.bold())
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(Palette.sparks)
                        } else {
                            Text("+\(quest.reward)").font(.subheadline.bold()).foregroundStyle(.secondary)
                        }
                    }
                    .frame(minWidth: 56)
                }
            }
            Divider()
            HStack {
                Image(systemName: "ticket.fill").foregroundStyle(Palette.ticket)
                Text("Finish all 3 for a free capsule ticket").font(.subheadline)
                Spacer()
                if store.todayLog.bonusClaimed {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.mint)
                } else if store.canClaimDailyBonus {
                    Button("Claim") {
                        Haptics.success()
                        withAnimation { store.claimDailyBonus() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Palette.ticket)
                }
            }
        }
        .card()
    }
}
