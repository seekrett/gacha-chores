import SwiftUI

@main
struct ChoreCapsuleApp: App {
    @StateObject private var store = GameStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(store.sync)
                .fontDesign(.rounded)
                .tint(Palette.berry)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                store.lockPartner()
                store.saveNow()
            case .active:
                store.refreshStreak()
                Task { await store.sync.refresh() }
            default:
                break
            }
        }
    }
}

struct RootView: View {
    @EnvironmentObject var store: GameStore
    @EnvironmentObject var sync: PartnerSync

    private var todoCount: Int {
        store.state.chores.filter { !$0.isArchived && !$0.isDone() }.count
    }

    var body: some View {
        TabView(selection: $store.selectedTab) {
            Tab("Today", systemImage: "sun.max.fill", value: AppTab.today) {
                TodayView()
            }
            Tab("Chores", systemImage: "checklist", value: AppTab.chores) {
                ChoresView()
            }
            .badge(todoCount)
            Tab("Capsules", systemImage: "shippingbox.fill", value: AppTab.capsules) {
                CapsuleView()
            }
            .badge(store.affordablePulls > 0 ? Text("\(store.affordablePulls)") : nil)
            Tab("Partner", systemImage: "person.2.fill", value: AppTab.partner) {
                PartnerDashboardView()
            }
            .badge(sync.reviewsToDo.count)
            Tab("Collection", systemImage: "square.grid.2x2.fill", value: AppTab.collection) {
                CollectionView()
            }
        }
        .task {
            // No push notifications on a free developer account, so check for partner updates while the app is open.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(45))
                await store.sync.refresh()
            }
        }
        .alert("Level up! 🎉", isPresented: Binding(
            get: { store.pendingLevelUp != nil },
            set: { if !$0 { store.pendingLevelUp = nil } }
        )) {
            Button("Yay!") { store.pendingLevelUp = nil }
        } message: {
            Text("You reached level \(store.pendingLevelUp ?? store.state.level). Here's a free capsule ticket 🎟️")
        }
        .alert("Heads up", isPresented: Binding(
            get: { store.notice != nil },
            set: { if !$0 { store.notice = nil } }
        )) {
            Button("OK") { store.notice = nil }
        } message: {
            Text(store.notice ?? "")
        }
    }
}
