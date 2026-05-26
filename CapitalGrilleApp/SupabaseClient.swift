import Foundation

// Lightweight Supabase REST client. Uses the service-role key from Secrets.swift.
// Single-user personal project — no RLS, no per-user auth.
struct SupabaseClient {
    static let shared = SupabaseClient()

    private let baseURL = URL(string: "https://felyggqjjhltwokdfhop.supabase.co/rest/v1/")!

    enum SBError: Error, LocalizedError {
        case http(Int, String)
        var errorDescription: String? {
            switch self {
            case .http(let code, let body): return "Supabase HTTP \(code): \(body)"
            }
        }
    }

    private func request(_ path: String, method: String, body: Data? = nil, prefer: String? = nil) -> URLRequest {
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
        req.httpMethod = method
        req.setValue(Secrets.supabaseKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(Secrets.supabaseKey)", forHTTPHeaderField: "Authorization")
        if body != nil { req.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        if let prefer { req.setValue(prefer, forHTTPHeaderField: "Prefer") }
        req.httpBody = body
        return req
    }

    func get<T: Decodable>(path: String) async throws -> T {
        let (data, resp) = try await URLSession.shared.data(for: request(path, method: "GET"))
        try Self.check(resp, data: data)
        return try JSONDecoder().decode(T.self, from: data)
    }

    @discardableResult
    func patch(path: String, body: [String: Any?]) async throws -> Data {
        // Convert nullable values; Supabase accepts JSON null to clear a column.
        let clean: [String: Any] = body.mapValues { $0 ?? NSNull() }
        let data = try JSONSerialization.data(withJSONObject: clean)
        let (resp, http) = try await URLSession.shared.data(for: request(path, method: "PATCH", body: data, prefer: "return=minimal"))
        try Self.check(http, data: resp)
        return resp
    }

    @discardableResult
    func upsert(path: String, body: [[String: Any]], onConflict: String) async throws -> Data {
        let data = try JSONSerialization.data(withJSONObject: body)
        let p = "\(path)?on_conflict=\(onConflict)"
        let (resp, http) = try await URLSession.shared.data(for: request(p, method: "POST", body: data, prefer: "resolution=merge-duplicates,return=minimal"))
        try Self.check(http, data: resp)
        return resp
    }

    @discardableResult
    func delete(path: String) async throws -> Data {
        let (resp, http) = try await URLSession.shared.data(for: request(path, method: "DELETE", prefer: "return=minimal"))
        try Self.check(http, data: resp)
        return resp
    }

    private static func check(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        if !(200...299).contains(http.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw SBError.http(http.statusCode, body)
        }
    }
}
