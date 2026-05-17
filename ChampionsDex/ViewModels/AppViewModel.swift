import Foundation
import UIKit
import Observation

@Observable @MainActor final class AppViewModel {
    var roster: [RosterEntry] = []
    var details: [String: PokemonDetail] = [:]
    var icons: [String: UIImage] = [:]
    var appState: AppState = .launching
    var downloadProgress: (current: Int, total: Int)? = nil
    var loadingMessage: String = "Starting up..."
    var currentDownloadingSlug: String? = nil
    var bytesDownloaded: Int = 0
    var detailLoadingLabel: String = ""
    var detailLoadingProgress: Double = 0.0

    private let persistence = PersistenceManager.shared
    private let service = SerebiiService()
    private var bulkDownloadTask: Task<Void, Never>?

    // MARK: Launch

    func launch(networkMonitor: NetworkMonitor) async {
        print("🚀⏳ [ViewModel] ═══ LAUNCH START ═══")

        // Phase 1 — disk
        loadingMessage = "Loading cached data..."
        print("🚀⏳ [ViewModel] Phase 1 — loading from disk")
        if let saved = persistence.loadRoster() {
            roster = saved
            var loaded = 0
            for entry in saved where entry.iconCached {
                if let img = persistence.loadIcon(slug: entry.id) { icons[entry.id] = img; loaded += 1 }
            }
            print("🚀✅ [ViewModel] Phase 1 — roster=\(saved.count) icons loaded=\(loaded)")
        } else {
            print("🚀⏳ [ViewModel] Phase 1 — no roster on disk (first launch)")
        }

        // Phase 2 — network state
        loadingMessage = "Checking connection..."
        print("🚀⏳ [ViewModel] Phase 2 — waiting for NetworkMonitor")
        let connected = await networkMonitor.waitForInitialState()
        print("🚀\(connected ? "✅" : "❌") [ViewModel] Phase 2 — connected=\(connected) roster=\(roster.count)")

        guard connected else {
            let state: AppState = roster.isEmpty ? .noDataOffline : .ready
            print("🚀⏳ [ViewModel] Phase 2 — offline → \(state)")
            appState = state
            return
        }

        // Phase 3 — roster sync
        loadingMessage = "Syncing Pokémon roster..."
        print("🚀⏳ [ViewModel] Phase 3 — fetching roster")
        do {
            let fetched = try await service.fetchRoster()
            let existingSlugs = Set(roster.map { $0.id })
            let newEntries = fetched.filter { !existingSlugs.contains($0.slug) }
            print("🚀✅ [ViewModel] Phase 3 — fetched=\(fetched.count) existing=\(existingSlugs.count) new=\(newEntries.count)")

            if newEntries.isEmpty {
                print("🚀✅ [ViewModel] Phase 3 — up to date → .ready")
                appState = .ready
            } else {
                print("🚀✅ [ViewModel] Phase 3 — \(newEntries.count) new Pokémon → auto-downloading")
                await downloadNewEntries(slugs: newEntries.map { $0.slug }, allFetched: fetched)
            }
        } catch {
            print("🚀❌ [ViewModel] Phase 3 — fetchRoster FAILED: \(error)")
            appState = roster.isEmpty ? .noDataOffline : .ready
        }

        print("🚀✅ [ViewModel] ═══ LAUNCH END — appState=\(appState) ═══")
    }

    // MARK: Download new roster entries

    func downloadNewEntries(slugs: [String], allFetched: [(name: String, slug: String)]) async {
        print("📥⏳ [ViewModel] downloadNewEntries — \(slugs.count) slugs")
        loadingMessage = "Downloading \(slugs.count) new Pokémon..."
        appState = .downloadingRoster
        bytesDownloaded = 0
        let nameMap = Dictionary(uniqueKeysWithValues: allFetched.map { ($0.slug, $0.name) })
        let total = slugs.count
        var current = 0
        downloadProgress = (current: 0, total: total)

        for slug in slugs {
            currentDownloadingSlug = slug
            loadingMessage = "Fetching \(slug)... (\(current + 1)/\(total))"
            print("📥⏳ [ViewModel] [\(current+1)/\(total)] Fetching \(slug)")
            do {
                let image = try await service.fetchIcon(slug: slug)
                let iconBytes = image.pngData()?.count ?? 0
                persistence.saveIcon(image, slug: slug)
                icons[slug] = image
                bytesDownloaded += iconBytes
                let name = nameMap[slug] ?? slug.capitalized
                roster.append(RosterEntry(id: slug, name: name, iconCached: true))
                persistence.saveRoster(roster)
                current += 1
                downloadProgress = (current: current, total: total)
                print("📥✅ [ViewModel] [\(current)/\(total)] \(slug) done")
                try? await Task.sleep(for: .milliseconds(300))
            } catch {
                print("📥❌ [ViewModel] [\(current+1)/\(total)] \(slug) FAILED: \(error)")
                current += 1
                downloadProgress = (current: current, total: total)
            }
        }

        currentDownloadingSlug = nil
        downloadProgress = nil
        appState = .ready
        print("📥✅ [ViewModel] downloadNewEntries complete — roster=\(roster.count)")
    }

    // MARK: Detail fetch

    func loadDetail(slug: String) async {
        print("🔍⏳ [ViewModel] loadDetail(\(slug))")
        if details[slug] != nil { print("🔍✅ [ViewModel] loadDetail(\(slug)) — already in memory"); return }
        if let cached = persistence.loadDetail(slug: slug) {
            details[slug] = cached
            print("🔍✅ [ViewModel] loadDetail(\(slug)) — loaded from disk cache (\(cached.forms.count) forms)")
            return
        }
        detailLoadingLabel = "Fetching..."
        detailLoadingProgress = 0.0
        print("🌐⏳ [ViewModel] loadDetail(\(slug)) — fetching from network")
        do {
            let detail = try await service.fetchDetail(slug: slug) { [weak self] label, pct in
                Task { @MainActor [weak self] in
                    self?.detailLoadingLabel = label
                    self?.detailLoadingProgress = pct
                }
            }
            detailLoadingLabel = "Saving..."
            detailLoadingProgress = 0.95
            persistence.saveDetail(detail)
            details[slug] = detail
            detailLoadingProgress = 1.0
            let totalMoves = detail.forms.reduce(0) { $0 + $1.moves.count }
            print("🌐✅ [ViewModel] loadDetail(\(slug)) — saved (\(detail.forms.count) forms, \(totalMoves) total moves)")
            print("📋 [\(detail.name) #\(detail.number)] gender=\(detail.genderRatio.map { "♂\($0.male)%♀\($0.female)%" } ?? "genderless")")
            for (i, f) in detail.forms.enumerated() {
                print("  form[\(i)] \"\(f.formName)\" types=\(f.types) H=\(f.height) W=\(f.weight) class=\(f.classification)")
                print("    stats HP\(f.stats.hp)/Atk\(f.stats.attack)/Def\(f.stats.defense)/SpA\(f.stats.specialAttack)/SpD\(f.stats.specialDefense)/Spe\(f.stats.speed) total=\(f.stats.total)")
                print("    abilities: \(f.abilities.map { $0.name }.joined(separator: ", "))")
                print("    matchups: \(f.typeMatchups.count) entries  moves: \(f.moves.count)")
            }
        } catch {
            detailLoadingLabel = "Failed"
            print("🌐❌ [ViewModel] loadDetail(\(slug)) — FAILED: \(error)")
        }
    }

    // MARK: Bulk download

    func startBulkDownload() {
        let slugsNeeded = roster.map { $0.id }.filter { !persistence.detailExists(slug: $0) }
        print("📥⏳ [ViewModel] startBulkDownload — \(slugsNeeded.count) details needed")
        bulkDownloadTask = Task {
            for slug in slugsNeeded {
                guard !Task.isCancelled else { print("📥⏳ [ViewModel] bulk cancelled at \(slug)"); break }
                do {
                    let detail = try await service.fetchDetail(slug: slug) { _, _ in }
                    persistence.saveDetail(detail)
                    details[slug] = detail
                    try? await Task.sleep(for: .milliseconds(500))
                } catch {
                    print("📥❌ [ViewModel] bulk \(slug) FAILED: \(error)")
                }
            }
            print("📥✅ [ViewModel] startBulkDownload complete")
        }
    }

    func cancelBulkDownload() {
        print("📥⏳ [ViewModel] cancelBulkDownload")
        bulkDownloadTask?.cancel()
        bulkDownloadTask = nil
    }

    // MARK: Cache clearing

    func clearDetail(slug: String) {
        persistence.clearDetail(slug: slug)
        details[slug] = nil
    }

    func clearAllDataAndRelaunch(networkMonitor: NetworkMonitor) {
        cancelBulkDownload()
        persistence.clearAllData()
        roster = []
        details = [:]
        icons = [:]
        appState = .launching
        Task { await launch(networkMonitor: networkMonitor) }
    }

    // MARK: Icon loading

    func loadIconIfNeeded(slug: String) async {
        guard icons[slug] == nil else { return }
        if let img = persistence.loadIcon(slug: slug) { icons[slug] = img }
    }
}
