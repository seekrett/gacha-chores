import SwiftUI

// MARK: - Rows (match supabase/setup.sql)

struct ProfileRow: Codable {
    let id: UUID
    var displayName: String
    var inviteCode: String?

    enum CodingKeys: String, CodingKey {
        case id, displayName = "display_name", inviteCode = "invite_code"
    }
}

private struct ProfileUpsert: Encodable {
    let id: UUID
    let displayName: String
    enum CodingKeys: String, CodingKey { case id, displayName = "display_name" }
}

private struct PartnershipRow: Decodable {
    let userID: UUID
    let partnerID: UUID
    enum CodingKeys: String, CodingKey { case userID = "user_id", partnerID = "partner_id" }
}

struct ReviewRow: Codable, Identifiable, Hashable {
    let id: UUID
    let userID: UUID
    let choreID: UUID
    let choreTitle: String
    let choreEmoji: String
    let note: String
    let aiNote: String?
    let aiVerified: Bool?
    let points: Int
    let breakdown: PointBreakdown
    let photoPaths: [String]
    let submittedAt: Date
    var status: String = "pending"
    var reviewerName: String? = nil
    var comment: String? = nil
    var goldStar: Bool? = nil

    enum CodingKeys: String, CodingKey {
        case id, note, points, breakdown, status, comment
        case userID = "user_id", choreID = "chore_id", choreTitle = "chore_title", choreEmoji = "chore_emoji"
        case aiNote = "ai_note", aiVerified = "ai_verified", photoPaths = "photo_paths", submittedAt = "submitted_at"
        case reviewerName = "reviewer_name", goldStar = "gold_star"
    }
}

/// The fields the owner reads back once a partner has decided.
private struct DecisionRow: Decodable {
    let id: UUID
    let status: String
    let reviewerName: String?
    let comment: String?
    let goldStar: Bool?
    let photoPaths: [String]

    enum CodingKeys: String, CodingKey {
        case id, status, comment
        case reviewerName = "reviewer_name", goldStar = "gold_star", photoPaths = "photo_paths"
    }
}

struct AssignedChoreRow: Codable, Identifiable, Hashable {
    let id: UUID
    let userID: UUID
    let partnerID: UUID
    var chore: Chore
    var deleted: Bool = false

    enum CodingKeys: String, CodingKey {
        case id, chore, deleted, userID = "user_id", partnerID = "partner_id"
    }
}

private struct GiftRow: Codable {
    var id: UUID? = nil
    let userID: UUID
    let fromName: String
    let amount: Int
    let message: String
    var claimed: Bool? = nil

    enum CodingKeys: String, CodingKey {
        case id, amount, message, claimed, userID = "user_id", fromName = "from_name"
    }
}

// MARK: - Sync

/// Keeps this phone in step with online partners: uploads proof that needs review,
/// applies partners' decisions, pulls chores partners assign, and claims Spark gifts.
@MainActor
final class PartnerSync: ObservableObject {
    weak var store: GameStore?
    private lazy var client = SupabaseClient()

    @Published private(set) var myID: UUID?
    @Published private(set) var inviteCode: String?
    /// People who check this phone's chores.
    @Published private(set) var myPartners: [OnlinePartner] = []
    /// People whose chores this phone checks.
    @Published private(set) var partnerFor: [OnlinePartner] = []
    /// Proof from `partnerFor` people waiting for this phone's decision.
    @Published private(set) var reviewsToDo: [ReviewRow] = []
    /// Chores this phone assigned to other people.
    @Published private(set) var choresIAssigned: [AssignedChoreRow] = []
    @Published private(set) var isRefreshing = false
    @Published var lastError: String?
    @Published private(set) var lastSynced: Date?

    private var syncedName: String?
    private var photoCache: [String: UIImage] = [:]

    var isConfigured: Bool { SupabaseConfig.isConfigured }
    var isOn: Bool { isConfigured && (store?.state.onlinePartnersOn ?? false) }

    private var myName: String {
        let name = store?.state.userName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? "Someone" : name
    }

    func reviewsToDo(for person: OnlinePartner) -> [ReviewRow] {
        reviewsToDo.filter { $0.userID == person.id }
    }

    func choresAssigned(to person: OnlinePartner) -> [AssignedChoreRow] {
        choresIAssigned.filter { $0.userID == person.id }
    }

    // MARK: Turning it on

    func turnOn() async {
        store?.state.onlinePartnersOn = true
        await refresh()
    }

    // MARK: Refresh

    func refresh() async {
        guard isOn, !isRefreshing, let store else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let me = try await ensureProfile()
            try await loadPartnerships(me: me, store: store)
            try await uploadPendingProof(me: me, store: store)
            try await applyDecisions(me: me, store: store)
            try await pullAssignedChores(me: me, store: store)
            try await claimGifts(me: me, store: store)

            reviewsToDo = try await client.select("reviews", [
                .init(name: "status", value: "eq.pending"),
                .init(name: "user_id", value: "neq.\(me.lower)"),
                .init(name: "order", value: "submitted_at.asc"),
            ])
            choresIAssigned = try await client.select("assigned_chores", [
                .init(name: "partner_id", value: "eq.\(me.lower)"),
                .init(name: "deleted", value: "eq.false"),
                .init(name: "order", value: "updated_at.desc"),
            ])
            lastSynced = .now
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func ensureProfile() async throws -> UUID {
        let session = try await client.ensureSession()
        if syncedName != myName || inviteCode == nil {
            let rows: [ProfileRow] = try await client.upsertReturning("profiles", ProfileUpsert(id: session.userID, displayName: myName))
            inviteCode = rows.first?.inviteCode
            syncedName = myName
        }
        myID = session.userID
        return session.userID
    }

    private func loadPartnerships(me: UUID, store: GameStore) async throws {
        let rows: [PartnershipRow] = try await client.select("partnerships", [.init(name: "select", value: "user_id,partner_id")])
        let others = Set(rows.flatMap { [$0.userID, $0.partnerID] }).subtracting([me])
        var names: [UUID: String] = [:]
        if !others.isEmpty {
            let list = others.map(\.lower).joined(separator: ",")
            let profiles: [ProfileRow] = try await client.select("profiles", [
                .init(name: "select", value: "id,display_name"),
                .init(name: "id", value: "in.(\(list))"),
            ])
            for p in profiles { names[p.id] = p.displayName.isEmpty ? "Someone" : p.displayName }
        }
        myPartners = rows.filter { $0.userID == me }
            .map { OnlinePartner(id: $0.partnerID, name: names[$0.partnerID] ?? "Someone") }
            .sorted { $0.name < $1.name }
        partnerFor = rows.filter { $0.partnerID == me }
            .map { OnlinePartner(id: $0.userID, name: names[$0.userID] ?? "Someone") }
            .sorted { $0.name < $1.name }
        if store.state.onlinePartners ?? [] != myPartners {
            store.state.onlinePartners = myPartners
        }
    }

    /// Sends proof that is waiting for an online partner.
    private func uploadPendingProof(me: UUID, store: GameStore) async throws {
        guard !myPartners.isEmpty else { return }
        for sub in store.state.submissions where sub.status == .pending && sub.awaitingUpload != false {
            var paths: [String] = []
            for (index, file) in sub.photoFiles.enumerated() {
                guard let image = PhotoStore.load(file),
                      let jpeg = image.resizedForUpload().jpegData(compressionQuality: 0.7) else { continue }
                let path = "\(me.lower)/\(sub.id.lower)/\(index).jpg"
                try await client.upload(jpeg, to: path)
                paths.append(path)
            }
            let row = ReviewRow(id: sub.id, userID: me, choreID: sub.choreID, choreTitle: sub.choreTitle,
                                choreEmoji: sub.choreEmoji, note: sub.note, aiNote: sub.aiNote, aiVerified: sub.aiVerified,
                                points: sub.breakdown.total, breakdown: sub.breakdown, photoPaths: paths,
                                submittedAt: sub.submittedAt)
            try await client.insert("reviews", ReviewUpload(row), onConflict: "ignore")
            if let i = store.state.submissions.firstIndex(where: { $0.id == sub.id }) {
                store.state.submissions[i].awaitingUpload = false
            }
        }
    }

    /// Applies partners' approvals and send-backs, then clears them from the server.
    private func applyDecisions(me: UUID, store: GameStore) async throws {
        let rows: [DecisionRow] = try await client.select("reviews", [
            .init(name: "select", value: "id,status,reviewer_name,comment,gold_star,photo_paths"),
            .init(name: "user_id", value: "eq.\(me.lower)"),
        ])
        var finished: [DecisionRow] = []
        var messages: [String] = []
        for row in rows {
            let local = store.state.submissions.first { $0.id == row.id }
            let stillPending = local?.status == .pending
            if row.status == "pending" {
                // Decided on this phone (same-phone partner) or deleted: withdraw it.
                if !stillPending { finished.append(row) }
                continue
            }
            if stillPending, let local {
                let who = row.reviewerName.flatMap { $0.isEmpty ? nil : $0 } ?? "Your partner"
                if row.status == "approved" {
                    let total = store.approve(local.id, comment: row.comment ?? "", goldStar: row.goldStar ?? false, reviewer: who)
                    messages.append("\(who) approved \(local.choreEmoji) \(local.choreTitle): +\(total) Sparks")
                } else {
                    store.reject(local.id, comment: row.comment ?? "", reviewer: who)
                    messages.append("\(who) sent back \(local.choreEmoji) \(local.choreTitle)" + ((row.comment ?? "").isEmpty ? "." : ": \u{201C}\(row.comment!)\u{201D}"))
                }
            }
            finished.append(row)
        }
        if !messages.isEmpty {
            Haptics.success()
            store.notice = messages.joined(separator: "\n")
        }
        guard !finished.isEmpty else { return }
        try await client.removeObjects(finished.flatMap(\.photoPaths))
        try await client.delete("reviews", [.init(name: "id", value: "in.(\(finished.map(\.id.lower).joined(separator: ",")))")])
    }

    private func pullAssignedChores(me: UUID, store: GameStore) async throws {
        let rows: [AssignedChoreRow] = try await client.select("assigned_chores", [.init(name: "user_id", value: "eq.\(me.lower)")])
        var names = Dictionary(uniqueKeysWithValues: myPartners.map { ($0.id, $0.name) })
        for p in partnerFor where names[p.id] == nil { names[p.id] = p.name }
        var chores = store.state.chores
        for row in rows {
            let index = chores.firstIndex { $0.id == row.id }
            if row.deleted {
                if let index, !chores[index].isArchived { chores[index].isArchived = true }
                continue
            }
            var incoming = row.chore
            incoming.id = row.id
            incoming.assignedBy = .partner
            incoming.requiresReview = true
            incoming.remoteAssignerID = row.partnerID
            incoming.remoteAssignerName = names[row.partnerID] ?? row.chore.remoteAssignerName
            if let index {
                var merged = chores[index]
                merged.title = incoming.title
                merged.notes = incoming.notes
                merged.emoji = incoming.emoji
                merged.difficulty = incoming.difficulty
                merged.proof = incoming.proof
                merged.recurrence = incoming.recurrence
                merged.deadline = incoming.deadline
                merged.assignedBy = .partner
                merged.requiresReview = true
                merged.remoteAssignerID = incoming.remoteAssignerID
                merged.remoteAssignerName = incoming.remoteAssignerName
                merged.isArchived = false
                chores[index] = merged
            } else {
                incoming.lastCompletedAt = nil
                incoming.completionCount = 0
                incoming.isArchived = false
                incoming.createdAt = .now
                chores.append(incoming)
            }
        }
        if chores != store.state.chores { store.state.chores = chores }
    }

    private func claimGifts(me: UUID, store: GameStore) async throws {
        let gifts: [GiftRow] = try await client.select("gifts", [
            .init(name: "user_id", value: "eq.\(me.lower)"),
            .init(name: "claimed", value: "eq.false"),
        ])
        guard !gifts.isEmpty else { return }
        var claimed = store.state.claimedGiftIDs ?? []
        for gift in gifts {
            guard let id = gift.id, !claimed.contains(id) else { continue }
            store.gift(gift.amount, message: gift.message, from: gift.fromName.isEmpty ? "Your partner" : gift.fromName)
            claimed.append(id)
        }
        store.state.claimedGiftIDs = Array(claimed.suffix(500))
        let ids = gifts.compactMap(\.id).map(\.lower).joined(separator: ",")
        try await client.update("gifts", ["claimed": true], [.init(name: "id", value: "in.(\(ids))")])
    }

    // MARK: Partner actions

    /// Become the partner of the person who owns `code`.
    func join(code: String) async -> Bool {
        do {
            _ = try await ensureProfile()
            _ = try await client.rpc("join_as_partner", ["code": code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()])
            Haptics.success()
            await refresh()
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    /// Stop `person` from checking this phone's chores.
    func remove(partner person: OnlinePartner) async {
        await perform {
            guard let me = self.myID else { return }
            try await self.client.delete("partnerships", [
                .init(name: "user_id", value: "eq.\(me.lower)"),
                .init(name: "partner_id", value: "eq.\(person.id.lower)"),
            ])
        }
    }

    /// Stop checking `person`'s chores.
    func leave(_ person: OnlinePartner) async {
        await perform {
            guard let me = self.myID else { return }
            try await self.client.delete("partnerships", [
                .init(name: "user_id", value: "eq.\(person.id.lower)"),
                .init(name: "partner_id", value: "eq.\(me.lower)"),
            ])
        }
    }

    func decide(_ review: ReviewRow, approve: Bool, comment: String, goldStar: Bool) async -> Bool {
        struct Params: Encodable {
            let p_review_id: UUID
            let p_approve: Bool
            let p_comment: String
            let p_gold_star: Bool
        }
        do {
            _ = try await client.rpc("decide_review", Params(p_review_id: review.id, p_approve: approve,
                                                             p_comment: comment, p_gold_star: goldStar))
            reviewsToDo.removeAll { $0.id == review.id }
            return true
        } catch {
            lastError = error.localizedDescription
            await refresh()
            return false
        }
    }

    func assign(_ chore: Chore, to person: OnlinePartner) async -> Bool {
        do {
            guard let me = myID else { throw SupabaseError(message: "Not connected yet. Pull to refresh.", status: 0) }
            var c = chore
            c.assignedBy = .partner
            c.requiresReview = true
            c.remoteAssignerID = me
            c.remoteAssignerName = myName
            c.lastCompletedAt = nil
            c.completionCount = 0
            let row = AssignedChoreRow(id: c.id, userID: person.id, partnerID: me, chore: c)
            try await client.insert("assigned_chores", AssignedUpload(row), onConflict: "merge")
            choresIAssigned.removeAll { $0.id == row.id }
            choresIAssigned.insert(row, at: 0)
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func unassign(_ row: AssignedChoreRow) async {
        await perform {
            try await self.client.update("assigned_chores", ["deleted": true], [.init(name: "id", value: "eq.\(row.id.lower)")])
        }
    }

    func sendGift(_ amount: Int, message: String, to person: OnlinePartner) async -> Bool {
        do {
            try await client.insert("gifts", GiftRow(userID: person.id, fromName: myName, amount: amount, message: message))
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func photo(_ path: String) async -> UIImage? {
        if let cached = photoCache[path] { return cached }
        guard let data = try? await client.download(path), let image = UIImage(data: data) else { return nil }
        photoCache[path] = image
        return image
    }

    private func perform(_ action: @escaping () async throws -> Void) async {
        do {
            try await action()
            await refresh()
        } catch {
            lastError = error.localizedDescription
        }
    }
}

// Upload shapes: only the columns the database lets the client write.

private struct ReviewUpload: Encodable {
    let row: ReviewRow
    init(_ row: ReviewRow) { self.row = row }

    enum CodingKeys: String, CodingKey {
        case id, note, points, breakdown
        case userID = "user_id", choreID = "chore_id", choreTitle = "chore_title", choreEmoji = "chore_emoji"
        case aiNote = "ai_note", aiVerified = "ai_verified", photoPaths = "photo_paths", submittedAt = "submitted_at"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(row.id, forKey: .id)
        try c.encode(row.userID, forKey: .userID)
        try c.encode(row.choreID, forKey: .choreID)
        try c.encode(row.choreTitle, forKey: .choreTitle)
        try c.encode(row.choreEmoji, forKey: .choreEmoji)
        try c.encode(row.note, forKey: .note)
        try c.encode(row.aiNote, forKey: .aiNote)
        try c.encode(row.aiVerified, forKey: .aiVerified)
        try c.encode(row.points, forKey: .points)
        try c.encode(row.breakdown, forKey: .breakdown)
        try c.encode(row.photoPaths, forKey: .photoPaths)
        try c.encode(row.submittedAt, forKey: .submittedAt)
    }
}

private struct AssignedUpload: Encodable {
    let row: AssignedChoreRow
    init(_ row: AssignedChoreRow) { self.row = row }

    enum CodingKeys: String, CodingKey {
        case id, chore, deleted, userID = "user_id", partnerID = "partner_id", updatedAt = "updated_at"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(row.id, forKey: .id)
        try c.encode(row.userID, forKey: .userID)
        try c.encode(row.partnerID, forKey: .partnerID)
        try c.encode(row.chore, forKey: .chore)
        try c.encode(false, forKey: .deleted)
        try c.encode(Date(), forKey: .updatedAt)
    }
}

extension UUID {
    /// Supabase stores ids lowercase; storage folder names must match `auth.uid()::text`.
    var lower: String { uuidString.lowercased() }
}

extension UIImage {
    func resizedForUpload(maxDimension: CGFloat = 1600) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxDimension else { return self }
        let scale = maxDimension / longest
        let newSize = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: newSize, format: format).image { _ in draw(in: CGRect(origin: .zero, size: newSize)) }
    }
}
