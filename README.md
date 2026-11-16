# Chore Capsule

A SwiftUI iOS app that turns chores into blind-box collecting. You finish a chore, prove it, earn **Sparks**, then spend them on capsules (gamble) or in the shop (sure thing).

## Run it
Open `ChoreCapsule.xcodeproj` in Xcode, pick an iPhone simulator or your phone, and press Run. The app needs iOS 18 or later. To install on your own phone, set your Team under Signing & Capabilities.

## Where things live
- `ChoreCapsule/Models/Catalog.swift`: the 4 series and 32 collectible figures. Each figure is drawn in code from a `FigureLook`, so you can add new ones without any art.
- `ChoreCapsule/Store/GameStore.swift`: all the game rules: point formula, streaks, quests, levels, gacha odds and pity, the shop, and partner review.
- `ChoreCapsule/Views/Capsules/UnboxingView.swift`: the pick, shake, and reveal ritual.
- Your data is saved as JSON (plus proof photos) in the app's Documents folder.

## Tuning
The economy's numbers are constants at the top of `GameStore` (pull costs, pity, crit chance) and on `Rarity` and `Difficulty`.
