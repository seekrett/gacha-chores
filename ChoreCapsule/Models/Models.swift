import SwiftUI

// MARK: - Chores

enum Difficulty: String, Codable, CaseIterable, Identifiable {
    case quick, standard, big, epic
    var id: String { rawValue }

    var label: String {
        switch self {
        case .quick: "Quick"
        case .standard: "Standard"
        case .big: "Big"
        case .epic: "Epic"
        }
    }

    var detail: String {
        switch self {
        case .quick: "about 5 min"
        case .standard: "about 15 min"
        case .big: "about 45 min"
        case .epic: "an hour or more"
        }
    }

    var basePoints: Int {
        switch self {
        case .quick: 15
        case .standard: 30
        case .big: 60
        case .epic: 120
        }
    }

    var icon: String {
        switch self {
        case .quick: "leaf.fill"
        case .standard: "star.fill"
        case .big: "flame.fill"
        case .epic: "crown.fill"
        }
    }

    var color: Color {
        switch self {
        case .quick: Palette.mint
        case .standard: Palette.sky
        case .big: Palette.peach
        case .epic: Palette.lavender
        }
    }
}

enum ProofType: String, Codable, CaseIterable, Identifiable {
    case photo, beforeAfter, note, honor
    var id: String { rawValue }

    var label: String {
        switch self {
        case .photo: "Photo"
        case .beforeAfter: "Before & after"
        case .note: "Written note"
        case .honor: "Honor system"
        }
    }

    var icon: String {
        switch self {
        case .photo: "camera.fill"
        case .beforeAfter: "photo.on.rectangle.angled"
        case .note: "square.and.pencil"
        case .honor: "hand.raised.fill"
        }
    }

    /// Stronger evidence pays more. This nudges you toward proof you can't fudge.
    var multiplier: Double {
        switch self {
        case .photo: 1.0
        case .beforeAfter: 1.3
        case .note: 0.8
        case .honor: 0.5
        }
    }

    var bonusText: String {
        switch self {
        case .photo: "Standard"
        case .beforeAfter: "+30%"
        case .note: "−20%"
        case .honor: "−50%"
        }
    }

    var explanation: String {
        switch self {
        case .photo: "Snap one photo of the finished job."
        case .beforeAfter: "Two photos: the mess, then the glow-up. Pays the most."
        case .note: "Write at least a sentence about what you did."
        case .honor: "No proof, just a promise. Pays half."
        }
    }
}

enum Recurrence: String, Codable, CaseIterable, Identifiable {
    case once, daily, weekly
    var id: String { rawValue }
    var label: String {
        switch self {
        case .once: "One-time"
        case .daily: "Daily"
        case .weekly: "Weekly"
        }
    }
}

enum Assigner: String, Codable {
    case me, partner
}

struct Chore: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var notes: String = ""
    var emoji: String = "🧹"
    var difficulty: Difficulty = .standard
    var proof: ProofType = .photo
    var recurrence: Recurrence = .once
    /// For one-time chores: a full date. For daily chores: only the time of day is used.
    var deadline: Date? = nil
    var assignedBy: Assigner = .me
    var requiresReview: Bool = false
    var createdAt = Date()
    var lastCompletedAt: Date? = nil
    var completionCount: Int = 0
    var isArchived = false
    /// Set when an online partner assigned this chore from their own phone.
    var remoteAssignerID: UUID? = nil
    var remoteAssignerName: String? = nil

    func isDone(on now: Date = .now) -> Bool {
        guard let last = lastCompletedAt else { return false }
        let cal = Calendar.current
        switch recurrence {
        case .once: return true
        case .daily: return cal.isDate(last, inSameDayAs: now)
        case .weekly: return cal.isDate(last, equalTo: now, toGranularity: .weekOfYear)
        }
    }

    func effectiveDeadline(on now: Date = .now) -> Date? {
        guard let deadline else { return nil }
        switch recurrence {
        case .once:
            return deadline
        case .daily:
            let cal = Calendar.current
            let c = cal.dateComponents([.hour, .minute], from: deadline)
            return cal.date(bySettingHour: c.hour ?? 23, minute: c.minute ?? 59, second: 0, of: now)
        case .weekly:
            return nil
        }
    }

    func isOverdue(on now: Date = .now) -> Bool {
        guard !isDone(on: now), let d = effectiveDeadline(on: now) else { return false }
        return now > d
    }
}

// MARK: - Proof submissions

enum SubmissionStatus: String, Codable {
    case pending, approved, rejected
}

struct PointLine: Identifiable, Codable, Hashable {
    var id = UUID()
    var label: String
    var amount: Int
    var icon: String
}

struct PointBreakdown: Codable, Hashable {
    var lines: [PointLine] = []
    var isCrit = false
    var total: Int { max(1, lines.reduce(0) { $0 + $1.amount }) }
    var subtotal: Int { lines.reduce(0) { $0 + $1.amount } }
}

struct Submission: Identifiable, Codable, Hashable {
    var id = UUID()
    var choreID: UUID
    var choreTitle: String
    var choreEmoji: String
    var submittedAt = Date()
    var photoFiles: [String] = []
    var note: String = ""
    var status: SubmissionStatus = .pending
    var breakdown: PointBreakdown
    var partnerComment: String = ""
    var goldStar = false
    var reviewedAt: Date? = nil
    var previousCompletion: Date? = nil
    /// What the AI photo check saw (optional so older saves still load).
    var aiNote: String? = nil
    var aiVerified: Bool? = nil
    /// True while this proof still has to be sent to online partners.
    var awaitingUpload: Bool? = nil
    /// Who approved or sent it back.
    var reviewerName: String? = nil
}

// MARK: - Collection & economy

struct OwnedFigure: Codable, Hashable {
    var count: Int
    var firstObtained: Date
    var shiny = false
}

enum Currency: String, Codable {
    case sparks, glitter, tickets
}

struct LedgerEntry: Identifiable, Codable, Hashable {
    var id = UUID()
    var date = Date()
    var text: String
    var amount: Int
    var currency: Currency
}

struct DailyLog: Codable, Hashable {
    var choresCompleted = 0
    var pointsEarned = 0
    var bigChores = 0
    var beforeAfter = 0
    var beforeNoon = 0
    var claimedQuests: [String] = []
    var bonusClaimed = false
}

struct Treat: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var emoji: String
    var cost: Int
    var addedBy: Assigner = .me
}

struct Redemption: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var emoji: String
    var cost: Int
    var date = Date()
}

enum ShelfTheme: String, Codable, CaseIterable, Identifiable {
    case cloud, wood, sakura, neon, starry
    var id: String { rawValue }

    var name: String {
        switch self {
        case .cloud: "Cotton Cloud"
        case .wood: "Cozy Oak"
        case .sakura: "Sakura Window"
        case .neon: "Neon Arcade"
        case .starry: "Starry Night"
        }
    }

    var price: Int {
        switch self {
        case .cloud: 0
        case .wood: 400
        case .sakura: 700
        case .neon: 900
        case .starry: 1200
        }
    }

    var colors: [Color] {
        switch self {
        case .cloud: [Color(hex: 0xFDF0F7), Color(hex: 0xE9E4FF)]
        case .wood: [Color(hex: 0xF6E3C8), Color(hex: 0xE2C39B)]
        case .sakura: [Color(hex: 0xFFE1EC), Color(hex: 0xFFC2D6)]
        case .neon: [Color(hex: 0x1C1036), Color(hex: 0x3A1859)]
        case .starry: [Color(hex: 0x0E1838), Color(hex: 0x283D7A)]
        }
    }

    var shelf: Color {
        switch self {
        case .cloud: Color(hex: 0xFFFFFF)
        case .wood: Color(hex: 0xA8743F)
        case .sakura: Color(hex: 0xF08DB0)
        case .neon: Color(hex: 0x00E5FF)
        case .starry: Color(hex: 0xC9B8FF)
        }
    }

    var isDark: Bool { self == .neon || self == .starry }
}

// MARK: - Saved state

struct AppState: Codable {
    var userName = ""
    var partnerName = ""
    var partnerPIN: String? = nil

    var sparks = 300
    var glitter = 0
    var tickets = 1
    var lifetimeSparks = 0
    var level = 1

    var streak = 0
    var bestStreak = 0
    var lastActiveDay: Date? = nil

    var streakShields = 0
    var luckyCharms = 0
    var doubleSparkCharges = 0

    var chores: [Chore] = []
    var submissions: [Submission] = []

    var owned: [String: OwnedFigure] = [:]
    var claimedSeriesRewards: [String] = []
    var pullsSinceEpic = 0
    var pullsSinceSecret = 0
    var totalPulls = 0

    var ownedThemes: [ShelfTheme] = [.cloud]
    var selectedTheme: ShelfTheme = .cloud

    var treats: [Treat] = []
    var redemptions: [Redemption] = []

    var dailyLogs: [String: DailyLog] = [:]
    var ledger: [LedgerEntry] = []

    /// nil or false means the AI photo check is on (optional so older saves still load).
    var aiPhotoCheckOff: Bool? = nil

    /// Online partners (checking chores from their own phones). Optional so older saves still load.
    var onlinePartnersOn: Bool? = nil
    var onlinePartners: [OnlinePartner]? = nil
    var claimedGiftIDs: [UUID]? = nil
}

struct OnlinePartner: Codable, Hashable, Identifiable {
    var id: UUID
    var name: String
}
