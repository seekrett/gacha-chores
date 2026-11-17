import SwiftUI

struct EditorContext: Identifiable {
    let id = UUID()
    var chore: Chore
    var isNew: Bool
}

struct ChoresView: View {
    @EnvironmentObject var store: GameStore
    @State private var completing: Chore?
    @State private var editor: EditorContext?
    @State private var lockedAlert: Chore?
    @State private var showPartner = false

    private var active: [Chore] { store.state.chores.filter { !$0.isArchived } }
    private var todo: [Chore] { active.filter { !$0.isDone() } }
    private var waiting: [Chore] { active.filter { $0.isDone() && store.pendingSubmission(for: $0) != nil } }
    private var done: [Chore] { active.filter { $0.isDone() && store.pendingSubmission(for: $0) == nil } }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if todo.isEmpty {
                        Text("Nothing left. You're a legend ✨").foregroundStyle(.secondary)
                    }
                    ForEach(todo) { chore in
                        Button { completing = chore } label: { ChoreRow(chore: chore) }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing) { actions(for: chore) }
                    }
                } header: {
                    Text("To do")
                } footer: {
                    Text("Tap a chore to submit your proof and earn Sparks.")
                }

                if !waiting.isEmpty {
                    Section("Waiting for \(store.partnerDisplayName)") {
                        ForEach(waiting) { chore in
                            ChoreRow(chore: chore)
                                .swipeActions(edge: .trailing) { actions(for: chore) }
                        }
                    }
                }

                if !done.isEmpty {
                    Section("Done") {
                        ForEach(done) { chore in
                            ChoreRow(chore: chore)
                                .swipeActions(edge: .trailing) { actions(for: chore) }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppBackground())
            .navigationTitle("Chores")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        editor = EditorContext(chore: Chore(title: ""), isNew: true)
                    } label: {
                        Image(systemName: "plus.circle.fill").font(.title3)
                    }
                }
            }
            .sheet(item: $completing) { CompleteChoreView(chore: $0) }
            .sheet(item: $editor) { ctx in ChoreEditorView(chore: ctx.chore, isNew: ctx.isNew) }
            .sheet(isPresented: $showPartner) { PartnerView() }
            .alert("Assigned by \(store.partnerDisplayName)", isPresented: Binding(
                get: { lockedAlert != nil }, set: { if !$0 { lockedAlert = nil } }
            )) {
                if lockedAlert?.remoteAssignerID == nil {
                    Button("Partner unlock") { showPartner = true }
                }
                Button("OK", role: .cancel) {}
            } message: {
                Text("Only \(lockedAlert?.remoteAssignerName ?? store.partnerDisplayName) can edit or remove this chore. That's the point of accountability 😉")
            }
        }
    }

    @ViewBuilder
    private func actions(for chore: Chore) -> some View {
        if store.canEdit(chore) {
            Button(role: .destructive) {
                withAnimation { store.delete(chore) }
            } label: { Label("Delete", systemImage: "trash") }
            Button {
                editor = EditorContext(chore: chore, isNew: false)
            } label: { Label("Edit", systemImage: "pencil") }
                .tint(Palette.lavender)
            if chore.recurrence == .once && chore.isDone() {
                Button { withAnimation { store.archive(chore) } } label: { Label("Archive", systemImage: "archivebox") }
                    .tint(.gray)
            }
        } else {
            Button { lockedAlert = chore } label: { Label("Locked", systemImage: "lock.fill") }
                .tint(.gray)
        }
    }
}

struct ChoreRow: View {
    @EnvironmentObject var store: GameStore
    let chore: Chore

    private var isDone: Bool { chore.isDone() }
    private var isPending: Bool { store.pendingSubmission(for: chore) != nil }

    var body: some View {
        HStack(spacing: 12) {
            Text(chore.emoji)
                .font(.system(size: 28))
                .frame(width: 48, height: 48)
                .background(Circle().fill(chore.difficulty.color.opacity(0.22)))
                .overlay(alignment: .bottomTrailing) {
                    if isDone {
                        Image(systemName: isPending ? "hourglass.circle.fill" : "checkmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(.white, isPending ? Palette.lavender : Palette.mint)
                    }
                }

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 4) {
                    Text(chore.title)
                        .font(.headline)
                        .strikethrough(isDone && !isPending)
                        .foregroundStyle(isDone ? .secondary : .primary)
                        .lineLimit(2)
                    if chore.assignedBy == .partner {
                        Image(systemName: "lock.fill").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 5) {
                        difficultyTag
                        proofTag
                        if chore.recurrence != .once {
                            Tag(text: chore.recurrence.label, icon: "arrow.trianglehead.2.clockwise")
                        }
                    }
                    HStack(spacing: 5) {
                        difficultyTag
                        proofTag
                    }
                    difficultyTag
                }
                if let deadline = chore.effectiveDeadline(), !isDone {
                    let overdue = chore.isOverdue()
                    let style: Date.FormatStyle = chore.recurrence == .once
                        ? Date.FormatStyle.dateTime.month().day().hour().minute()
                        : Date.FormatStyle.dateTime.hour().minute()
                    Label(overdue ? "Overdue: bonus missed" : "By \(deadline.formatted(style)) for +20%",
                          systemImage: "alarm.fill")
                        .font(.caption)
                        .foregroundStyle(overdue ? .red : .orange)
                }
                if let rejected = store.lastRejection(for: chore), !isDone {
                    Label("Sent back: \(rejected.partnerComment.isEmpty ? "try again" : rejected.partnerComment)", systemImage: "arrow.uturn.backward")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 4)
            if !isDone {
                VStack(spacing: 0) {
                    Text("+\(store.previewBreakdown(for: chore).total)")
                        .font(.headline.monospacedDigit())
                    Image(systemName: "sparkle").font(.caption)
                }
                .foregroundStyle(Palette.sparks)
                .fixedSize()
            }
        }
        .contentShape(Rectangle())
        .padding(.vertical, 2)
    }

    private var difficultyTag: some View {
        Tag(text: chore.difficulty.label, icon: chore.difficulty.icon, color: chore.difficulty.color.adjusted(brightness: -0.25))
    }

    private var proofTag: some View {
        Tag(text: chore.proof.label, icon: chore.proof.icon)
    }
}

struct ChoreEditorView: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.dismiss) private var dismiss
    @State private var chore: Chore
    @State private var hasDeadline: Bool
    @State private var saving = false
    let isNew: Bool
    /// When set (assigning to an online partner), Save calls this instead of saving locally.
    /// Return false to keep the editor open.
    var onSave: ((Chore) async -> Bool)? = nil
    var assigneeName: String? = nil

    init(chore: Chore, isNew: Bool, assigneeName: String? = nil, onSave: ((Chore) async -> Bool)? = nil) {
        _chore = State(initialValue: chore)
        _hasDeadline = State(initialValue: chore.deadline != nil)
        self.isNew = isNew
        self.assigneeName = assigneeName
        self.onSave = onSave
    }

    private var defaultDeadline: Date {
        Calendar.current.date(bySettingHour: 21, minute: 0, second: 0, of: .now) ?? .now
    }

    private var deadlineBinding: Binding<Date> {
        Binding(get: { chore.deadline ?? defaultDeadline }, set: { chore.deadline = $0 })
    }

    private static let emojiChoices = ["🧹", "🧺", "🍽️", "🛏️", "🛁", "🪴", "🗑️", "🧽", "👕", "🐶", "🛒", "📚", "💻", "🏃", "💧", "🧘"]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What needs doing?", text: $chore.title)
                        .font(.title3.bold())
                    TextField("Notes (optional)", text: $chore.notes, axis: .vertical)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(Self.emojiChoices, id: \.self) { e in
                                Text(e)
                                    .font(.title2)
                                    .frame(width: 42, height: 42)
                                    .background(Circle().fill(chore.emoji == e ? Palette.pink.opacity(0.35) : Color(.tertiarySystemFill)))
                                    .onTapGesture { chore.emoji = e }
                            }
                        }
                    }
                }

                Section {
                    Picker("Size", selection: $chore.difficulty) {
                        ForEach(Difficulty.allCases) { d in Text(d.label).tag(d) }
                    }
                    .pickerStyle(.segmented)
                    Text("\(chore.difficulty.label) is \(chore.difficulty.detail) · base \(chore.difficulty.basePoints) Sparks")
                        .font(.subheadline).foregroundStyle(.secondary)
                } header: {
                    Text("How big is it?")
                }

                Section {
                    ForEach(ProofType.allCases) { proof in
                        Button {
                            chore.proof = proof
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: proof.icon).frame(width: 26).foregroundStyle(Palette.berry)
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        Text(proof.label).font(.body.weight(.semibold))
                                        Tag(text: proof.bonusText, color: proof.multiplier >= 1 ? Palette.mint.adjusted(brightness: -0.3) : .orange)
                                    }
                                    Text(proof.explanation).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if chore.proof == proof {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.berry)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("Proof required")
                }

                Section {
                    Picker("Repeats", selection: $chore.recurrence) {
                        ForEach(Recurrence.allCases) { r in Text(r.label).tag(r) }
                    }
                    .pickerStyle(.segmented)
                    if chore.recurrence != .weekly {
                        Toggle("Deadline", isOn: $hasDeadline.animation())
                        if hasDeadline {
                            DatePicker(chore.recurrence == .once ? "Due" : "Every day by",
                                       selection: deadlineBinding,
                                       displayedComponents: chore.recurrence == .once ? [.date, .hourAndMinute] : [.hourAndMinute])
                        }
                    }
                } header: {
                    Text("Schedule")
                } footer: {
                    Text(chore.recurrence == .weekly ? "Weekly chores reset every week." : "Finish before the deadline for a +20% bonus.")
                }

                if store.hasPartner && onSave == nil {
                    Section {
                        Toggle("Always ask \(store.partnerDisplayName) to verify", isOn: $chore.requiresReview)
                            .disabled(chore.assignedBy == .partner)
                    } footer: {
                        Text(chore.proof == .photo || chore.proof == .beforeAfter
                             ? "When off, a photo the AI approves pays straight away. When on, \(store.partnerDisplayName) checks it too and you get +15%."
                             : "\(chore.proof.label) chores are always checked by \(store.partnerDisplayName). Verified chores earn +15%.")
                    }
                }

                Section {
                    HStack {
                        Text("Estimated reward")
                        Spacer()
                        Label("\(store.previewBreakdown(for: preparedChore).total)", systemImage: "sparkle")
                            .font(.headline)
                            .foregroundStyle(Palette.sparks)
                    }
                }
            }
            .navigationTitle(assigneeName.map { isNew ? "Assign to \($0)" : "Edit \($0)'s chore" }
                             ?? (isNew ? (chore.assignedBy == .partner ? "Assign a chore" : "New chore") : "Edit chore"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(onSave == nil ? "Save" : (isNew ? "Send" : "Update")) {
                        if let onSave {
                            saving = true
                            Task {
                                let ok = await onSave(preparedChore)
                                saving = false
                                if ok { dismiss() }
                            }
                        } else {
                            store.upsert(preparedChore)
                            dismiss()
                        }
                    }
                    .disabled(chore.title.trimmingCharacters(in: .whitespaces).isEmpty || saving)
                }
            }
        }
    }

    private var preparedChore: Chore {
        var c = chore
        c.title = c.title.trimmingCharacters(in: .whitespaces)
        if !hasDeadline || c.recurrence == .weekly {
            c.deadline = nil
        } else if c.deadline == nil {
            c.deadline = defaultDeadline
        }
        if c.assignedBy == .partner { c.requiresReview = true }
        if !store.hasPartner { c.requiresReview = false }
        return c
    }
}
