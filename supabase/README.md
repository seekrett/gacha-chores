# Setting up online partners

Online partners let a friend assign chores and approve proof from their own iPhone.
Both phones talk to one free Supabase project that you create once.

## 1. Create the Supabase project (about 5 minutes)

1. Sign up at [supabase.com](https://supabase.com) (free, no card needed) and create a new project.
   Pick any name and a region near you. Save the database password somewhere, though the app doesn't need it.
2. When the project is ready, open **SQL Editor → New query**, paste the whole of
   [`setup.sql`](setup.sql), and press **Run**. It should finish with "Success. No rows returned".
3. Open **Authentication → Sign In / Providers** and turn on **Allow anonymous sign-ins**, then save.
   (Each phone gets an anonymous account, so nobody needs an email or password.)
4. Open **Project Settings → API Keys** and copy the **Publishable key** (`sb_publishable_…`).
   Then open **Project Settings → Data API** (or the project's Connect dialog) and copy the **Project URL**
   (`https://xxxx.supabase.co`).

## 2. Put the two values in the app

Open `ChoreCapsule/Sync/SupabaseConfig.swift` and fill in:

```swift
static let url = "https://xxxx.supabase.co"
static let publishableKey = "sb_publishable_..."
```

The publishable key is designed to live inside apps. What protects the data are the database rules
in `setup.sql`: proof is visible only to that person's current partners, only a partner can approve it
(once), and nobody can approve their own proof.

## 3. Install on both phones

Build and run on each iPhone from Xcode (plug the phone into the Mac and pick it as the run destination).

With a free Apple developer account:
- Each phone has to be plugged into this Mac once to install, and the app stops opening after 7 days
  until you run it from Xcode again. Your progress is kept when you reinstall.
- A free account can install on up to 3 devices.

## 4. Link up

1. On your phone: tap the **people icon** on the Today screen, enter your name, tap **Turn on online partners**.
   You'll get a 6-letter invite code. Tap the share button to send it.
2. On your friend's phone: do the same, then type your code under **You check chores for** and tap **Join**.
3. Want to check each other? Do the reverse with their code. You can have several partners, and be a
   partner for several people.

## How it behaves

- When you submit proof for a chore that needs verifying, it's uploaded and your Sparks wait.
  Any one of your partners can approve or send it back from their phone.
- There are no push notifications on a free account: phones check for updates when the app opens
  and every 45 seconds while it's open. Pull down on the Partners screen to check right away.
  The partner icon on Today shows a red count when someone's proof is waiting for you.
- If you're offline, proof is kept on your phone and uploaded at the next sync.
- Photos are deleted from the server once the partner decides.
- Free Supabase projects pause after a week with no activity. If the app says it can't reach the
  partner server, open the project at supabase.com and press **Restore**.
