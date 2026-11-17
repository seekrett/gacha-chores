import Foundation
import Security

struct SupabaseError: LocalizedError {
    let message: String
    let status: Int
    var errorDescription: String? { message }
}

/// A small Supabase client over URLSession: anonymous sign-in, database (PostgREST) and Storage.
/// Swift has no official Supabase SDK in this project, so it talks to the REST endpoints directly.
@MainActor
final class SupabaseClient {
    struct Session: Codable {
        var accessToken: String
        var refreshToken: String
        var expiresAt: Date
        var userID: UUID
    }

    static let bucket = "proofs"

    private var session: Session? = SessionKeychain.load()
    private var signingIn: Task<Session, Error>?

    private let base: URL
    private let key: String

    init() {
        // Use only the project address, even if a full API URL such as ".../rest/v1/" was pasted.
        var components = URLComponents(string: SupabaseConfig.url.trimmingCharacters(in: .whitespacesAndNewlines))
        components?.path = ""
        components?.query = nil
        base = components?.url ?? URL(string: "https://invalid.local")!
        key = SupabaseConfig.publishableKey
    }

    var currentUserID: UUID? { session?.userID }

    // MARK: Auth

    private struct AuthResponse: Decodable {
        let access_token: String
        let refresh_token: String
        let expires_in: Double
        let user: User
        struct User: Decodable { let id: UUID }
    }

    /// Returns a valid session, signing in anonymously the first time.
    func ensureSession() async throws -> Session {
        if let signingIn { return try await signingIn.value }
        if let session, session.expiresAt.timeIntervalSinceNow > 60 { return session }

        let task = Task { () throws -> Session in
            if let old = self.session {
                do {
                    return try await self.authCall(path: "auth/v1/token", query: [URLQueryItem(name: "grant_type", value: "refresh_token")],
                                                   body: ["refresh_token": old.refreshToken])
                } catch let error as SupabaseError where error.status == 400 || error.status == 401 || error.status == 403 {
                    // The refresh token is no longer valid (for example the project was reset): start a new account.
                }
            }
            return try await self.authCall(path: "auth/v1/signup", query: [], body: ["data": [String: String]()])
        }
        signingIn = task
        defer { signingIn = nil }
        let new = try await task.value
        session = new
        SessionKeychain.save(new)
        return new
    }

    private func authCall(path: String, query: [URLQueryItem], body: [String: Any]) async throws -> Session {
        var request = URLRequest(url: url(path, query))
        request.httpMethod = "POST"
        request.setValue(key, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let data = try await send(request)
        let auth = try JSONDecoder().decode(AuthResponse.self, from: data)
        return Session(accessToken: auth.access_token, refreshToken: auth.refresh_token,
                       expiresAt: Date().addingTimeInterval(auth.expires_in), userID: auth.user.id)
    }

    // MARK: Database

    func select<T: Decodable>(_ table: String, _ query: [URLQueryItem]) async throws -> [T] {
        let data = try await authorized("GET", "rest/v1/\(table)", query: query)
        return try Self.decoder.decode([T].self, from: data)
    }

    /// Inserts rows. `onConflict`: nil = fail on duplicates, "merge" = upsert, "ignore" = skip duplicates.
    func insert<T: Encodable>(_ table: String, _ value: T, onConflict: String? = nil) async throws {
        var prefer = "return=minimal"
        if onConflict == "merge" { prefer += ",resolution=merge-duplicates" }
        if onConflict == "ignore" { prefer += ",resolution=ignore-duplicates" }
        _ = try await authorized("POST", "rest/v1/\(table)", body: try Self.encoder.encode(value), headers: ["Prefer": prefer])
    }

    /// Upserts and returns the resulting rows.
    func upsertReturning<T: Encodable, R: Decodable>(_ table: String, _ value: T) async throws -> [R] {
        let data = try await authorized("POST", "rest/v1/\(table)", body: try Self.encoder.encode(value),
                                        headers: ["Prefer": "return=representation,resolution=merge-duplicates"])
        return try Self.decoder.decode([R].self, from: data)
    }

    func update<T: Encodable>(_ table: String, _ value: T, _ query: [URLQueryItem]) async throws {
        _ = try await authorized("PATCH", "rest/v1/\(table)", query: query, body: try Self.encoder.encode(value),
                                 headers: ["Prefer": "return=minimal"])
    }

    func delete(_ table: String, _ query: [URLQueryItem]) async throws {
        _ = try await authorized("DELETE", "rest/v1/\(table)", query: query, headers: ["Prefer": "return=minimal"])
    }

    func rpc<P: Encodable>(_ function: String, _ params: P) async throws -> Data {
        try await authorized("POST", "rest/v1/rpc/\(function)", body: try Self.encoder.encode(params))
    }

    // MARK: Storage

    func upload(_ data: Data, to path: String) async throws {
        _ = try await authorized("POST", "storage/v1/object/\(Self.bucket)/\(path)", body: data,
                                 headers: ["Content-Type": "image/jpeg", "x-upsert": "true"])
    }

    func download(_ path: String) async throws -> Data {
        try await authorized("GET", "storage/v1/object/authenticated/\(Self.bucket)/\(path)")
    }

    func removeObjects(_ paths: [String]) async throws {
        guard !paths.isEmpty else { return }
        let body = try JSONSerialization.data(withJSONObject: ["prefixes": paths])
        _ = try await authorized("DELETE", "storage/v1/object/\(Self.bucket)", body: body)
    }

    // MARK: Plumbing

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            if let seconds = try? container.decode(Double.self) {
                return Date(timeIntervalSinceReferenceDate: seconds)
            }
            let text = try container.decode(String.self)
            if let date = parseTimestamp(text) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unreadable date \(text)")
        }
        return d
    }()

    /// Parses Postgres timestamps such as "2026-11-16T10:00:00.123456+00:00".
    nonisolated static func parseTimestamp(_ text: String) -> Date? {
        var s = text.replacingOccurrences(of: " ", with: "T")
        if let dot = s.firstIndex(of: ".") {
            let fractionEnd = s[s.index(after: dot)...].firstIndex(where: { !$0.isNumber }) ?? s.endIndex
            s.removeSubrange(dot..<fractionEnd)
        }
        if s.hasSuffix("+00") { s += ":00" }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: s)
    }

    private func url(_ path: String, _ query: [URLQueryItem]) -> URL {
        var components = URLComponents(url: base.appending(path: path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        return components.url!
    }

    private func authorized(_ method: String, _ path: String, query: [URLQueryItem] = [], body: Data? = nil,
                            headers: [String: String] = [:]) async throws -> Data {
        let session = try await ensureSession()
        var request = URLRequest(url: url(path, query))
        request.httpMethod = method
        request.timeoutInterval = 30
        request.setValue(key, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        request.httpBody = body
        return try await send(request)
    }

    private func send(_ request: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let error as URLError {
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
                throw SupabaseError(message: "You're offline. Partner updates will sync when you're back online.", status: 0)
            case .timedOut:
                throw SupabaseError(message: "The partner server took too long to answer. Try again.", status: 0)
            case .cannotFindHost, .cannotConnectToHost:
                throw SupabaseError(message: "Can't reach the partner server. Check the Supabase URL, or the project may be paused.", status: 0)
            default:
                throw SupabaseError(message: error.localizedDescription, status: 0)
            }
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let message = (json?["message"] ?? json?["msg"] ?? json?["error_description"] ?? json?["error"]) as? String
            throw SupabaseError(message: Self.friendly(message, status: status), status: status)
        }
        return data
    }

    private static func friendly(_ message: String?, status: Int) -> String {
        if let message, message.localizedCaseInsensitiveContains("anonymous sign-ins are disabled") {
            return "Anonymous sign-ins are off in Supabase. Turn them on under Authentication → Sign In / Providers."
        }
        if let message, message.contains("does not exist") || message.contains("schema cache") {
            return "The partner database isn't set up yet. Run supabase/setup.sql in the Supabase SQL Editor."
        }
        if status == 401 && message == nil {
            return "The Supabase key was rejected. Check SupabaseConfig.swift."
        }
        return message ?? "The partner server returned an error (\(status))."
    }
}

/// Keeps the anonymous account's tokens in the Keychain so the same identity survives reinstalls.
enum SessionKeychain {
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "app.chorecapsule.supabase-session",
         kSecAttrAccount as String: "default"]
    }

    static func load() -> SupabaseClient.Session? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(SupabaseClient.Session.self, from: data)
    }

    static func save(_ session: SupabaseClient.Session) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        SecItemDelete(query as CFDictionary)
        var q = query
        q[kSecValueData as String] = data
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(q as CFDictionary, nil)
    }
}
