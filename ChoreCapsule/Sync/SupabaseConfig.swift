import Foundation

/// Fill these in from your Supabase project (Project Settings → API Keys / Data API).
/// Both phones must use the same project. The publishable key is meant to ship inside apps:
/// the database's row-level security rules (supabase/setup.sql) are what protect the data.
enum SupabaseConfig {
    /// Project URL, for example "https://abcdefghijklmnop.supabase.co".
    static let url = "https://hdmlzwlpudkjgoupjptd.supabase.co"
    /// Publishable key ("sb_publishable_…") or the legacy "anon" key.
    static let publishableKey = "sb_publishable_2Wei2EaK3SaW92vGafnAdA_hk7M8Diw"

    static var isConfigured: Bool {
        !publishableKey.isEmpty && URL(string: url)?.host != nil
    }
}
