import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: GameStore
    @Environment(\.dismiss) private var dismiss
    @State private var confirmReset = false
    @State private var showHow = false
    @State private var showPartner = false

    private var partnerLocked: Bool { store.hasPartner && !store.partnerUnlocked }

    var body: some View {
        NavigationStack {
            Form {
                Section("You") {
                    TextField("Your name", text: $store.state.userName)
                }

                Section {
                    if store.hasPartner {
                        LabeledContent("Partners", value: store.partnerDisplayName.capitalizedFirst)
                    }
                    Button(store.hasPartner ? "Manage partners" : "Set up an accountability partner") { showPartner = true }
                } header: {
                    Text("Accountability")
                } footer: {
                    Text("Partners assign chores, verify your proof, and send you Sparks, from their own phone with an invite code, or on this phone with a PIN.")
                }

                Section {
                    Toggle("AI photo check", isOn: Binding(
                        get: { store.aiPhotoCheckOn },
                        set: { store.state.aiPhotoCheckOff = !$0 }
                    ))
                    .disabled(partnerLocked)
                    LabeledContent("On this iPhone", value: PhotoVerifier.status.available ? "Ready" : "Not available")
                } header: {
                    Text("Proof")
                } footer: {
                    let status = PhotoVerifier.status
                    Text(status.message
                         + (status.available
                            ? " Photos that don't match the chore earn nothing."
                            : " Until then, photos go to your partner. Without a partner, chores can't earn Sparks.")
                         + (partnerLocked ? " Only \(store.partnerDisplayName) can turn this off." : ""))
                }

                Section("Stats") {
                    LabeledContent("Lifetime Sparks", value: "\(store.state.lifetimeSparks)")
                    LabeledContent("Best streak", value: "\(store.state.bestStreak) days")
                    LabeledContent("Chores completed", value: "\(store.state.submissions.filter { $0.status == .approved }.count)")
                    LabeledContent("Capsules opened", value: "\(store.state.totalPulls)")
                    LabeledContent("Treats redeemed", value: "\(store.state.redemptions.count)")
                }

                Section {
                    Button("How Sparks work") { showHow = true }
                }

                Section {
                    Button("Reset all progress", role: .destructive) { confirmReset = true }
                } footer: {
                    Text("Erases chores, proof photos, Sparks, and your whole collection.")
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .sheet(isPresented: $showHow) { HowItWorksView() }
            .sheet(isPresented: $showPartner) { PartnerView() }
            .confirmationDialog("Reset everything?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Erase all progress", role: .destructive) { store.resetEverything() }
            } message: {
                Text("This can't be undone.")
            }
        }
    }
}

struct HowItWorksView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Earning Sparks ✦") {
                    row("leaf.fill", "Chore size", "Quick 15 · Standard 30 · Big 60 · Epic 120")
                    row("photo.on.rectangle.angled", "Better proof pays more", "Before & after +30% · Photo 100% · Note −20% · Honor system −50%")
                    row("camera.aperture", "Fresh photo", "Snap it with the camera, not the library: +10%")
                    row("lock.shield.fill", "Verified or nothing", "Every chore needs a check before it pays: the AI for photos, or your accountability partner for anything. With neither, chores can't earn Sparks")
                    row("checkmark.shield.fill", "AI photo check", "On iPhones with Apple Intelligence (iOS 27), your photo is checked on-device to make sure it shows the chore. Photos that don't match earn nothing. On other iPhones, the photo goes to your partner")
                    row("alarm.fill", "Beat the deadline", "+20% when you finish before it's due")
                    row("flame.fill", "Streaks", "+5% for every day in a row, up to +50%")
                    row("sunrise.fill", "First chore of the day", "+10 just for getting started")
                    row("checkmark.seal.fill", "Verified", "+15% when your partner approves it, plus a possible gold star for +25%")
                    row("sparkles", "Critical clean", "12% chance any chore pays double")
                }
                Section("Bonus rewards") {
                    row("checklist", "Daily quests", "3 quests a day. Clear all 3 for a free capsule ticket")
                    row("star.fill", "Levels", "Every level-up gives you a capsule ticket")
                    row("trophy.fill", "Complete a series", "500 Sparks + 2 tickets")
                }
                Section("Spending") {
                    row("shippingbox.fill", "Capsules", "100 per box, or 900 for a case of 10 with a Rare or better guaranteed. Epic guaranteed every 40, Secret every 120")
                    row("bag.fill", "Shop", "Buy the exact figure you want from today's shelf, boosters, display shelves, or your own real-life treats")
                    row("diamond.fill", "Glitter", "Duplicates become Glitter. Polish figures to shiny, or trade 60 for a ticket")
                }
                Section {
                    Text("The best rewards come from the habits that actually help you: doing things on time, every day, with real proof. Gambling is optional. Productivity is not 😌")
                        .font(.subheadline)
                }
            }
            .navigationTitle("How it works")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Got it") { dismiss() } }
            }
        }
    }

    private func row(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).foregroundStyle(Palette.berry).frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.bold())
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
