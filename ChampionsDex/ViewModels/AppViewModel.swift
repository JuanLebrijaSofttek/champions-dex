import Foundation
import Observation

@Observable @MainActor final class AppViewModel {
    var roster: [RosterEntry] = []
    var details: [String: PokemonDetail] = [:]
    var appState: AppState = .launching
    var loadingMessage: String = "Starting up..."
    var detailLoadingLabel: String = ""
    var detailLoadingProgress: Double = 0.0
    var bulkDetailProgress: (current: Int, total: Int)? = nil
    var currentBulkSlug: String? = nil

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
            print("🚀✅ [ViewModel] Phase 1 — roster=\(saved.count)")
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
            if !newEntries.isEmpty {
                for entry in newEntries {
                    roster.append(RosterEntry(id: entry.slug, name: entry.name))
                }
                persistence.saveRoster(roster)
                print("🚀✅ [ViewModel] Phase 3 — added \(newEntries.count) new entries")
            }
        } catch {
            print("🚀❌ [ViewModel] Phase 3 — fetchRoster FAILED: \(error)")
            if roster.isEmpty { appState = .noDataOffline; return }
        }

        appState = .ready
        startBulkDownload()
        print("🚀✅ [ViewModel] ═══ LAUNCH END — appState=\(appState) ═══")
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
        } catch {
            detailLoadingLabel = "Failed"
            print("🌐❌ [ViewModel] loadDetail(\(slug)) — FAILED: \(error)")
        }
    }

    // MARK: Bulk download

    func startBulkDownload() {
        let slugsToLoad = roster.map { $0.id }.filter { details[$0] == nil }
        print("📥⏳ [ViewModel] startBulkDownload — \(slugsToLoad.count) details to load")
        guard !slugsToLoad.isEmpty else {
            print("📥✅ [ViewModel] startBulkDownload — nothing to load")
            appState = .ready
            return
        }

        appState = .loadingDetails
        let total = slugsToLoad.count
        bulkDetailProgress = (current: 0, total: total)

        bulkDownloadTask = Task {
            for (i, slug) in slugsToLoad.enumerated() {
                guard !Task.isCancelled else { print("📥⏳ [ViewModel] bulk cancelled at \(slug)"); break }
                currentBulkSlug = slug
                bulkDetailProgress = (current: i, total: total)
                let wasOnDisk = persistence.detailExists(slug: slug)
                await loadDetail(slug: slug)
                if !wasOnDisk {
                    try? await Task.sleep(for: .milliseconds(500))
                }
            }
            currentBulkSlug = nil
            bulkDetailProgress = (current: total, total: total)
            appState = .ready
            print("📥✅ [ViewModel] startBulkDownload complete")
        }
    }

    func cancelBulkDownload() {
        print("📥⏳ [ViewModel] cancelBulkDownload")
        bulkDownloadTask?.cancel()
        bulkDownloadTask = nil
        currentBulkSlug = nil
        bulkDetailProgress = nil
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
        appState = .launching
        Task { await launch(networkMonitor: networkMonitor) }
    }
}
