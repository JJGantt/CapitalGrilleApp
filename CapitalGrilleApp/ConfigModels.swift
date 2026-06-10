import Foundation
import CryptoKit

/// App configuration that can be overridden from Supabase without an app rebuild.
/// Ships with bundled defaults so the app works first-launch / offline — the DB
/// is an override layer, never a hard dependency.
struct AppConfig: Codable {
    var allowedBackends: [String]   // subset of ["mac","api"]
    var allowedModels: [String]     // subset of ["haiku","sonnet","opus"]
    var defaultBackend: String      // "mac" | "api"
    var defaultModel: String        // "haiku" | "sonnet" | "opus"

    enum CodingKeys: String, CodingKey {
        case allowedBackends = "allowed_backends"
        case allowedModels   = "allowed_models"
        case defaultBackend  = "default_backend"
        case defaultModel    = "default_model"
    }

    /// Owner (Jared's device): everything unlocked.
    static let owner = AppConfig(
        allowedBackends: ["mac", "api"],
        allowedModels:   ["haiku", "sonnet", "opus"],
        defaultBackend:  "mac",
        defaultModel:    "sonnet"
    )

    /// Everyone else: direct API + Haiku only.
    static let restricted = AppConfig(
        allowedBackends: ["api"],
        allowedModels:   ["haiku"],
        defaultBackend:  "api",
        defaultModel:    "haiku"
    )
}

/// Resolves device identity (owner vs everyone else) and publishes the active
/// gating that `Backend`/`AIModel` clamp to. Fails closed: until `apply()` runs,
/// only API + Haiku are permitted.
enum AppGate {
    /// SHA-256 of the owner's Anthropic API key. Hash only — safe to ship, reveals
    /// nothing. The owner device is whichever one holds that key.
    static let ownerKeyHash = "0c4eb3445e20e7d8b5164aca839f65fad2d05683f7556addbf4ca774d9a9c990"

    private(set) static var config: AppConfig = .restricted

    static var allowedBackends: Set<String> { Set(config.allowedBackends) }
    static var allowedModels: Set<String> { Set(config.allowedModels) }
    static var defaultBackend: String { config.defaultBackend }
    static var defaultModel: String { config.defaultModel }
    static var isOwnerDevice: Bool { isOwner(APIKeyStore.current) }

    static func isOwner(_ key: String?) -> Bool {
        guard let key, !key.isEmpty else { return false }
        let hex = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return hex == ownerKeyHash
    }

    /// Resolve the bundled-default config from the current key. Synchronous and
    /// instant — call at launch and whenever the key changes.
    static func apply(key: String? = APIKeyStore.current) {
        config = isOwner(key) ? .owner : .restricted
    }

    /// Pull an override row from Supabase (profile = owner|default) and apply it.
    /// Graceful: any failure (table missing, offline) leaves the bundled config.
    static func refreshFromSupabase(key: String? = APIKeyStore.current) async {
        let profile = isOwner(key) ? "owner" : "default"
        let path = "app_config?profile=eq.\(profile)&select=allowed_backends,allowed_models,default_backend,default_model"
        if let rows: [AppConfig] = try? await SupabaseClient.shared.get(path: path), let remote = rows.first {
            config = remote
        }
    }
}
