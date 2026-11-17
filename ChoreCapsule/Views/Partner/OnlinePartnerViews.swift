import SwiftUI

// MARK: - Hub

/// Online partners: each person uses their own phone.
struct PartnersHubView: View {
    @EnvironmentObject var store: GameStore
    @EnvironmentObject var sync: PartnerSync
    @State private var nameDraft = ""
    @State private var code = ""
    @State private var joining = false
    @State private var turningOn = false
    @State private var removing: OnlinePartner?

    var body: some View {
        List {
            if sync.isOn {
                onlineSections
            } else {
                introSection
            }

            Section {
                NavigationLink {
                    SamePhonePartnerView()
                } label: {
                    Label("Same-phone partner (PIN)", systemImage: "person.2.badge.key.fill")
                }
            } footer: {
                Text("For a partner who reviews on this phone, unlocked with their PIN.")
            }
        }
        .navigationTitle("Partners")
        .navigationDestination(for: OnlinePartner.self) { PartnerPersonView(person: $0) }
        .refreshable { await sync.refresh() }
        .task { await sync.refresh() }
        .onAppear { nameDraft = store.state.userName }
        .confirmationDialog("Remove \(removing?.name ?? "")?", isPresented: Binding(
            get: { removing != nil }, set: { if !$0 { removing = nil } }
        ), titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                if let person = removing { Task { await sync.remove(partner: person) } }
            }
        } message: {
            Text("They'll stop seeing your proof. Chores they assigned stay on your list but can't be edited.")
        }
    }

    // MARK: Off

    private var introSection: some View {
        Section {
            VStack(spacing: 10) {
                Image(systemName: "iphone.radiowaves.left.and.right")
                    .font(.system(size: 44))
                    .foregroundStyle(LinearGradient(colors: [Palette.pink, Palette.lavender], startPoint: .top, endPoint: .bottom))
                Text("Partners on their own phones").font(.title3.bold()).multilineTextAlignment(.center)
                Text("Share an invite code with a friend. They can assign you chores and check your proof from their phone, and your Sparks unlock once they approve. You can check theirs too.")
                    .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)

            TextField("Your name (partners see this)", text: $nameDraft)
                .textInputAutocapitalization(.words)

            Button {
                store.state.userName = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                turningOn = true
                Task {
                    await sync.turnOn()
                    turningOn = false
                }
            } label: {
                HStack {
                    Text("Turn on online partners").font(.headline)
                    if turningOn { Spacer(); ProgressView() }
                }
            }
            .disabled(nameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || turningOn)

            if let error = sync.lastError {
                Text(error).font(.subheadline).foregroundStyle(.red)
            }
        } footer: {
            Text("Your chores, Sparks and collection stay on this phone. Only proof waiting for review, chores partners assign, and Spark gifts go through the partner server.")
        }
    }

    // MARK: On

    @ViewBuilder
    private var onlineSections: some View {
        Section {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your invite code").font(.caption).foregroundStyle(.secondary)
                    if let invite = sync.inviteCode {
                        Text(invite)
                            .font(.system(size: 30, weight: .heavy, design: .monospaced))
                            .tracking(4)
                            .textSelection(.enabled)
                    } else if sync.lastError != nil && !sync.isRefreshing {
                        Text("Not connected").font(.headline).foregroundStyle(.secondary)
                    } else {
                        ProgressView()
                    }
                }
                Spacer()
                if let invite = sync.inviteCode {
                    ShareLink(item: "Be my Chore Capsule accountability partner! In the app, open Partners and enter my code: \(invite)") {
                        Label("Share", systemImage: "square.and.arrow.up").labelStyle(.iconOnly).font(.title2)
                    }
                }
            }
            TextField("Your name", text: $store.state.userName)
                .onSubmit { Task { await sync.refresh() } }
        } footer: {
            Text("Give this code to someone you want checking your chores. They enter it on their phone.")
        }

        Section {
            if sync.myPartners.isEmpty {
                Text("Nobody yet. Share your invite code.").foregroundStyle(.secondary)
            }
            ForEach(sync.myPartners) { person in
                Label(person.name, systemImage: "person.crop.circle.badge.checkmark")
                    .swipeActions {
                        Button("Remove", role: .destructive) { removing = person }
                    }
            }
        } header: {
            Text("Checking your chores")
        } footer: {
            if !sync.myPartners.isEmpty {
                Text("Proof for chores that need verifying goes to them. Any one of them can approve it. Swipe to remove.")
            }
        }

        Section {
            ForEach(sync.partnerFor) { person in
                NavigationLink(value: person) {
                    HStack {
                        Label(person.name, systemImage: "person.crop.circle")
                        Spacer()
                        let waiting = sync.reviewsToDo(for: person).count
                        if waiting > 0 {
                            Text("\(waiting) to review")
                                .font(.caption.bold())
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Capsule().fill(Palette.pink.opacity(0.25)))
                        }
                    }
                }
            }
            HStack {
                TextField("Friend's invite code", text: $code)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .font(.body.monospaced())
                Button {
                    joining = true
                    Task {
                        if await sync.join(code: code) { code = "" }
                        joining = false
                    }
                } label: {
                    if joining { ProgressView() } else { Text("Join").bold() }
                }
                .disabled(code.trimmingCharacters(in: .whitespaces).count < 6 || joining)
            }
        } header: {
            Text("You check chores for")
        } footer: {
            Text("Enter a friend's code to become their partner. You can be a partner for several people, and they can be yours at the same time.")
        }

        Section {
            if let error = sync.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
            HStack {
                if sync.isRefreshing {
                    ProgressView()
                    Text("Syncing…").foregroundStyle(.secondary)
                } else if let synced = sync.lastSynced {
                    Text("Updated \(synced, format: .relative(presentation: .named))").foregroundStyle(.secondary)
                }
                Spacer()
                Button("Refresh") { Task { await sync.refresh() } }
                    .disabled(sync.isRefreshing)
            }
            .font(.subheadline)
        }
    }
}

// MARK: - One person you check

struct PartnerPersonView: View {
    @EnvironmentObject var store: GameStore
    @EnvironmentObject var sync: PartnerSync
    @Environment(\.dismiss) private var dismiss
    let person: OnlinePartner

    @State private var reviewing: ReviewRow?
    @State private var editor: EditorContext?
    @State private var giftAmount = 50
    @State private var giftMessage = ""
    @State private var giftSent = false
    @State private var sendingGift = false
    @State private var confirmLeave = false

    var body: some View {
        let reviews = sync.reviewsToDo(for: person)
        let assigned = sync.choresAssigned(to: person)
        List {
            Section {
                if reviews.isEmpty {
                    Text("Nothing to review right now.").foregroundStyle(.secondary)
                }
                ForEach(reviews) { review in
                    Button { reviewing = review } label: {
                        HStack(spacing: 12) {
                            Group {
                                if let path = review.photoPaths.last {
                                    RemotePhoto(path: path, contentMode: .fill)
                                } else {
                                    Text(review.choreEmoji).font(.title)
                                }
                            }
                            .frame(width: 52, height: 52)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(review.choreTitle).font(.headline)
                                Text(review.submittedAt, format: .relative(presentation: .named))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Label("\(review.points)", systemImage: "sparkle")
                                .font(.subheadline.bold()).foregroundStyle(Palette.sparks)
                        }
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("Waiting for your review (\(reviews.count))")
            }

            Section {
                Button {
                    editor = EditorContext(chore: Chore(title: "", assignedBy: .partner, requiresReview: true), isNew: true)
                } label: {
                    Label("Assign a chore", systemImage: "plus.circle.fill")
                }
                ForEach(assigned) { row in
                    HStack {
                        Text(row.chore.emoji)
                        Text(row.chore.title)
                        Spacer()
                        Text(row.chore.recurrence.label).font(.caption).foregroundStyle(.secondary)
                    }
                    .swipeActions {
                        Button(role: .destructive) { Task { await sync.unassign(row) } } label: { Label("Delete", systemImage: "trash") }
                        Button { editor = EditorContext(chore: row.chore, isNew: false) } label: { Label("Edit", systemImage: "pencil") }
                    }
                }
            } header: {
                Text("Chores you assigned")
            } footer: {
                Text("\(person.name) can't edit or delete these, and they always need a partner's approval. They earn a +15% verified bonus.")
            }

            Section {
                Stepper(value: $giftAmount, in: 10...1000, step: 10) {
                    Label("\(giftAmount) Sparks", systemImage: "sparkle")
                }
                TextField("Message (e.g. proud of you!)", text: $giftMessage)
                Button {
                    sendingGift = true
                    Task {
                        if await sync.sendGift(giftAmount, message: giftMessage, to: person) {
                            Haptics.success()
                            giftMessage = ""
                            giftSent = true
                        }
                        sendingGift = false
                    }
                } label: {
                    Label(giftSent ? "Sent! Send another" : "Send encouragement", systemImage: "gift.fill")
                }
                .disabled(sendingGift)
            } header: {
                Text("Send Sparks")
            } footer: {
                Text("Gifts arrive the next time \(person.name) opens Chore Capsule.")
            }

            if let error = sync.lastError {
                Section { Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
            }

            Section {
                Button("Stop being \(person.name)'s partner", role: .destructive) { confirmLeave = true }
            }
        }
        .navigationTitle(person.name)
        .refreshable { await sync.refresh() }
        .sheet(item: $reviewing) { RemoteReviewView(review: $0, person: person) }
        .sheet(item: $editor) { ctx in
            ChoreEditorView(chore: ctx.chore, isNew: ctx.isNew, assigneeName: person.name) { chore in
                await sync.assign(chore, to: person)
            }
        }
        .confirmationDialog("Stop being \(person.name)'s partner?", isPresented: $confirmLeave, titleVisibility: .visible) {
            Button("Stop", role: .destructive) {
                Task {
                    await sync.leave(person)
                    dismiss()
                }
            }
        } message: {
            Text("You won't see their proof any more. They can invite you again with their code.")
        }
    }
}

// MARK: - Reviewing someone's proof

struct RemoteReviewView: View {
    @EnvironmentObject var sync: PartnerSync
    @Environment(\.dismiss) private var dismiss
    let review: ReviewRow
    let person: OnlinePartner
    @State private var comment = ""
    @State private var goldStar = false
    @State private var sending = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text(review.choreEmoji).font(.largeTitle)
                        VStack(alignment: .leading) {
                            Text(review.choreTitle).font(.title2.bold())
                            Text("\(person.name) · \(review.submittedAt.formatted(.dateTime.weekday().hour().minute()))")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }

                    ForEach(Array(review.photoPaths.enumerated()), id: \.offset) { i, path in
                        VStack(alignment: .leading, spacing: 4) {
                            if review.photoPaths.count == 2 {
                                Text(i == 0 ? "Before" : "After").font(.caption.bold()).foregroundStyle(.secondary)
                            }
                            RemotePhoto(path: path)
                                .frame(maxWidth: .infinity, minHeight: 200)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                        }
                    }

                    if let aiNote = review.aiNote {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(review.aiVerified == true ? "AI check passed"
                                     : review.aiVerified == false ? "AI check flagged this photo"
                                     : "AI check didn't run").font(.subheadline.bold())
                                Text(aiNote).font(.subheadline).foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: review.aiVerified == true ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                                .foregroundStyle(review.aiVerified == true ? Palette.mint : .orange)
                        }
                        .card()
                    }

                    if !review.note.isEmpty {
                        Text("\u{201C}\(review.note)\u{201D}").italic().card()
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(review.breakdown.lines) { BreakdownRow(line: $0) }
                        Divider()
                        HStack {
                            Text("Total").bold()
                            Spacer()
                            Label("\(review.points)", systemImage: "sparkle").bold().foregroundStyle(Palette.sparks)
                        }
                    }
                    .card()

                    Toggle(isOn: $goldStar) {
                        Label("Award a gold star (+25%)", systemImage: "star.circle.fill")
                    }
                    .tint(Palette.gold)
                    .card()

                    TextField("Comment for \(person.name) (optional)", text: $comment, axis: .vertical)
                        .lineLimit(1...4)
                        .card()

                    if let error {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline).foregroundStyle(.orange)
                    }

                    HStack(spacing: 12) {
                        Button { decide(approve: false) } label: {
                            Label("Send back", systemImage: "arrow.uturn.backward")
                        }
                        .buttonStyle(BubblyButtonStyle(color: .gray))

                        Button { decide(approve: true) } label: {
                            Label("Approve", systemImage: "checkmark.seal.fill")
                        }
                        .buttonStyle(BubblyButtonStyle(color: Palette.mint.adjusted(brightness: -0.15)))
                    }
                    .disabled(sending)
                    .overlay { if sending { ProgressView() } }
                }
                .padding()
            }
            .background(AppBackground())
            .navigationTitle("Review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }

    private func decide(approve: Bool) {
        sending = true
        error = nil
        Task {
            let ok = await sync.decide(review, approve: approve, comment: comment, goldStar: goldStar)
            sending = false
            if ok {
                approve ? Haptics.success() : Haptics.warning()
                dismiss()
            } else {
                error = sync.lastError ?? "Couldn't send your decision. Try again."
            }
        }
    }
}

// MARK: - Photo from the partner server

struct RemotePhoto: View {
    @EnvironmentObject var sync: PartnerSync
    let path: String
    var contentMode: ContentMode = .fit
    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().aspectRatio(contentMode: contentMode)
            } else if failed {
                Image(systemName: "photo.badge.exclamationmark").font(.title2).foregroundStyle(.secondary)
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.tertiarySystemFill))
        .task(id: path) {
            image = await sync.photo(path)
            failed = image == nil
        }
    }
}
