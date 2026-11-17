import SwiftUI

struct PartnerView: View {
    @EnvironmentObject var store: GameStore
    @EnvironmentObject var sync: PartnerSync
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if sync.isConfigured {
                    PartnersHubView()
                } else {
                    SamePhonePartnerView()
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        store.lockPartner()
                        dismiss()
                    }
                }
            }
        }
        .onDisappear { store.lockPartner() }
    }
}

/// The original partner mode: the partner uses this phone and a PIN.
struct SamePhonePartnerView: View {
    @EnvironmentObject var store: GameStore

    var body: some View {
        Group {
            if store.partnerUnlocked {
                PartnerPanel()
            } else {
                PINGateView()
            }
        }
        .toolbar {
            if store.partnerUnlocked {
                ToolbarItem(placement: .primaryAction) {
                    Button("Lock") { store.lockPartner() }
                }
            }
        }
        .onDisappear { store.lockPartner() }
    }
}

private struct PINGateView: View {
    @EnvironmentObject var store: GameStore
    @State private var name = ""
    @State private var pin = ""
    @State private var confirm = ""
    @State private var error: String?

    private var isSetup: Bool { store.state.partnerPIN == nil }

    var body: some View {
        Form {
            Section {
                VStack(spacing: 10) {
                    Image(systemName: "person.2.badge.key.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(LinearGradient(colors: [Palette.pink, Palette.lavender], startPoint: .top, endPoint: .bottom))
                    Text(isSetup ? "Set up an accountability partner" : "Hand the phone to \(store.partnerDisplayName)")
                        .font(.title3.bold())
                        .multilineTextAlignment(.center)
                    Text(isSetup
                         ? "Your partner picks a secret PIN. With it they can assign chores you can't delete, approve or reject your proof, award gold stars, and send you Sparks."
                         : "Partner mode lets them review proofs, assign chores, and send encouragement.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }

            Section {
                if isSetup {
                    TextField("Partner's name", text: $name)
                }
                SecureField("4-digit PIN", text: $pin)
                    .keyboardType(.numberPad)
                if isSetup {
                    SecureField("Confirm PIN", text: $confirm)
                        .keyboardType(.numberPad)
                }
                if let error {
                    Text(error).foregroundStyle(.red).font(.subheadline)
                }
            } footer: {
                if isSetup { Text("Only your partner should know this PIN. Hand them the phone now!") }
            }

            Section {
                Button(isSetup ? "Save PIN & enter partner mode" : "Unlock") { submit() }
                    .frame(maxWidth: .infinity)
                    .font(.headline)
            }
        }
        .onAppear { name = store.state.partnerName }
    }

    private func submit() {
        let digits = pin.filter(\.isNumber)
        guard digits.count == 4, digits == pin else {
            error = "The PIN needs exactly 4 digits."
            return
        }
        if isSetup {
            guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { error = "Add your partner's name."; return }
            guard pin == confirm else { error = "PINs don't match."; return }
            store.state.partnerName = name.trimmingCharacters(in: .whitespaces)
            store.setPartnerPIN(pin)
            Haptics.success()
        } else if store.unlockPartner(pin: pin) {
            Haptics.success()
        } else {
            Haptics.warning()
            error = "Wrong PIN."
            pin = ""
        }
    }
}

private struct PartnerPanel: View {
    @EnvironmentObject var store: GameStore
    @State private var reviewing: Submission?
    @State private var editor: EditorContext?
    @State private var showTreat = false
    @State private var giftAmount = 50
    @State private var giftMessage = ""
    @State private var giftSent = false
    @State private var newPIN = ""

    private var partnerChores: [Chore] {
        store.state.chores.filter { $0.assignedBy == .partner && !$0.isArchived }
    }

    var body: some View {
        List {
            Section {
                HStack {
                    Image(systemName: "lock.open.fill").foregroundStyle(Palette.mint)
                    Text("Partner mode: \(store.partnerDisplayName)").font(.headline)
                }
            }

            Section {
                if store.pendingSubmissions.isEmpty {
                    Text("Nothing to review right now.").foregroundStyle(.secondary)
                }
                ForEach(store.pendingSubmissions) { sub in
                    Button { reviewing = sub } label: {
                        HStack(spacing: 12) {
                            if let file = sub.photoFiles.last, let img = PhotoStore.load(file) {
                                Image(uiImage: img).resizable().scaledToFill()
                                    .frame(width: 52, height: 52)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            } else {
                                Text(sub.choreEmoji).font(.title).frame(width: 52, height: 52)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(sub.choreTitle).font(.headline)
                                Text(sub.submittedAt, format: .relative(presentation: .named))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Label("\(sub.breakdown.total)", systemImage: "sparkle")
                                .font(.subheadline.bold()).foregroundStyle(Palette.sparks)
                        }
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("Waiting for review (\(store.pendingSubmissions.count))")
            }

            Section {
                Button {
                    editor = EditorContext(chore: Chore(title: "", assignedBy: .partner, requiresReview: true), isNew: true)
                } label: {
                    Label("Assign a new chore", systemImage: "plus.circle.fill")
                }
                ForEach(partnerChores) { chore in
                    HStack {
                        Text(chore.emoji)
                        Text(chore.title)
                        Spacer()
                        Text(chore.recurrence.label).font(.caption).foregroundStyle(.secondary)
                    }
                    .swipeActions {
                        Button(role: .destructive) { store.delete(chore) } label: { Label("Delete", systemImage: "trash") }
                        Button { editor = EditorContext(chore: chore, isNew: false) } label: { Label("Edit", systemImage: "pencil") }
                    }
                }
            } header: {
                Text("Chores you assigned")
            } footer: {
                Text("These are locked for your partner and always need your approval. They earn a +15% verified bonus.")
            }

            Section {
                Stepper(value: $giftAmount, in: 10...1000, step: 10) {
                    Label("\(giftAmount) Sparks", systemImage: "sparkle")
                }
                TextField("Message (e.g. proud of you!)", text: $giftMessage)
                Button {
                    store.gift(giftAmount, message: giftMessage)
                    Haptics.success()
                    giftMessage = ""
                    giftSent = true
                } label: {
                    Label(giftSent ? "Sent! Send another" : "Send encouragement", systemImage: "gift.fill")
                }
            } header: {
                Text("Send Sparks")
            }

            Section("Treats") {
                Button { showTreat = true } label: { Label("Add a real-life reward", systemImage: "heart.fill") }
            }

            Section {
                SecureField("New 4-digit PIN", text: $newPIN).keyboardType(.numberPad)
                Button("Change PIN") {
                    store.setPartnerPIN(newPIN)
                    newPIN = ""
                    Haptics.success()
                }
                .disabled(newPIN.count != 4 || !newPIN.allSatisfy(\.isNumber))
            } header: {
                Text("Security")
            }
        }
        .navigationTitle("Partner")
        .sheet(item: $reviewing) { ReviewDetailView(submission: $0) }
        .sheet(item: $editor) { ctx in ChoreEditorView(chore: ctx.chore, isNew: ctx.isNew) }
        .sheet(isPresented: $showTreat) { TreatEditorView(addedBy: .partner) }
    }
}

private struct ReviewDetailView: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.dismiss) private var dismiss
    let submission: Submission
    @State private var comment = ""
    @State private var goldStar = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text(submission.choreEmoji).font(.largeTitle)
                        VStack(alignment: .leading) {
                            Text(submission.choreTitle).font(.title2.bold())
                            Text(submission.submittedAt, format: .dateTime.weekday().hour().minute())
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }

                    ForEach(Array(submission.photoFiles.enumerated()), id: \.offset) { i, file in
                        if let img = PhotoStore.load(file) {
                            VStack(alignment: .leading, spacing: 4) {
                                if submission.photoFiles.count == 2 {
                                    Text(i == 0 ? "Before" : "After").font(.caption.bold()).foregroundStyle(.secondary)
                                }
                                Image(uiImage: img).resizable().scaledToFit()
                                    .clipShape(RoundedRectangle(cornerRadius: 16))
                            }
                        }
                    }

                    if let aiNote = submission.aiNote {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(submission.aiVerified == true ? "AI check passed"
                                     : submission.aiVerified == false ? "AI check flagged this photo"
                                     : "AI check didn't run").font(.subheadline.bold())
                                Text(aiNote).font(.subheadline).foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: submission.aiVerified == true ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                                .foregroundStyle(submission.aiVerified == true ? Palette.mint : .orange)
                        }
                        .card()
                    }

                    if !submission.note.isEmpty {
                        Text("“\(submission.note)”").italic().card()
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(submission.breakdown.lines) { BreakdownRow(line: $0) }
                        Divider()
                        HStack {
                            Text("Total").bold()
                            Spacer()
                            Label("\(submission.breakdown.total)", systemImage: "sparkle").bold().foregroundStyle(Palette.sparks)
                        }
                    }
                    .card()

                    Toggle(isOn: $goldStar) {
                        Label("Award a gold star (+25%)", systemImage: "star.circle.fill")
                    }
                    .tint(Palette.gold)
                    .card()

                    TextField("Comment for them (optional)", text: $comment, axis: .vertical)
                        .lineLimit(1...4)
                        .card()

                    HStack(spacing: 12) {
                        Button {
                            Haptics.warning()
                            store.reject(submission.id, comment: comment)
                            dismiss()
                        } label: {
                            Label("Send back", systemImage: "arrow.uturn.backward")
                        }
                        .buttonStyle(BubblyButtonStyle(color: .gray))

                        Button {
                            Haptics.success()
                            store.approve(submission.id, comment: comment, goldStar: goldStar)
                            dismiss()
                        } label: {
                            Label("Approve", systemImage: "checkmark.seal.fill")
                        }
                        .buttonStyle(BubblyButtonStyle(color: Palette.mint.adjusted(brightness: -0.15)))
                    }
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
}
