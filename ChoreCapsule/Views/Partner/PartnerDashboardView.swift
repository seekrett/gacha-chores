import SwiftUI

/// The Partner tab: proof to review, your own proof waiting, and the people you're linked with.
struct PartnerDashboardView: View {
    @EnvironmentObject var store: GameStore
    @EnvironmentObject var sync: PartnerSync
    @State private var showManage = false
    @State private var reviewing: ReviewRow?

    private var waitingOnMe: [ReviewRow] { sync.reviewsToDo }
    private var myPending: [Submission] { store.pendingSubmissions }

    private var recentlyReviewed: [Submission] {
        let weekAgo = Date().addingTimeInterval(-7 * 86_400)
        return store.state.submissions
            .filter { $0.status != .pending && $0.reviewerName != nil && ($0.reviewedAt ?? .distantPast) > weekAgo }
            .prefix(5)
            .map { $0 }
    }

    private var hasAnyPartnerLink: Bool {
        store.hasPartner || !sync.partnerFor.isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    if !hasAnyPartnerLink {
                        setupCard
                    }
                    if sync.isOn && (!sync.partnerFor.isEmpty || !waitingOnMe.isEmpty) {
                        reviewQueue
                    }
                    if !myPending.isEmpty || !recentlyReviewed.isEmpty {
                        myProofCard
                    }
                    if hasAnyPartnerLink {
                        peopleCard
                    }
                    statusFooter
                }
                .padding()
            }
            .background(AppBackground())
            .navigationTitle("Partner")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showManage = true } label: { Image(systemName: "person.badge.plus") }
                        .accessibilityLabel("Invite or manage partners")
                }
            }
            .navigationDestination(for: OnlinePartner.self) { PartnerPersonView(person: $0) }
            .refreshable { await sync.refresh() }
            .task { await sync.refresh() }
            .sheet(isPresented: $showManage) { PartnerView() }
            .sheet(item: $reviewing) { review in
                RemoteReviewView(review: review, person: person(for: review))
            }
        }
    }

    private func person(for review: ReviewRow) -> OnlinePartner {
        sync.partnerFor.first { $0.id == review.userID } ?? OnlinePartner(id: review.userID, name: "Someone")
    }

    // MARK: No partner yet

    private var setupCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.2.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(LinearGradient(colors: [Palette.pink, Palette.lavender], startPoint: .top, endPoint: .bottom))
            Text("Get an accountability partner").font(.title3.bold())
            Text(store.aiPhotoCheckReady
                 ? "Right now only photo chores the AI can check earn Sparks. A partner can verify any chore, assign you new ones, and cheer you on with Sparks."
                 : "Chores only earn Sparks once someone verifies them. Add a partner to check your proof, assign you chores, and cheer you on with Sparks.")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button { showManage = true } label: {
                Label(sync.isConfigured ? "Invite a partner" : "Set up a partner", systemImage: "person.badge.plus")
            }
            .buttonStyle(BubblyButtonStyle())
        }
        .frame(maxWidth: .infinity)
        .card()
    }

    // MARK: Proof waiting for me

    private var reviewQueue: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("To review", systemImage: "checkmark.seal").font(.headline)
                Spacer()
                if !waitingOnMe.isEmpty {
                    CountBadge(count: waitingOnMe.count)
                }
            }
            if waitingOnMe.isEmpty {
                HStack(spacing: 10) {
                    Text("✨").font(.title)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("All caught up").font(.subheadline.bold())
                        Text("New proof from \(sync.partnerFor.map(\.name).formatted(.list(type: .or))) shows up here.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            ForEach(waitingOnMe) { review in
                Button { reviewing = review } label: { ReviewQueueRow(review: review, personName: person(for: review).name) }
                    .buttonStyle(.plain)
            }
        }
        .card()
    }

    // MARK: My proof

    private var myProofCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Your proof", systemImage: "hourglass").font(.headline)
            ForEach(myPending) { sub in
                HStack(spacing: 12) {
                    Text(sub.choreEmoji).font(.title2).frame(width: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(sub.choreTitle).font(.subheadline.bold())
                        Text(pendingStatus(sub)).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Label("\(sub.breakdown.total)", systemImage: "sparkle")
                        .font(.subheadline.bold()).foregroundStyle(Palette.sparks.opacity(0.7))
                }
            }
            if !myPending.isEmpty && store.state.partnerPIN != nil {
                Button { showManage = true } label: {
                    Label("Hand the phone to \(store.state.partnerName.isEmpty ? "your partner" : store.state.partnerName)",
                          systemImage: "iphone.and.arrow.forward")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            if !recentlyReviewed.isEmpty {
                if !myPending.isEmpty { Divider() }
                Text("Recently reviewed").font(.caption.bold()).foregroundStyle(.secondary)
                ForEach(recentlyReviewed) { sub in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: sub.status == .approved ? "checkmark.circle.fill" : "arrow.uturn.backward.circle.fill")
                            .font(.title3)
                            .foregroundStyle(sub.status == .approved ? Palette.mint.adjusted(brightness: -0.2) : .orange)
                            .frame(width: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(sub.choreEmoji) \(sub.choreTitle)").font(.subheadline.bold())
                            Text("\(sub.reviewerName ?? "Partner") \(sub.status == .approved ? "approved" : "sent it back")"
                                 + (sub.goldStar ? " with a gold star ⭐️" : ""))
                                .font(.caption).foregroundStyle(.secondary)
                            if !sub.partnerComment.isEmpty {
                                Text("\u{201C}\(sub.partnerComment)\u{201D}").font(.caption).italic()
                            }
                        }
                        Spacer()
                        if sub.status == .approved {
                            Text("+\(sub.breakdown.total)").font(.subheadline.bold()).foregroundStyle(Palette.sparks)
                        }
                    }
                }
            }
        }
        .card()
    }

    private func pendingStatus(_ sub: Submission) -> String {
        if store.hasOnlinePartner {
            return sub.awaitingUpload == false
                ? "Waiting for \(store.partnerDisplayName) · \(sub.submittedAt.formatted(.relative(presentation: .named)))"
                : "Sending to \(store.partnerDisplayName)…"
        }
        if store.hasPartner { return "Waiting for \(store.partnerDisplayName) on this phone" }
        return "Held until you add a partner"
    }

    // MARK: People

    private var peopleCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Your people", systemImage: "person.2.fill").font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text("Checking your chores").font(.caption.bold()).foregroundStyle(.secondary)
                if store.hasPartner {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            if store.state.partnerPIN != nil {
                                PersonChip(name: store.state.partnerName.isEmpty ? "Partner" : store.state.partnerName, subtitle: "This phone")
                            }
                            ForEach(store.onlinePartners) { PersonChip(name: $0.name, subtitle: "Their phone") }
                        }
                    }
                } else {
                    Button("Invite someone to check your chores") { showManage = true }.font(.subheadline)
                }
            }

            if sync.isOn {
                VStack(alignment: .leading, spacing: 8) {
                    Text("You check chores for").font(.caption.bold()).foregroundStyle(.secondary)
                    if sync.partnerFor.isEmpty {
                        Button("Enter a friend's invite code") { showManage = true }.font(.subheadline)
                    }
                    ForEach(sync.partnerFor) { person in
                        NavigationLink(value: person) {
                            HStack(spacing: 12) {
                                Avatar(name: person.name, size: 36)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(person.name).font(.subheadline.bold())
                                    Text("Assign chores · send Sparks").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                let waiting = sync.reviewsToDo(for: person).count
                                if waiting > 0 { CountBadge(count: waiting) }
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .card()
    }

    @ViewBuilder
    private var statusFooter: some View {
        if let error = sync.lastError, sync.isOn {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .font(.caption).foregroundStyle(.orange)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if sync.isOn, let synced = sync.lastSynced {
            Text("Updated \(synced, format: .relative(presentation: .named)) · pull down to refresh")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Pieces

private struct ReviewQueueRow: View {
    let review: ReviewRow
    let personName: String

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let path = review.photoPaths.last {
                    RemotePhoto(path: path, contentMode: .fill)
                } else {
                    Text(review.choreEmoji).font(.largeTitle)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(.tertiarySystemFill))
                }
            }
            .frame(width: 72, height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text("\(review.choreEmoji) \(review.choreTitle)").font(.subheadline.bold()).lineLimit(2)
                HStack(spacing: 6) {
                    Avatar(name: personName, size: 18)
                    Text("\(personName) · \(review.submittedAt.formatted(.relative(presentation: .named)))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if review.aiVerified == false {
                    Label("AI flagged this", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2.bold()).foregroundStyle(.orange)
                }
            }
            Spacer()
            VStack(spacing: 2) {
                Text("+\(review.points)").font(.headline).foregroundStyle(Palette.sparks)
                Text("Review").font(.caption2.bold()).foregroundStyle(Palette.berry)
            }
        }
        .contentShape(Rectangle())
    }
}

struct Avatar: View {
    let name: String
    var size: CGFloat = 40

    private var color: Color {
        let palette = [Palette.pink, Palette.lavender, Palette.mint, Palette.sky, Palette.peach]
        let index = name.unicodeScalars.reduce(0) { $0 + Int($1.value) } % palette.count
        return palette[index]
    }

    var body: some View {
        Text(String(name.prefix(1)).uppercased())
            .font(.system(size: size * 0.45, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Circle().fill(color.gradient))
    }
}

private struct PersonChip: View {
    let name: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 4) {
            Avatar(name: name, size: 44)
            Text(name).font(.caption.bold()).lineLimit(1)
            Text(subtitle).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(width: 76)
    }
}

private struct CountBadge: View {
    let count: Int
    var body: some View {
        Text("\(count)")
            .font(.caption.bold())
            .foregroundStyle(.white)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(Palette.berry))
    }
}
