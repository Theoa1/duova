import CryptoKit
import Foundation
import Supabase

/// Every preference that follows the account between devices. App Lock and
/// Touch ID / Face ID sign-in are deliberately absent: they protect one device
/// and stay on it.
struct PreferenceSnapshot: Equatable {
    var appearance: AppearanceMode
    var colorStyle: DuovaColorStyle
    var motion: MotionLevel
    var defaults: ServiceDefaults
    var overrides: [String: ServiceOverrides]
    var favorites: [String]
}

enum PreferencePull: Equatable {
    /// Nothing saved in the cloud yet. `revision` is 0 when there's no row.
    case empty(revision: Int64)
    /// What's saved, and the revision to save on top of.
    case snapshot(PreferenceSnapshot, revision: Int64)
    /// Saved from a device whose keys this one doesn't have. Never overwrite it.
    case sealedElsewhere
}

/// Reads and writes `duova_user_preferences` and `duova_user_app_preferences`.
/// Each column holds its own `dv2` envelope (two layers of encryption, bound to
/// the user, row and column), and app rows are keyed by an opaque HMAC rather
/// than the app's name. Saving is all-or-nothing and only lands on the
/// revision this device last read (`duova_save_preferences`, schema v5).
struct PreferenceCloudStore {
    private static let accountTable = "duova_user_preferences"
    private static let appTable = "duova_user_app_preferences"

    let client: SupabaseClient
    let userID: UUID
    private let master: SymmetricKey
    private let vault: SymmetricKey

    init(client: SupabaseClient, userID: UUID) throws {
        self.client = client
        self.userID = userID
        master = try KeychainKeyProvider().masterKey(for: userID)
        vault = try KeychainKeyProvider.vault.masterKey(for: userID)
    }

    private var userKey: String { userID.uuidString.lowercased() }

    private func seal(_ text: String, table: String, record: String, column: String) throws -> String {
        try PrivateDataCrypto.sealDouble(
            Data(text.utf8), outer: master, inner: vault,
            context: EnvelopeContext(userID: userID, table: table, recordID: record, column: column))
    }

    private func open(_ envelope: String, table: String, record: String, column: String) throws -> String {
        let data = try PrivateDataCrypto.openDouble(
            envelope, outer: master, inner: vault,
            context: EnvelopeContext(userID: userID, table: table, recordID: record, column: column))
        guard let text = String(data: data, encoding: .utf8) else { throw PrivateDataError.malformedEnvelope }
        return text
    }

    func appReference(_ slug: String) -> String {
        PrivateDataCrypto.appReference(for: slug, masterKey: master, userID: userID)
    }

    // MARK: Columns

    fileprivate static let overrideColumns: [(String, WritableKeyPath<ServiceOverrides, String?>)] = [
        ("appearance_mode_enc", \.appearanceRaw),
        ("motion_level_enc", \.motionRaw),
        ("expanded_layout_enc", \.expandedLayoutRaw),
        ("panel_ratio_enc", \.panelRatioRaw),
        ("opening_behavior_enc", \.openingRaw),
        ("switcher_side_enc", \.switcherSideRaw),
        ("gesture_style_enc", \.gestureRaw),
    ]

    // MARK: Push

    private struct SaveParams: Encodable {
        let expectedRevision: Int64
        let account: [String: String?]
        let apps: [[String: String?]]
        enum CodingKeys: String, CodingKey {
            case expectedRevision = "expected_revision", account, apps
        }
    }

    /// Saves everything on top of `expectedRevision`. Returns the new revision,
    /// or nil when another device saved first (nothing was changed then).
    func push(_ snapshot: PreferenceSnapshot, expectedRevision: Int64) async throws -> Int64? {
        let table = Self.accountTable
        var row: [String: String?] = [:]
        func put(_ column: String, _ value: String) throws {
            row[column] = try seal(value, table: table, record: userKey, column: column)
        }
        try put("appearance_mode_enc", snapshot.appearance.rawValue)
        try put("color_style_enc", snapshot.colorStyle.rawValue)
        try put("motion_level_enc", snapshot.motion.rawValue)
        try put("expanded_layout_enc", snapshot.defaults.expandedLayout.rawValue)
        try put("panel_ratio_enc", snapshot.defaults.panelRatio.rawValue)
        try put("opening_behavior_enc", snapshot.defaults.opening.rawValue)
        try put("switcher_side_enc", snapshot.defaults.switcherSide.rawValue)
        try put("gesture_style_enc", snapshot.defaults.gesture.rawValue)
        let favorites = String(decoding: try JSONEncoder().encode(snapshot.favorites), as: UTF8.self)
        try put("favorites_enc", favorites)

        // Apps back on the defaults have no row; the server removes theirs.
        var appRows: [[String: String?]] = []
        for (slug, overrides) in snapshot.overrides where !overrides.isEmpty {
            let ref = appReference(slug)
            var appRow: [String: String?] = [
                "app_ref": ref,
                "app_slug_enc": try seal(slug, table: Self.appTable, record: ref, column: "app_slug_enc"),
            ]
            for (column, keyPath) in Self.overrideColumns {
                // updateValue keeps an explicit null, so a cleared override is cleared remotely too.
                appRow.updateValue(
                    try overrides[keyPath: keyPath].map {
                        try seal($0, table: Self.appTable, record: ref, column: column)
                    },
                    forKey: column)
            }
            appRows.append(appRow)
        }

        let revision: Int64 = try await client
            .rpc("duova_save_preferences", params: SaveParams(expectedRevision: expectedRevision, account: row, apps: appRows))
            .execute().value
        return revision > 0 ? revision : nil
    }

    // MARK: Pull

    private struct RevisionRow: Decodable {
        let revision: Int64
    }

    func pull() async throws -> PreferencePull {
        // The revision is read before the values: values newer than it only
        // make the next save a conflict, never an overwrite.
        let revisions: [RevisionRow] = try await client.from(Self.accountTable)
            .select("revision").eq("user_id", value: userKey).execute().value
        let revision = revisions.first?.revision ?? 0
        let accountColumns = [
            "appearance_mode_enc", "color_style_enc", "motion_level_enc", "expanded_layout_enc",
            "panel_ratio_enc", "opening_behavior_enc", "switcher_side_enc", "gesture_style_enc", "favorites_enc",
        ]
        let rows: [[String: String?]] = try await client.from(Self.accountTable)
            .select(accountColumns.joined(separator: ","))
            .eq("user_id", value: userKey).execute().value
        guard let row = rows.first, row.values.contains(where: { $0 != nil }) else { return .empty(revision: revision) }

        do {
            func value(_ column: String) throws -> String? {
                guard let envelope = row[column] ?? nil else { return nil }
                return try open(envelope, table: Self.accountTable, record: userKey, column: column)
            }
            var defaults = ServiceDefaults()
            if let v = try value("expanded_layout_enc").flatMap(ExpandedLayout.init(rawValue:)) { defaults.expandedLayout = v }
            if let v = try value("panel_ratio_enc").flatMap(PanelRatio.init(rawValue:)) { defaults.panelRatio = v }
            if let v = try value("opening_behavior_enc").flatMap(OpeningBehavior.init(rawValue:)) { defaults.opening = v }
            if let v = try value("switcher_side_enc").flatMap(SwitcherSide.init(rawValue:)) { defaults.switcherSide = v }
            if let v = try value("gesture_style_enc").flatMap(GestureStyle.init(rawValue:)) { defaults.gesture = v }
            let favorites = try value("favorites_enc")
                .flatMap { try? JSONDecoder().decode([String].self, from: Data($0.utf8)) } ?? []

            let appRows: [[String: String?]] = try await client.from(Self.appTable)
                .select((["app_ref", "app_slug_enc"] + Self.overrideColumns.map(\.0)).joined(separator: ","))
                .eq("user_id", value: userKey).execute().value
            var overrides: [String: ServiceOverrides] = [:]
            for appRow in appRows {
                guard let ref = appRow["app_ref"] ?? nil, let slugEnvelope = appRow["app_slug_enc"] ?? nil else { continue }
                let slug = try open(slugEnvelope, table: Self.appTable, record: ref, column: "app_slug_enc")
                var override = ServiceOverrides()
                for (column, keyPath) in Self.overrideColumns {
                    if let envelope = appRow[column] ?? nil {
                        override[keyPath: keyPath] = try open(envelope, table: Self.appTable, record: ref, column: column)
                    }
                }
                if !override.isEmpty { overrides[slug] = override }
            }

            return .snapshot(PreferenceSnapshot(
                appearance: try value("appearance_mode_enc").flatMap(AppearanceMode.init(rawValue:)) ?? .system,
                colorStyle: try value("color_style_enc").flatMap(DuovaColorStyle.init(rawValue:)) ?? .duova,
                motion: try value("motion_level_enc").flatMap(MotionLevel.init(rawValue:)) ?? .standard,
                defaults: defaults, overrides: overrides, favorites: favorites), revision: revision)
        } catch PrivateDataError.authenticationFailed {
            return .sealedElsewhere
        }
    }
}

extension PreferenceSnapshot {
    /// Combines two devices' changes made since `base` (what both last agreed
    /// on): each setting this device changed keeps its value, every other one
    /// takes the other device's. Favorites merge item by item.
    static func merge(base: PreferenceSnapshot, local: PreferenceSnapshot, remote: PreferenceSnapshot) -> PreferenceSnapshot {
        func pick<Value: Equatable>(_ keyPath: KeyPath<PreferenceSnapshot, Value>) -> Value {
            local[keyPath: keyPath] != base[keyPath: keyPath] ? local[keyPath: keyPath] : remote[keyPath: keyPath]
        }
        var merged = remote
        merged.appearance = pick(\.appearance)
        merged.colorStyle = pick(\.colorStyle)
        merged.motion = pick(\.motion)
        merged.defaults.expandedLayout = pick(\.defaults.expandedLayout)
        merged.defaults.panelRatio = pick(\.defaults.panelRatio)
        merged.defaults.opening = pick(\.defaults.opening)
        merged.defaults.switcherSide = pick(\.defaults.switcherSide)
        merged.defaults.gesture = pick(\.defaults.gesture)

        let added = local.favorites.filter { !base.favorites.contains($0) }
        let removed = Set(base.favorites.filter { !local.favorites.contains($0) })
        merged.favorites = remote.favorites.filter { !removed.contains($0) }
        merged.favorites += added.filter { !merged.favorites.contains($0) }

        var overrides: [String: ServiceOverrides] = [:]
        for slug in Set(base.overrides.keys).union(local.overrides.keys).union(remote.overrides.keys) {
            let mine = local.overrides[slug] ?? ServiceOverrides()
            let before = base.overrides[slug] ?? ServiceOverrides()
            var combined = remote.overrides[slug] ?? ServiceOverrides()
            for (_, keyPath) in PreferenceCloudStore.overrideColumns where mine[keyPath: keyPath] != before[keyPath: keyPath] {
                combined[keyPath: keyPath] = mine[keyPath: keyPath]
            }
            if !combined.isEmpty { overrides[slug] = combined }
        }
        merged.overrides = overrides
        return merged
    }
}

/// String views of each override, for storing one encrypted column per setting.
private extension ServiceOverrides {
    var appearanceRaw: String? {
        get { appearance?.rawValue }
        set { appearance = newValue.flatMap(AppearanceMode.init(rawValue:)) }
    }
    var motionRaw: String? {
        get { motion?.rawValue }
        set { motion = newValue.flatMap(MotionLevel.init(rawValue:)) }
    }
    var expandedLayoutRaw: String? {
        get { expandedLayout?.rawValue }
        set { expandedLayout = newValue.flatMap(ExpandedLayout.init(rawValue:)) }
    }
    var panelRatioRaw: String? {
        get { panelRatio?.rawValue }
        set { panelRatio = newValue.flatMap(PanelRatio.init(rawValue:)) }
    }
    var openingRaw: String? {
        get { opening?.rawValue }
        set { opening = newValue.flatMap(OpeningBehavior.init(rawValue:)) }
    }
    var switcherSideRaw: String? {
        get { switcherSide?.rawValue }
        set { switcherSide = newValue.flatMap(SwitcherSide.init(rawValue:)) }
    }
    var gestureRaw: String? {
        get { gesture?.rawValue }
        set { gesture = newValue.flatMap(GestureStyle.init(rawValue:)) }
    }
}
