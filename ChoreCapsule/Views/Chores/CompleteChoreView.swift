import SwiftUI
import PhotosUI

struct ProofPhoto {
    var image: UIImage
    var fromCamera: Bool
}

struct CompleteChoreView: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.dismiss) private var dismiss
    let chore: Chore

    @State private var photo1: ProofPhoto?
    @State private var photo2: ProofPhoto?
    @State private var note = ""
    @State private var honor = false
    @State private var result: Submission?
    @State private var phase: CheckPhase = .idle
    @State private var aiStatus = PhotoVerifier.status

    private enum CheckPhase: Equatable {
        case idle
        case checking
        case rejected(observed: String, reason: String)
        case failed(String)
    }

    private var photos: [ProofPhoto] { [photo1, photo2].compactMap { $0 } }
    private var liveCamera: Bool { !photos.isEmpty && photos.allSatisfy(\.fromCamera) }
    private var isPhotoProof: Bool { chore.proof == .photo || chore.proof == .beforeAfter }
    private var route: VerificationRoute { store.verificationRoute(for: chore) }
    /// The AI looks at the photo first: it decides on the AI route, and filters junk before a partner sees it.
    private var runsAICheck: Bool { isPhotoProof && store.aiPhotoCheckReady }
    private var isBlocked: Bool { if case .blocked = route { true } else { false } }

    private var isValid: Bool {
        switch chore.proof {
        case .photo: photo1 != nil
        case .beforeAfter: photo1 != nil && photo2 != nil
        case .note: note.trimmingCharacters(in: .whitespacesAndNewlines).count >= 15
        case .honor: honor
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let result {
                    SubmissionResultView(submission: result) { dismiss() }
                } else {
                    form
                }
            }
            .background(AppBackground())
            .toolbar {
                if result == nil {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                }
            }
        }
        .interactiveDismissDisabled(result != nil || phase == .checking)
        .onChange(of: photo1?.image) { _, _ in phase = .idle }
        .onChange(of: photo2?.image) { _, _ in phase = .idle }
    }

    // MARK: Submitting

    private func submitTapped() {
        Haptics.impact(.medium)
        guard !isBlocked else { return }
        guard runsAICheck else {
            finish(.none)
            return
        }
        withAnimation { phase = .checking }
        let images = photos.map(\.image)
        Task {
            let verdict = await PhotoVerifier.verify(chore: chore, images: images)
            switch verdict {
            case .approved(let observed):
                finish(.verified(observed))
            case .rejected(let observed, let reason):
                Haptics.warning()
                withAnimation(.spring) { phase = .rejected(observed: observed, reason: reason) }
            case .unavailable(let reason):
                if store.hasPartner {
                    finish(.unverified(reason))
                } else {
                    Haptics.warning()
                    withAnimation(.spring) { phase = .failed(reason) }
                }
            case .failed(let reason):
                Haptics.warning()
                withAnimation(.spring) { phase = .failed(reason) }
            }
        }
    }

    private func finish(_ check: PhotoCheck) {
        withAnimation(.spring) {
            phase = .idle
            result = store.submit(chore: chore, photos: photos.map(\.image), note: note, liveCamera: liveCamera, check: check)
        }
    }

    private func retake() {
        withAnimation {
            photo1 = nil
            photo2 = nil
            phase = .idle
        }
    }

    // MARK: Check UI

    /// Says up front who verifies this chore.
    @ViewBuilder
    private var verifierRow: some View {
        switch route {
        case .ai:
            Label {
                Text("Checked by AI on this iPhone. Sparks are paid only if the photo clearly shows the finished chore.")
            } icon: {
                Image(systemName: "checkmark.shield.fill").foregroundStyle(Palette.mint.adjusted(brightness: -0.25))
            }
            .font(.subheadline)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
        case .partner:
            Label {
                Text("\(store.partnerDisplayName.capitalizedFirst) verifies this. Sparks land when they approve."
                     + (runsAICheck ? " The AI checks your photo first." : ""))
            } icon: {
                Image(systemName: "person.fill.checkmark").foregroundStyle(Palette.lavender.adjusted(brightness: -0.2))
            }
            .font(.subheadline)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
        case .blocked(let reason):
            VStack(alignment: .leading, spacing: 10) {
                Label("Nobody can verify this yet", systemImage: "lock.fill").font(.headline)
                Text(reason).font(.subheadline).foregroundStyle(.secondary)
                Button {
                    dismiss()
                    store.selectedTab = .partner
                } label: {
                    Label("Set up a partner", systemImage: "person.2.fill")
                }
                .buttonStyle(BubblyButtonStyle())
            }
            .card()
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(.orange.opacity(0.5), lineWidth: 1.5))
        }
    }

    private var checkingCard: some View {
        HStack(spacing: 14) {
            ProgressView().controlSize(.large)
            VStack(alignment: .leading, spacing: 2) {
                Text("Checking your photo…").font(.headline)
                Text("Making sure it really shows \u{201C}\(chore.title)\u{201D}. This stays on your phone.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .card()
    }

    private func rejectedCard(observed: String, reason: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "eye.trianglebadge.exclamationmark.fill")
                    .font(.title2)
                    .foregroundStyle(.orange)
                Text("That doesn't look like \u{201C}\(chore.title)\u{201D}")
                    .font(.headline)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("I see: \(observed)").font(.subheadline)
                Text(reason).font(.subheadline).foregroundStyle(.secondary)
            }
            Text("No Sparks for this one. Take a photo that clearly shows the finished chore.")
                .font(.caption).foregroundStyle(.secondary)
            Button {
                retake()
            } label: {
                Label("Retake photo", systemImage: "camera.fill")
            }
            .buttonStyle(BubblyButtonStyle())
            if store.hasPartner {
                Button {
                    finish(.partnerAppeal("AI flagged it: \(observed) \(reason)"))
                } label: {
                    Label("AI got it wrong? Ask \(store.partnerDisplayName)", systemImage: "person.fill.questionmark")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .card()
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(.orange.opacity(0.5), lineWidth: 1.5))
    }

    private func failedCard(_ reason: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "wifi.exclamationmark")
                    .font(.title2)
                    .foregroundStyle(.orange)
                Text("Couldn't check your photo").font(.headline)
            }
            Text(reason).font(.subheadline).foregroundStyle(.secondary)
            Button {
                submitTapped()
            } label: {
                Label("Try again", systemImage: "arrow.clockwise")
            }
            .buttonStyle(BubblyButtonStyle())
            if store.hasPartner {
                Button {
                    finish(.partnerAppeal("The AI check couldn't run: \(reason)"))
                } label: {
                    Label("Send to \(store.partnerDisplayName) instead", systemImage: "person.fill.questionmark")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .card()
    }

    private var form: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(spacing: 8) {
                    Text(chore.emoji).font(.system(size: 64))
                    Text(chore.title).font(.title2.bold()).multilineTextAlignment(.center)
                    if !chore.notes.isEmpty {
                        Text(chore.notes).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    HStack {
                        Tag(text: chore.difficulty.label, icon: chore.difficulty.icon, color: chore.difficulty.color.adjusted(brightness: -0.25))
                        if chore.assignedBy == .partner {
                            Tag(text: "From \(chore.remoteAssignerName ?? store.partnerDisplayName)", icon: "person.fill", color: Palette.lavender.adjusted(brightness: -0.2))
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .card()

                VStack(alignment: .leading, spacing: 14) {
                    Label("Your proof", systemImage: chore.proof.icon).font(.headline)
                    Text(chore.proof.explanation).font(.subheadline).foregroundStyle(.secondary)
                    switch chore.proof {
                    case .photo:
                        ProofSlot(title: "Finished!", photo: $photo1)
                    case .beforeAfter:
                        ProofSlot(title: "Before", photo: $photo1)
                        ProofSlot(title: "After", photo: $photo2)
                    case .note:
                        TextField("What did you do? Be specific!", text: $note, axis: .vertical)
                            .lineLimit(3...8)
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 14).fill(Color(.tertiarySystemFill)))
                        Text("\(note.count)/15 characters minimum").font(.caption).foregroundStyle(.secondary)
                    case .honor:
                        Toggle(isOn: $honor) {
                            Text("I solemnly swear I actually did this 🤞").font(.subheadline.weight(.semibold))
                        }
                        .tint(Palette.berry)
                    }
                    if isPhotoProof {
                        Label("Use the camera for a fresh photo to get a bonus", systemImage: "camera.aperture")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if chore.proof != .note {
                        TextField("Add a note (optional)", text: $note, axis: .vertical)
                            .lineLimit(1...4)
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 14).fill(Color(.tertiarySystemFill)))
                    }
                }
                .card()

                verifierRow

                let preview = store.previewBreakdown(for: chore, liveCamera: liveCamera)
                VStack(alignment: .leading, spacing: 8) {
                    Text("You'll earn").font(.headline)
                    ForEach(preview.lines) { line in
                        BreakdownRow(line: line)
                    }
                    Divider()
                    HStack {
                        Text("Total").bold()
                        Spacer()
                        Label("\(preview.total)", systemImage: "sparkle").font(.title3.bold()).foregroundStyle(Palette.sparks)
                    }
                    Text("…plus a \(Int(GameStore.critChance * 100))% chance of a CRITICAL CLEAN that doubles it ✨")
                        .font(.caption).foregroundStyle(.secondary)
                    if route == .partner {
                        Text("Sparks unlock once \(store.partnerDisplayName) approves.")
                            .font(.caption).foregroundStyle(Palette.lavender.adjusted(brightness: -0.2))
                    }
                }
                .card()

                switch phase {
                case .checking:
                    checkingCard
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                case .rejected(let observed, let reason):
                    rejectedCard(observed: observed, reason: reason)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                case .failed(let reason):
                    failedCard(reason)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                case .idle:
                    Button {
                        submitTapped()
                    } label: {
                        Label(route == .partner ? "Send for review" : "Submit & collect", systemImage: "sparkles")
                    }
                    .buttonStyle(BubblyButtonStyle())
                    .disabled(!isValid || isBlocked)
                }
            }
            .padding()
            .animation(.spring, value: phase)
        }
        .onAppear { aiStatus = PhotoVerifier.status }
    }
}

struct BreakdownRow: View {
    let line: PointLine
    var body: some View {
        HStack {
            Image(systemName: line.icon).frame(width: 22).foregroundStyle(Palette.berry)
            Text(line.label).font(.subheadline)
            Spacer()
            Text(line.amount >= 0 ? "+\(line.amount)" : "\(line.amount)")
                .font(.subheadline.bold().monospacedDigit())
                .foregroundStyle(line.amount >= 0 ? Color.primary : Color.orange)
        }
    }
}

struct ProofSlot: View {
    let title: String
    @Binding var photo: ProofPhoto?
    @State private var pickerItem: PhotosPickerItem?
    @State private var showCamera = false

    private var cameraAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.subheadline.bold())
                if photo?.fromCamera == true {
                    Tag(text: "Fresh", icon: "camera.aperture", color: Palette.mint.adjusted(brightness: -0.3))
                }
            }
            Color(.tertiarySystemFill)
                .frame(height: 190)
                .overlay {
                    if let photo {
                        Image(uiImage: photo.image).resizable().scaledToFill()
                    } else {
                        VStack(spacing: 6) {
                            Image(systemName: "camera.viewfinder").font(.system(size: 36))
                            Text("Add a photo").font(.subheadline)
                        }
                        .foregroundStyle(.secondary)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            HStack {
                if cameraAvailable {
                    Button { showCamera = true } label: { Label("Camera", systemImage: "camera.fill") }
                        .buttonStyle(.borderedProminent)
                }
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Label("Library", systemImage: "photo.on.rectangle")
                }
                .buttonStyle(.bordered)
                Spacer()
                if photo != nil {
                    Button(role: .destructive) { photo = nil } label: { Image(systemName: "trash") }
                        .buttonStyle(.bordered)
                }
            }
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    photo = ProofPhoto(image: image, fromCamera: false)
                }
                pickerItem = nil
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { image in
                photo = ProofPhoto(image: image, fromCamera: true)
            }
            .ignoresSafeArea()
        }
    }
}

struct CameraPicker: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    var onImage: (UIImage) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onImage(image) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

struct SubmissionResultView: View {
    @EnvironmentObject var store: GameStore
    let submission: Submission
    var onDone: () -> Void

    @State private var visible = 0
    @State private var shown = 0
    @State private var critFlash = false
    @State private var levelUp: Int?

    private var lines: [PointLine] { submission.breakdown.lines }
    private var isPending: Bool { submission.status == .pending }

    var body: some View {
        ZStack {
            ScrollView {
                VStack(spacing: 18) {
                    Text(isPending ? "Sent for review!" : "Chore complete!")
                        .font(.largeTitle.bold())
                        .padding(.top, 20)
                    Text(submission.choreEmoji).font(.system(size: 72))

                    HStack(spacing: 6) {
                        Image(systemName: isPending ? "hourglass" : "sparkle")
                        Text("+\(shown)")
                            .contentTransition(.numericText(value: Double(shown)))
                    }
                    .font(.system(size: 56, weight: .black, design: .rounded))
                    .foregroundStyle(LinearGradient(colors: [Palette.sparks, Palette.berry], startPoint: .leading, endPoint: .trailing))

                    if critFlash {
                        Text("CRITICAL CLEAN!")
                            .font(.title.weight(.black))
                            .foregroundStyle(LinearGradient(colors: Palette.rainbow, startPoint: .leading, endPoint: .trailing))
                            .transition(.scale(scale: 2.5).combined(with: .opacity))
                    }

                    VStack(spacing: 8) {
                        ForEach(lines.prefix(visible)) { line in
                            BreakdownRow(line: line)
                                .transition(.move(edge: .leading).combined(with: .opacity))
                        }
                    }
                    .card()

                    if submission.aiVerified == true {
                        Label("Photo verified by AI: \(submission.aiNote ?? "looks good")", systemImage: "checkmark.seal.fill")
                            .font(.subheadline)
                            .foregroundStyle(Palette.mint.adjusted(brightness: -0.3))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else if submission.aiVerified == nil, let note = submission.aiNote {
                        Label("Not checked: \(note)", systemImage: "exclamationmark.shield")
                            .font(.subheadline)
                            .foregroundStyle(.orange)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if let levelUp {
                        HStack {
                            Text("🎉").font(.largeTitle)
                            VStack(alignment: .leading) {
                                Text("Level \(levelUp)!").font(.headline)
                                Text("You got a free capsule ticket.").font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                        .card()
                    }

                    if isPending && store.hasOnlinePartner {
                        Label("Sent to \(store.partnerDisplayName)'s phone. The Sparks land as soon as one of them approves.",
                              systemImage: "paperplane.fill")
                            .font(.subheadline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .card()
                    } else if isPending && store.hasPartner {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("\(store.partnerDisplayName.capitalizedFirst) needs to approve before the Sparks land. Hand them your phone (Partner tab), or send the proof:")
                                .font(.subheadline)
                            shareButton
                        }
                        .card()
                    } else if isPending {
                        Label("Your Sparks are held until you add a partner to verify this.", systemImage: "hourglass")
                            .font(.subheadline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .card()
                    } else if store.affordablePulls > 0 {
                        Button {
                            onDone()
                            store.selectedTab = .capsules
                        } label: {
                            Label("Open a capsule", systemImage: "shippingbox.fill")
                        }
                        .buttonStyle(BubblyButtonStyle(color: Palette.glitter))
                    }

                    Button("Done", action: onDone)
                        .buttonStyle(BubblyButtonStyle())
                }
                .padding()
            }
            if critFlash { ConfettiView() }
        }
        .task { await animate() }
    }

    @ViewBuilder
    private var shareButton: some View {
        let message = "I finished \"\(submission.choreTitle)\" \(submission.choreEmoji) Can you approve it in Chore Capsule?"
        if let file = submission.photoFiles.last {
            ShareLink(item: PhotoStore.url(file), message: Text(message)) {
                Label("Send proof to \(store.partnerDisplayName)", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.bordered)
        } else {
            ShareLink(item: message) {
                Label("Message \(store.partnerDisplayName)", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.bordered)
        }
    }

    private func animate() async {
        if let lvl = store.pendingLevelUp {
            levelUp = lvl
            store.pendingLevelUp = nil
        }
        for i in lines.indices {
            try? await Task.sleep(for: .milliseconds(i == 0 ? 250 : 380))
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                visible = i + 1
                shown = max(0, lines.prefix(i + 1).reduce(0) { $0 + $1.amount })
            }
            Haptics.impact(.light)
        }
        if submission.breakdown.isCrit {
            try? await Task.sleep(for: .milliseconds(200))
            withAnimation(.spring(response: 0.5, dampingFraction: 0.5)) { critFlash = true }
            Haptics.success()
        } else if !isPending {
            Haptics.success()
        }
    }
}
