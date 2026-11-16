import SwiftUI
import Combine

enum AppTab: Hashable {
    case today, chores, capsules, collection, shop
}

struct QuestDef: Identifiable {
    let id: String
    let title: String
    let icon: String
    let target: Int
    let reward: Int
    let metric: KeyPath<DailyLog, Int>
}

struct PullResult: Identifiable, Hashable {
    let id = UUID()
    let figure: FigureDef
    let isNew: Bool
    let glitter: Int
    let wasPity: Bool
}

enum PullPayment {
    case sparks, ticket
}

/// How a photo proof was checked before submitting.
enum PhotoCheck {
    /// No photo check ran (non-photo proof, or checks turned off).
    case none
    /// The AI agreed the photo matches the chore.
    case verified(String)
    /// The AI couldn't run on this device.
    case unverified(String)
    /// The AI rejected the photo and the user asked their partner to decide.
    case partnerAppeal(String)
}

/// Deterministic RNG so the daily shop and quests stay the same all day.
struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

@MainActor
final class GameStore: ObservableObject {
    @Published var state: AppState
    @Published var selectedTab: AppTab = .today
    @Published var partnerUnlocked = false
    @Published var pendingLevelUp: Int? = nil
    @Published var notice: String? = nil

    static let singleCost = 100
    static let tenCost = 900
    static let epicPity = 40
    static let secretPity = 120
    static let polishCost = 30
    static let glitterTicketCost = 60
    static let critChance = 0.12

    private var saveCancellable: AnyCancellable?
    private let fileURL: URL

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = docs.appendingPathComponent("chore-capsule.json")
        if let data = try? Data(contentsOf: fileURL) {
            if let decoded = try? JSONDecoder().decode(AppState.self, from: data) {
                state = decoded
            } else {
                // Keep a backup rather than silently losing progress.
                try? data.write(to: docs.appendingPathComponent("chore-capsule-backup-\(Int(Date().timeIntervalSince1970)).json"))
                state = AppState()
                seed()
            }
        } else {
            state = AppState()
            seed()
        }
        saveCancellable = $state
            .dropFirst()
            .debounce(for: .milliseconds(400), scheduler: RunLoop.main)
            .sink { [weak self] s in self?.write(s) }
        refreshStreak()
    }

    // MARK: Persistence

    func saveNow() { write(state) }

    private func write(_ s: AppState) {
        do {
            let data = try JSONEncoder().encode(s)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("Save failed: \(error)")
        }
    }

    private func seed() {
        let cal = Calendar.current
        let ninePM = cal.date(bySettingHour: 21, minute: 0, second: 0, of: .now)
        state.chores = [
            Chore(title: "Make the bed", emoji: "🛏️", difficulty: .quick, proof: .photo, recurrence: .daily),
            Chore(title: "Wash the dishes", emoji: "🍽️", difficulty: .standard, proof: .beforeAfter, recurrence: .daily, deadline: ninePM),
            Chore(title: "Drink water & clear the desk", emoji: "💧", difficulty: .quick, proof: .honor, recurrence: .daily),
            Chore(title: "Do a load of laundry", emoji: "🧺", difficulty: .big, proof: .photo, recurrence: .weekly),
            Chore(title: "Deep-clean the bathroom", emoji: "🛁", difficulty: .epic, proof: .beforeAfter, recurrence: .weekly),
        ]
        state.treats = [
            Treat(title: "Boba run", emoji: "🧋", cost: 400),
            Treat(title: "1 hour of guilt-free gaming", emoji: "🎮", cost: 250),
            Treat(title: "Buy a real blind box", emoji: "🎁", cost: 2500),
        ]
        log("Welcome gift", 300, .sparks)
        log("Welcome gift", 1, .tickets)
    }

    func resetEverything() {
        PhotoStore.deleteAll()
        state = AppState()
        seed()
        partnerUnlocked = false
        saveNow()
    }

    // MARK: Helpers

    var partnerDisplayName: String {
        state.partnerName.isEmpty ? "your partner" : state.partnerName
    }

    var hasPartner: Bool { state.partnerPIN != nil }

    static func dayKey(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static var dayNumber: Int {
        let start = Calendar.current.startOfDay(for: .now)
        return Int(start.timeIntervalSince1970 / 86_400)
    }

    var todayLog: DailyLog { state.dailyLogs[Self.dayKey(.now)] ?? DailyLog() }

    private func updateTodayLog(_ change: (inout DailyLog) -> Void) {
        let key = Self.dayKey(.now)
        var log = state.dailyLogs[key] ?? DailyLog()
        change(&log)
        state.dailyLogs[key] = log
    }

    private func log(_ text: String, _ amount: Int, _ currency: Currency) {
        state.ledger.insert(LedgerEntry(text: text, amount: amount, currency: currency), at: 0)
        if state.ledger.count > 150 { state.ledger.removeLast(state.ledger.count - 150) }
    }

    // MARK: Streaks

    func refreshStreak() {
        guard let last = state.lastActiveDay else { return }
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: last), to: cal.startOfDay(for: .now)).day ?? 0
        guard days > 1 else { return }
        let missed = days - 1
        if state.streak > 0 && state.streakShields >= missed {
            state.streakShields -= missed
            state.lastActiveDay = cal.date(byAdding: .day, value: -1, to: cal.startOfDay(for: .now))
            notice = "🛡️ A Streak Shield saved your \(state.streak)-day streak!"
        } else if state.streak > 0 {
            notice = "Your \(state.streak)-day streak ended. Finish a chore today to start a new one 🔥"
            state.streak = 0
        }
    }

    /// What the streak will be once you complete something today.
    var projectedStreak: Int {
        if let last = state.lastActiveDay, Calendar.current.isDateInToday(last) { return state.streak }
        if let last = state.lastActiveDay, Calendar.current.isDateInYesterday(last) { return state.streak + 1 }
        return 1
    }

    var isStreakAtRisk: Bool {
        guard state.streak > 0, let last = state.lastActiveDay else { return false }
        return !Calendar.current.isDateInToday(last)
    }

    private func registerActivity() {
        refreshStreak()
        if let last = state.lastActiveDay, Calendar.current.isDateInToday(last) { return }
        state.streak = projectedStreak
        state.bestStreak = max(state.bestStreak, state.streak)
        state.lastActiveDay = .now
    }

    // MARK: Levels

    /// Total lifetime Sparks needed to reach a level.
    static func xpThreshold(level: Int) -> Int {
        guard level > 1 else { return 0 }
        let n = level - 1
        return 150 * n + 75 * n * (n - 1) / 2
    }

    var levelProgress: (current: Int, needed: Int) {
        let base = Self.xpThreshold(level: state.level)
        let next = Self.xpThreshold(level: state.level + 1)
        return (state.lifetimeSparks - base, next - base)
    }

    private func checkLevelUp() {
        while state.lifetimeSparks >= Self.xpThreshold(level: state.level + 1) {
            state.level += 1
            state.tickets += 1
            pendingLevelUp = state.level
            log("Reached level \(state.level)", 1, .tickets)
        }
    }

    // MARK: Earning

    func award(_ amount: Int, reason: String) {
        guard amount > 0 else { return }
        state.sparks += amount
        state.lifetimeSparks += amount
        updateTodayLog { $0.pointsEarned += amount }
        log(reason, amount, .sparks)
        checkLevelUp()
    }

    var aiPhotoCheckOn: Bool { !(state.aiPhotoCheckOff ?? false) }

    func previewBreakdown(for chore: Chore, liveCamera: Bool = false, rollCrit: Bool = false,
                          unverified: Bool = false, at now: Date = .now) -> PointBreakdown {
        var b = PointBreakdown()
        let base = chore.difficulty.basePoints
        b.lines.append(PointLine(label: "\(chore.difficulty.label) chore", amount: base, icon: chore.difficulty.icon))

        let proofAdj = Int((Double(base) * (chore.proof.multiplier - 1)).rounded())
        if proofAdj != 0 {
            b.lines.append(PointLine(label: "\(chore.proof.label) proof", amount: proofAdj, icon: chore.proof.icon))
        }
        if liveCamera && (chore.proof == .photo || chore.proof == .beforeAfter) {
            b.lines.append(PointLine(label: "Fresh camera photo", amount: max(2, base / 10), icon: "camera.aperture"))
        }
        if unverified {
            b.lines.append(PointLine(label: "Photo couldn't be verified −50%", amount: -(b.subtotal / 2), icon: "eye.slash"))
        }
        if let d = chore.effectiveDeadline(on: now), now <= d {
            b.lines.append(PointLine(label: "Beat the deadline", amount: max(3, base / 5), icon: "alarm.fill"))
        }
        if chore.requiresReview {
            b.lines.append(PointLine(label: "Verified by \(partnerDisplayName)", amount: max(3, base * 15 / 100), icon: "checkmark.seal.fill"))
        }

        let streak = projectedStreak
        let streakPct = min(max(streak - 1, 0), 10) * 5
        if streakPct > 0 {
            b.lines.append(PointLine(label: "\(streak)-day streak +\(streakPct)%", amount: max(1, b.subtotal * streakPct / 100), icon: "flame.fill"))
        }
        if todayLog.choresCompleted == 0 {
            b.lines.append(PointLine(label: "First chore of the day", amount: 10, icon: "sunrise.fill"))
        }
        if state.doubleSparkCharges > 0 {
            b.lines.append(PointLine(label: "Spark Boost ×1.5", amount: max(1, b.subtotal / 2), icon: "bolt.fill"))
        }
        if rollCrit && Double.random(in: 0..<1) < Self.critChance {
            b.isCrit = true
            b.lines.append(PointLine(label: "CRITICAL CLEAN ×2", amount: max(1, b.subtotal), icon: "sparkles"))
        }
        return b
    }

    @discardableResult
    func submit(chore: Chore, photos: [UIImage], note: String, liveCamera: Bool, check: PhotoCheck = .none) -> Submission {
        let files = photos.compactMap { PhotoStore.save($0) }

        var needsPartner = chore.requiresReview && hasPartner
        var unverifiedSolo = false
        var aiNote: String?
        var aiVerified: Bool?
        switch check {
        case .none:
            break
        case .verified(let observed):
            aiNote = observed
            aiVerified = true
        case .unverified(let reason):
            aiNote = reason
            if hasPartner { needsPartner = true } else { unverifiedSolo = true }
        case .partnerAppeal(let note):
            aiNote = note
            aiVerified = false
            needsPartner = true
        }

        let breakdown = previewBreakdown(for: chore, liveCamera: liveCamera, rollCrit: true, unverified: unverifiedSolo)
        if state.doubleSparkCharges > 0 { state.doubleSparkCharges -= 1 }

        var sub = Submission(choreID: chore.id, choreTitle: chore.title, choreEmoji: chore.emoji,
                             photoFiles: files, note: note, breakdown: breakdown,
                             previousCompletion: chore.lastCompletedAt)
        sub.aiNote = aiNote
        sub.aiVerified = aiVerified

        if let i = state.chores.firstIndex(where: { $0.id == chore.id }) {
            state.chores[i].lastCompletedAt = .now
            state.chores[i].completionCount += 1
        }
        registerActivity()
        let hour = Calendar.current.component(.hour, from: .now)
        updateTodayLog { log in
            log.choresCompleted += 1
            if chore.difficulty == .big || chore.difficulty == .epic { log.bigChores += 1 }
            if chore.proof == .beforeAfter { log.beforeAfter += 1 }
            if hour < 12 { log.beforeNoon += 1 }
        }

        if needsPartner {
            sub.status = .pending
        } else {
            sub.status = .approved
            sub.reviewedAt = .now
            award(breakdown.total, reason: "\(chore.emoji) \(chore.title)")
        }
        state.submissions.insert(sub, at: 0)
        return sub
    }

    var pendingSubmissions: [Submission] {
        state.submissions.filter { $0.status == .pending }
    }

    func pendingSubmission(for chore: Chore) -> Submission? {
        state.submissions.first { $0.choreID == chore.id && $0.status == .pending }
    }

    func latestSubmission(for chore: Chore) -> Submission? {
        state.submissions.first { $0.choreID == chore.id }
    }

    func approve(_ id: UUID, comment: String, goldStar: Bool) {
        guard let i = state.submissions.firstIndex(where: { $0.id == id }) else { return }
        var s = state.submissions[i]
        guard s.status == .pending else { return }
        if goldStar {
            let bonus = max(5, s.breakdown.total / 4)
            s.breakdown.lines.append(PointLine(label: "Gold star from \(partnerDisplayName)", amount: bonus, icon: "star.circle.fill"))
        }
        s.status = .approved
        s.partnerComment = comment
        s.goldStar = goldStar
        s.reviewedAt = .now
        state.submissions[i] = s
        award(s.breakdown.total, reason: "\(s.choreEmoji) \(s.choreTitle) (verified)")
    }

    func reject(_ id: UUID, comment: String) {
        guard let i = state.submissions.firstIndex(where: { $0.id == id }) else { return }
        var s = state.submissions[i]
        guard s.status == .pending else { return }
        s.status = .rejected
        s.partnerComment = comment
        s.reviewedAt = .now
        state.submissions[i] = s
        if let c = state.chores.firstIndex(where: { $0.id == s.choreID }) {
            state.chores[c].lastCompletedAt = s.previousCompletion
            state.chores[c].completionCount = max(0, state.chores[c].completionCount - 1)
        }
        log("\(s.choreEmoji) \(s.choreTitle) sent back", 0, .sparks)
    }

    func lastRejection(for chore: Chore) -> Submission? {
        guard let latest = latestSubmission(for: chore), latest.status == .rejected else { return nil }
        return latest
    }

    func gift(_ amount: Int, message: String) {
        let text = message.isEmpty ? "Gift from \(partnerDisplayName)" : "\(partnerDisplayName): \(message)"
        award(amount, reason: "💌 \(text)")
    }

    // MARK: Chores CRUD

    func upsert(_ chore: Chore) {
        if let i = state.chores.firstIndex(where: { $0.id == chore.id }) {
            state.chores[i] = chore
        } else {
            state.chores.append(chore)
        }
    }

    func delete(_ chore: Chore) {
        state.chores.removeAll { $0.id == chore.id }
    }

    func archive(_ chore: Chore) {
        guard let i = state.chores.firstIndex(where: { $0.id == chore.id }) else { return }
        state.chores[i].isArchived = true
    }

    func canEdit(_ chore: Chore) -> Bool {
        chore.assignedBy == .me || partnerUnlocked
    }

    // MARK: Daily quests

    static let questPool: [QuestDef] = [
        QuestDef(id: "c2", title: "Complete 2 chores", icon: "checklist", target: 2, reward: 20, metric: \.choresCompleted),
        QuestDef(id: "c3", title: "Complete 3 chores", icon: "checklist", target: 3, reward: 35, metric: \.choresCompleted),
        QuestDef(id: "c5", title: "Complete 5 chores", icon: "checklist", target: 5, reward: 60, metric: \.choresCompleted),
        QuestDef(id: "big", title: "Finish a Big or Epic chore", icon: "flame.fill", target: 1, reward: 30, metric: \.bigChores),
        QuestDef(id: "ba", title: "Submit a before & after", icon: "photo.on.rectangle.angled", target: 1, reward: 25, metric: \.beforeAfter),
        QuestDef(id: "e100", title: "Earn 100 Sparks", icon: "sparkle", target: 100, reward: 25, metric: \.pointsEarned),
        QuestDef(id: "noon", title: "Finish a chore before noon", icon: "sunrise.fill", target: 1, reward: 20, metric: \.beforeNoon),
    ]

    var todaysQuests: [QuestDef] {
        var rng = SeededRNG(seed: UInt64(Self.dayNumber) &* 7919)
        let countQuests = Self.questPool.filter { $0.id.hasPrefix("c") }
        let others = Self.questPool.filter { !$0.id.hasPrefix("c") }.shuffled(using: &rng)
        let first = countQuests[Int(rng.next() % UInt64(countQuests.count))]
        return [first] + Array(others.prefix(2))
    }

    func progress(_ quest: QuestDef) -> Int { todayLog[keyPath: quest.metric] }

    func isClaimed(_ quest: QuestDef) -> Bool { todayLog.claimedQuests.contains(quest.id) }

    func claim(_ quest: QuestDef) {
        guard progress(quest) >= quest.target, !isClaimed(quest) else { return }
        updateTodayLog { $0.claimedQuests.append(quest.id) }
        award(quest.reward, reason: "Quest: \(quest.title)")
    }

    var canClaimDailyBonus: Bool {
        let log = todayLog
        return !log.bonusClaimed && todaysQuests.allSatisfy { log.claimedQuests.contains($0.id) }
    }

    func claimDailyBonus() {
        guard canClaimDailyBonus else { return }
        updateTodayLog { $0.bonusClaimed = true }
        state.tickets += 1
        log("All daily quests done", 1, .tickets)
    }

    // MARK: Gacha

    var affordablePulls: Int { state.sparks / Self.singleCost + state.tickets }

    func canPull(count: Int, payment: PullPayment) -> Bool {
        switch payment {
        case .ticket: return count == 1 && state.tickets > 0
        case .sparks: return state.sparks >= (count == 10 ? Self.tenCost : Self.singleCost * count)
        }
    }

    func pull(seriesID: String, count: Int, payment: PullPayment) -> [PullResult] {
        guard canPull(count: count, payment: payment) else { return [] }
        let series = Catalog.series(seriesID)
        switch payment {
        case .ticket:
            state.tickets -= 1
            log("Opened a \(series.name) capsule", -1, .tickets)
        case .sparks:
            let cost = count == 10 ? Self.tenCost : Self.singleCost * count
            state.sparks -= cost
            log("Opened \(count == 10 ? "a case of 10" : "a") \(series.name) capsule\(count == 10 ? "s" : "")", -cost, .sparks)
        }

        var results: [PullResult] = []
        var gotRarePlus = false
        for i in 0..<count {
            var minimum: Rarity = .common
            var pity = false
            if i == 0 && state.luckyCharms > 0 {
                state.luckyCharms -= 1
                minimum = .rare
            }
            if count == 10 && i == 9 && !gotRarePlus { minimum = max(minimum, .rare) }

            state.pullsSinceEpic += 1
            state.pullsSinceSecret += 1
            if state.pullsSinceSecret >= Self.secretPity {
                minimum = .secret
                pity = true
            } else if state.pullsSinceEpic >= Self.epicPity {
                minimum = max(minimum, .epic)
                pity = true
            }

            let rarity = rollRarity(minimum: minimum)
            if rarity >= .rare { gotRarePlus = true }
            if rarity >= .epic { state.pullsSinceEpic = 0 }
            if rarity == .secret { state.pullsSinceSecret = 0 }

            let pool = Catalog.figures(in: seriesID, rarity: rarity)
            guard let fig = pool.randomElement() else { continue }
            let granted = grant(fig)
            state.totalPulls += 1
            results.append(PullResult(figure: fig, isNew: granted.isNew, glitter: granted.glitter, wasPity: pity))
        }
        return results
    }

    private func rollRarity(minimum: Rarity) -> Rarity {
        let eligible = Rarity.allCases.filter { $0 >= minimum }
        let total = eligible.map(\.rate).reduce(0, +)
        var x = Double.random(in: 0..<total)
        for r in eligible {
            if x < r.rate { return r }
            x -= r.rate
        }
        return eligible.last ?? .common
    }

    private func grant(_ fig: FigureDef) -> (isNew: Bool, glitter: Int) {
        if var owned = state.owned[fig.id] {
            owned.count += 1
            state.owned[fig.id] = owned
            let g = fig.rarity.glitterValue
            state.glitter += g
            return (false, g)
        }
        state.owned[fig.id] = OwnedFigure(count: 1, firstObtained: .now)
        return (true, 0)
    }

    // MARK: Collection

    func ownedCount(in seriesID: String) -> Int {
        Catalog.figures(in: seriesID).filter { state.owned[$0.id] != nil }.count
    }

    func isSeriesComplete(_ seriesID: String) -> Bool {
        ownedCount(in: seriesID) == Catalog.figures(in: seriesID).count
    }

    func canClaimSeries(_ seriesID: String) -> Bool {
        isSeriesComplete(seriesID) && !state.claimedSeriesRewards.contains(seriesID)
    }

    func claimSeries(_ seriesID: String) {
        guard canClaimSeries(seriesID) else { return }
        let s = Catalog.series(seriesID)
        state.claimedSeriesRewards.append(seriesID)
        state.tickets += 2
        log("Completed \(s.name)", 2, .tickets)
        award(s.completionReward, reason: "🏆 Completed \(s.name)")
    }

    func polish(_ figureID: String) {
        guard var owned = state.owned[figureID], !owned.shiny, state.glitter >= Self.polishCost else { return }
        state.glitter -= Self.polishCost
        owned.shiny = true
        state.owned[figureID] = owned
        log("Polished \(Catalog.byID[figureID]?.name ?? "a figure") to shiny", -Self.polishCost, .glitter)
    }

    // MARK: Shop

    var dailyShelf: [FigureDef] {
        var rng = SeededRNG(seed: UInt64(Self.dayNumber) &* 104_729)
        let pool = Catalog.figures.filter { $0.rarity != .secret }
        let commons = pool.filter { $0.rarity == .common }.shuffled(using: &rng)
        let rares = pool.filter { $0.rarity == .rare }.shuffled(using: &rng)
        let epics = pool.filter { $0.rarity == .epic }.shuffled(using: &rng)
        return Array(commons.prefix(2)) + Array(rares.prefix(1)) + Array(epics.prefix(1))
    }

    func buyFigure(_ fig: FigureDef) -> PullResult? {
        guard let price = fig.rarity.shopPrice, state.sparks >= price else { return nil }
        state.sparks -= price
        log("Bought \(fig.name)", -price, .sparks)
        let g = grant(fig)
        return PullResult(figure: fig, isNew: g.isNew, glitter: g.glitter, wasPity: false)
    }

    static let shieldPrice = 250
    static let charmPrice = 300
    static let boostPrice = 350
    static let maxShields = 3

    func buyShield() {
        guard state.sparks >= Self.shieldPrice, state.streakShields < Self.maxShields else { return }
        state.sparks -= Self.shieldPrice
        state.streakShields += 1
        log("Bought a Streak Shield", -Self.shieldPrice, .sparks)
    }

    func buyCharm() {
        guard state.sparks >= Self.charmPrice else { return }
        state.sparks -= Self.charmPrice
        state.luckyCharms += 1
        log("Bought a Lucky Charm", -Self.charmPrice, .sparks)
    }

    func buyBoost() {
        guard state.sparks >= Self.boostPrice else { return }
        state.sparks -= Self.boostPrice
        state.doubleSparkCharges += 3
        log("Bought a Spark Boost", -Self.boostPrice, .sparks)
    }

    func exchangeGlitterForTicket() {
        guard state.glitter >= Self.glitterTicketCost else { return }
        state.glitter -= Self.glitterTicketCost
        state.tickets += 1
        log("Traded Glitter for a ticket", 1, .tickets)
    }

    func buyTheme(_ theme: ShelfTheme) {
        guard !state.ownedThemes.contains(theme), state.sparks >= theme.price else { return }
        state.sparks -= theme.price
        state.ownedThemes.append(theme)
        state.selectedTheme = theme
        log("Bought the \(theme.name) shelf", -theme.price, .sparks)
    }

    func selectTheme(_ theme: ShelfTheme) {
        guard state.ownedThemes.contains(theme) else { return }
        state.selectedTheme = theme
    }

    func addTreat(_ treat: Treat) { state.treats.append(treat) }

    func deleteTreat(_ treat: Treat) { state.treats.removeAll { $0.id == treat.id } }

    func redeem(_ treat: Treat) {
        guard state.sparks >= treat.cost else { return }
        state.sparks -= treat.cost
        state.redemptions.insert(Redemption(title: treat.title, emoji: treat.emoji, cost: treat.cost), at: 0)
        log("Redeemed \(treat.emoji) \(treat.title)", -treat.cost, .sparks)
    }

    // MARK: Partner

    func unlockPartner(pin: String) -> Bool {
        guard let stored = state.partnerPIN, stored == pin else { return false }
        partnerUnlocked = true
        return true
    }

    func setPartnerPIN(_ pin: String) {
        state.partnerPIN = pin
        partnerUnlocked = true
    }

    func lockPartner() { partnerUnlocked = false }
}
