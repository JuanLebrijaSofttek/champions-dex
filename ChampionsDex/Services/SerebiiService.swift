import Foundation
import SwiftSoup

struct SerebiiService {
    private static let base = "https://www.serebii.net"

    // MARK: Roster

    func fetchRoster() async throws -> [(name: String, slug: String)] {
        let url = URL(string: "\(Self.base)/pokemonchampions/pokemon.shtml")!
        print("🌐⏳ [Serebii] fetchRoster — GET \(url)")
        let html = try await fetchHTML(url: url)
        print("🔍⏳ [Serebii] fetchRoster — first 500 chars:\n\(String(html.prefix(500)))")

        let doc = try SwiftSoup.parse(html)
        let links = try doc.select("a[href*='/pokedex-champions/']")
        print("🔍⏳ [Serebii] fetchRoster — \(links.count) candidate links")
        print("🔍⏳ [Serebii] fetchRoster — first 20 raw hrefs:")
        for (i, link) in links.enumerated().prefix(20) {
            let href = (try? link.attr("href")) ?? "?"
            let text = (try? link.text()) ?? "?"
            print("  [\(i)] href=\"\(href)\" text=\"\(text)\"")
        }

        var seen = Set<String>()
        var results: [(name: String, slug: String)] = []
        var skippedHub = 0, skippedShtml = 0, skippedDupe = 0, skippedNoName = 0

        for link in links {
            let href = try link.attr("href")
            let components = href.split(separator: "/").map(String.init)
            guard let last = components.last, last != "pokedex-champions", !last.isEmpty else { skippedHub += 1; continue }
            let slug = last.hasSuffix("/") ? String(last.dropLast()) : last
            guard !slug.contains(".shtml"), !slug.isEmpty else { skippedShtml += 1; continue }
            if seen.contains(slug) { skippedDupe += 1; continue }
            let name = try link.text()
            guard !name.isEmpty else { skippedNoName += 1; continue }
            seen.insert(slug)
            results.append((name: name, slug: slug))
        }

        print("🔍⏳ [Serebii] fetchRoster — skips: hub=\(skippedHub) shtml=\(skippedShtml) dupe=\(skippedDupe) noName=\(skippedNoName)")
        print("🌐✅ [Serebii] fetchRoster — \(results.count) Pokémon: \(results.prefix(10).map { "\($0.name)(\($0.slug))" }.joined(separator: ", "))")
        return results
    }

    // MARK: Move name list (Champions-specific learnset)

    struct SerebiiFormData {
        let formCount: Int        // true form count (from stat tables — more reliable than move tables)
        let movesByForm: [[String]] // per-form move name lists; may have fewer entries than formCount
    }

    // Scrapes the Champions detail page once and returns both the form count and move lists.
    // formCount comes from stat tables (one per form); Mega forms share a move pool so
    // movesByForm may have fewer arrays than formCount — callers should fall back to index 0.
    func fetchFormData(slug: String) async throws -> SerebiiFormData {
        let url = URL(string: "\(Self.base)/pokedex-champions/\(slug)/")!
        print("🌐⏳ [Serebii] fetchFormData(\(slug)) — GET \(url)")
        let html = try await fetchHTML(url: url)
        let doc  = try SwiftSoup.parse(html)

        // Stat tables: tables that contain any row with a cell whose text is exactly "HP".
        // Check both td and th since Serebii uses both across different page layouts.
        // There is one stat table per form (base, Mega X, Mega Y, regional variant, etc.).
        var statTableCount = 0
        for table in try doc.select("table") {
            for row in try table.select("tr") {
                let hasHP = (try? row.select("td, th").contains { ((try? $0.text())?.trimmingCharacters(in: .whitespaces)) == "HP" }) ?? false
                if hasHP { statTableCount += 1; break }
            }
        }

        // Move tables: identified by Serebii header classes (attheader or ygheader).
        // Upper cell count raised to 12 to accommodate Serebii layout variations.
        var movesByForm: [[String]] = []
        for table in try doc.select("table") {
            guard ((try? table.select("th.attheader, th.ygheader, th.bgsub").count) ?? 0) > 0 else { continue }
            var names: [String] = []
            for row in (try? table.select("tr")) ?? Elements() {
                if ((try? row.select("[colspan]").count) ?? 0) > 0 { continue }
                let cells = (try? row.select("td")) ?? Elements()
                guard cells.count >= 6 && cells.count <= 12 else { continue }
                let name = (try? cells[0].text()) ?? ""
                guard !name.isEmpty else { continue }
                names.append(name)
            }
            if !names.isEmpty { movesByForm.append(names) }
        }

        if movesByForm.isEmpty { movesByForm = [[]] }
        let formCount = max(statTableCount, movesByForm.count, 1)
        print("🌐✅ [Serebii] fetchFormData(\(slug)) — \(formCount) form(s) (\(statTableCount) stat table(s)), \(movesByForm.count) move table(s): \(movesByForm.map { $0.count })")
        return SerebiiFormData(formCount: formCount, movesByForm: movesByForm)
    }

    // MARK: Fetch helper

    private func fetchHTML(url: URL) async throws -> String {
        let start = Date()
        let (data, response) = try await URLSession.shared.data(from: url)
        let elapsed = String(format: "%.2fs", Date().timeIntervalSince(start))
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        let html = String(data: data, encoding: .isoLatin1) ?? ""
        print("🌐\(status == 200 ? "✅" : "❌") [Serebii] GET \(url.lastPathComponent) — HTTP \(status) \(data.count) bytes in \(elapsed)")
        if html.isEmpty { print("🌐❌ [Serebii] WARNING — empty string after isoLatin1 decode!") }
        return html
    }
}

enum SerebiiError: Error {
    case parseError(String)
}
