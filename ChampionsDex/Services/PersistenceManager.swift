import Foundation

final class PersistenceManager {
    static let shared = PersistenceManager()

    private let root: URL

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        root = appSupport.appendingPathComponent("ChampionsDex", isDirectory: true)
        print("💾⏳ [Persistence] Root: \(root.path)")
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: root.appendingPathComponent("details"), withIntermediateDirectories: true)
            print("💾✅ [Persistence] Directories ready")
        } catch {
            print("💾❌ [Persistence] Directory creation failed: \(error)")
        }
    }

    // MARK: Roster

    func loadRoster() -> [RosterEntry]? {
        let url = root.appendingPathComponent("roster.json")
        print("💾⏳ [Persistence] loadRoster — \(url.lastPathComponent)")
        guard let data = try? Data(contentsOf: url) else {
            print("💾⏳ [Persistence] loadRoster — no file (first launch)")
            return nil
        }
        do {
            let roster = try JSONDecoder().decode([RosterEntry].self, from: data)
            print("💾✅ [Persistence] loadRoster — \(roster.count) entries, \(data.count) bytes")
            return roster
        } catch {
            print("💾❌ [Persistence] loadRoster — decode error: \(error)")
            return nil
        }
    }

    func saveRoster(_ roster: [RosterEntry]) {
        let url = root.appendingPathComponent("roster.json")
        do {
            let data = try JSONEncoder().encode(roster)
            try data.write(to: url, options: .atomic)
            print("💾✅ [Persistence] saveRoster — \(roster.count) entries, \(data.count) bytes")
        } catch {
            print("💾❌ [Persistence] saveRoster — \(error)")
        }
    }

    // MARK: Details

    func detailExists(slug: String) -> Bool {
        FileManager.default.fileExists(atPath: detailURL(slug: slug).path)
    }

    func loadDetail(slug: String) -> PokemonDetail? {
        print("💾⏳ [Persistence] loadDetail(\(slug))")
        guard let data = try? Data(contentsOf: detailURL(slug: slug)) else {
            print("💾⏳ [Persistence] loadDetail(\(slug)) — not cached")
            return nil
        }
        do {
            let detail = try JSONDecoder().decode(PokemonDetail.self, from: data)
            let totalMoves = detail.forms.reduce(0) { $0 + $1.moves.count }
            print("💾✅ [Persistence] loadDetail(\(slug)) — \(detail.forms.count) forms, \(totalMoves) moves")
            return detail
        } catch {
            print("💾❌ [Persistence] loadDetail(\(slug)) — decode error: \(error)")
            return nil
        }
    }

    func saveDetail(_ detail: PokemonDetail) {
        do {
            let data = try JSONEncoder().encode(detail)
            try data.write(to: detailURL(slug: detail.id), options: .atomic)
            print("💾✅ [Persistence] saveDetail(\(detail.id)) — \(data.count) bytes")
        } catch {
            print("💾❌ [Persistence] saveDetail(\(detail.id)) — \(error)")
        }
    }

    // MARK: Cache clearing

    func clearDetail(slug: String) {
        try? FileManager.default.removeItem(at: detailURL(slug: slug))
        print("💾✅ [Persistence] clearDetail(\(slug))")
    }

    func clearAllData() {
        let fm = FileManager.default
        try? fm.removeItem(at: root.appendingPathComponent("roster.json"))
        for dir in ["details", "icons"] {
            let dirURL = root.appendingPathComponent(dir)
            if let files = try? fm.contentsOfDirectory(at: dirURL, includingPropertiesForKeys: nil) {
                files.forEach { try? fm.removeItem(at: $0) }
            }
        }
        print("💾✅ [Persistence] clearAllData")
    }

    // MARK: Helpers

    private func detailURL(slug: String) -> URL { root.appendingPathComponent("details/\(slug).json") }
}
