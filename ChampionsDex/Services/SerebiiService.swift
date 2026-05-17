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

    // MARK: Detail

    func fetchDetail(slug: String, progress: @escaping (String, Double) -> Void) async throws -> PokemonDetail {
        progress("Fetching page...", 0.0)
        let url = URL(string: "\(Self.base)/pokedex-champions/\(slug)/")!
        print("🌐⏳ [Serebii] fetchDetail(\(slug)) — GET \(url)")
        let html = try await fetchHTML(url: url)
        let doc = try SwiftSoup.parse(html)

        progress("Parsing basic info...", 0.25)
        let (name, number) = parseTitle(try doc.title())
        let genderRatio = try parseGenderRatio(doc: doc)
        print("🔍✅ [Serebii] fetchDetail(\(slug)) — name=\(name) #\(number) gender=\(genderRatio.map { "♂\($0.male)% ♀\($0.female)%" } ?? "genderless")")

        progress("Parsing forms & stats...", 0.50)
        let forms = try parseAllForms(doc: doc, slug: slug, number: number)
        print("🔍✅ [Serebii] fetchDetail(\(slug)) — \(forms.count) forms")
        for (i, f) in forms.enumerated() {
            print("  form[\(i)] \"\(f.formName)\" types=\(f.types.joined(separator: "/")) stats total=\(f.stats.total) moves=\(f.moves.count) imageURL=\(f.imageURL)")
        }

        progress("Parsing moves...", 0.75)
        // moves already included inside parseAllForms

        return PokemonDetail(id: slug, name: name, number: number, genderRatio: genderRatio, forms: forms, fetchedAt: Date())
    }

    // MARK: Gender

    private func parseGenderRatio(doc: Document) throws -> GenderRatio? {
        var malePct: Double? = nil
        var femalePct: Double? = nil
        for td in try doc.select("td") {
            let text = (try? td.text()) ?? ""
            if text == "Genderless" { return nil }
            if text.contains("Male") && text.contains("%"), malePct == nil {
                malePct = extractPercentage(from: text)
            } else if text.contains("Female") && text.contains("%"), femalePct == nil {
                femalePct = extractPercentage(from: text)
            }
            if malePct != nil && femalePct != nil { break }
        }
        guard let m = malePct else { return nil }
        return GenderRatio(male: m, female: femalePct ?? (100 - m))
    }

    private func extractPercentage(from text: String) -> Double? {
        let parts = text.components(separatedBy: "%")
        guard parts.count >= 2 else { return nil }
        let tokens = parts[0].components(separatedBy: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ":♂♀")))
        for token in tokens.reversed() {
            let t = token.trimmingCharacters(in: .whitespaces)
            if !t.isEmpty, let val = Double(t) { return val }
        }
        return nil
    }

    // MARK: Forms

    private func parseAllForms(doc: Document, slug: String, number: Int) throws -> [PokemonForm] {
        let allTables = try doc.select("table")

        // Stat tables — one per form (check ANY cell for "HP", not just the first)
        var statTables: [Element] = []
        for table in allTables {
            for row in try table.select("tr") {
                let cells = try row.select("td")
                if cells.contains(where: { ((try? $0.text())?.trimmingCharacters(in: .whitespaces)) == "HP" }) {
                    statTables.append(table)
                    break
                }
            }
        }
        print("🔍⏳ [Serebii] parseAllForms(\(slug)) — \(statTables.count) stat tables")

        // Form images
        let formImages = try parseFormImages(doc: doc, number: number)
        print("🔍⏳ [Serebii] parseAllForms(\(slug)) — \(formImages.count) form images: \(formImages)")

        let formCount = max(1, max(statTables.count, formImages.count))

        // Form names
        var formNames = try parseFormNames(doc: doc, slug: slug, formImages: formImages)
        while formNames.count < formCount { formNames.append(formNames.first ?? slug.capitalized) }
        print("🔍⏳ [Serebii] parseAllForms(\(slug)) — form names: \(formNames)")

        // Per-form types
        let allFormTypes = try parseAllFormTypes(doc: doc)
        print("🔍⏳ [Serebii] parseAllForms(\(slug)) — type sets: \(allFormTypes.map { $0.joined(separator: "/") })")

        // Per-form matchups — skip all-neutral rows (empty dict = all values were 1.0)
        let allMatchups = try parseAllMatchupMaps(doc: doc)
        let validMatchups = allMatchups.filter { !$0.isEmpty }
        print("🔍⏳ [Serebii] parseAllForms(\(slug)) — \(allMatchups.count) matchup tables, \(validMatchups.count) non-neutral")

        // Classification, height, weight
        let (classifications, heights, weights) = try parseClassificationHeightWeight(doc: doc)
        print("🔍⏳ [Serebii] parseAllForms(\(slug)) — classifications=\(classifications) heights=\(heights) weights=\(weights)")

        // Abilities (per form)
        let allFormAbilities = try parseAllFormAbilities(doc: doc)
        print("🔍⏳ [Serebii] parseAllForms(\(slug)) — \(allFormAbilities.count) ability group(s): \(allFormAbilities.map { $0.map { $0.name }.joined(separator: "/") }.joined(separator: " | "))")

        // Moves per form
        let allMoveTables = try parseAllMoveTables(doc: doc, statTables: statTables)

        var forms: [PokemonForm] = []
        for i in 0..<formCount {
            let formName      = i < formNames.count      ? formNames[i]        : (formNames.first ?? slug.capitalized)
            let imageURL      = i < formImages.count     ? formImages[i]       : (formImages.first ?? "")
            let types         = i < allFormTypes.count   ? allFormTypes[i]     : (allFormTypes.first ?? [])
            let classification = i < classifications.count ? classifications[i] : (classifications.first ?? "")
            let height        = i < heights.count        ? heights[i]          : (heights.first ?? "")
            let weight        = i < weights.count        ? weights[i]          : (weights.first ?? "")
            let abilities     = i < allFormAbilities.count ? allFormAbilities[i] : (allFormAbilities.first ?? [])
            let stats         = i < statTables.count     ? parseStats(table: statTables[i]) : Stats(hp:0,attack:0,defense:0,specialAttack:0,specialDefense:0,speed:0)
            let typeMatchups  = i < validMatchups.count  ? validMatchups[i]    : (validMatchups.first ?? [:])
            let moves         = i < allMoveTables.count  ? allMoveTables[i]    : (allMoveTables.first ?? [])
            forms.append(PokemonForm(formName: formName, imageURL: imageURL, types: types,
                                     classification: classification, height: height, weight: weight,
                                     abilities: abilities, stats: stats, typeMatchups: typeMatchups, moves: moves))
        }
        return forms
    }

    private func parseFormImages(doc: Document, number: Int) throws -> [String] {
        // Arcanine pattern: img.formpic
        let formpics = try doc.select("img.formpic")
        if !formpics.isEmpty {
            print("🔍⏳ [Serebii] parseFormImages — \(formpics.count) formpic imgs")
            return formpics.compactMap { img -> String? in
                guard let src = try? img.attr("src"), !src.isEmpty else { return nil }
                return src.hasPrefix("http") ? src : "\(Self.base)\(src)"
            }
        }

        // Gardevoir pattern: pokemonhome/legendsz-a sprite paths
        let numStr = "\(number)"
        let numStr3 = String(format: "%03d", number)
        var baseImage: String? = nil
        var extraImages: [String] = []
        var seenSrcs = Set<String>()

        for img in try doc.select("img") {
            let src = (try? img.attr("src")) ?? ""
            guard !src.isEmpty, !seenSrcs.contains(src) else { continue }
            guard src.contains("/pokemonhome/pokemon/") || src.contains("/legendsz-a/pokemon/") else { continue }

            let filename = src.components(separatedBy: "/").last?.components(separatedBy: ".").first ?? ""
            let isBase = filename == numStr || filename == numStr3
            let isExtra = !isBase && (filename.hasPrefix(numStr + "-") || filename.hasPrefix(numStr3 + "-"))
            guard isBase || isExtra else { continue }

            // Skip gender-difference sprites (suffix "f" = female)
            if isExtra {
                let suffixPart = filename.components(separatedBy: "-").dropFirst()
                    .joined(separator: "-").lowercased()
                if suffixPart == "f" { seenSrcs.insert(src); continue }
            }

            seenSrcs.insert(src)
            let fullURL = src.hasPrefix("http") ? src : "\(Self.base)\(src)"
            if isBase && baseImage == nil { baseImage = fullURL }
            else if isExtra { extraImages.append(fullURL) }
        }

        var images: [String] = []
        if let base = baseImage { images.append(base) }
        images.append(contentsOf: extraImages)
        print("🔍⏳ [Serebii] parseFormImages — pokemonhome: \(images.count) images")
        return images.isEmpty ? [""] : images
    }

    private func parseFormNames(doc: Document, slug: String, formImages: [String]) throws -> [String] {
        // Formpic-based: extract text from parent td of each formpic img
        let formpics = try doc.select("img.formpic")
        if !formpics.isEmpty {
            var names: [String] = []
            for img in formpics {
                var name = ""
                var el: Element? = img.parent()
                while let e = el, name.isEmpty {
                    let own = (try? e.ownText())?.trimmingCharacters(in: .whitespaces) ?? ""
                    if !own.isEmpty { name = own; break }
                    el = e.parent()
                }
                // Fallback: use alt attribute (e.g. "Johtonian Form", "Hisuian Form")
                if name.isEmpty { name = (try? img.attr("alt")) ?? "" }
                names.append(name.isEmpty ? (names.isEmpty ? slug.capitalized : "Alternate Form") : name)
            }
            if !names.isEmpty { return names }
        }

        // Pokemonhome/Mega pattern: derive name from image URL suffix
        let baseName = slug.split(separator: "-").map { $0.capitalized }.joined(separator: " ")
        var names = [baseName]
        for url in formImages.dropFirst() {
            let filename = url.components(separatedBy: "/").last?.components(separatedBy: ".").first ?? ""
            let suffix = filename.components(separatedBy: "-").dropFirst().joined(separator: "-").lowercased()
            let prefix = Self.formSuffixNames[suffix] ?? "Form \(suffix.uppercased())"
            names.append("\(prefix) \(baseName)")
        }
        return names
    }

    private static let typeNames = Set(["Normal","Fire","Water","Electric","Grass","Ice",
        "Fighting","Poison","Ground","Flying","Psychic","Bug","Rock","Ghost",
        "Dragon","Dark","Steel","Fairy"])

    private static let statLabels = Set(["HP","Attack","Defense","Sp. Atk","Sp. Def","Speed"])

    private static let formSuffixNames: [String: String] = [
        "m": "Mega", "mega": "Mega", "gmax": "Gigantamax",
        "mx": "Mega X", "my": "Mega Y",
        "mega-x": "Mega X", "mega-y": "Mega Y",
        "g": "Galarian", "h": "Hisuian", "a": "Alolan", "p": "Partner"
    ]

    // Walk every img in the doc, pick type badges (alt="TypeName-type", no " - " prefix),
    // then walk up the DOM to the containing <tr>. This avoids SwiftSoup's recursive
    // table.select("tr") collapsing inner/outer rows into one ambiguous sequence.
    private func parseAllFormTypes(doc: Document) throws -> [[String]] {
        var entries: [(Element, String)] = []

        for img in try doc.select("img") {
            let alt = (try? img.attr("alt")) ?? ""
            // Move-type badges have alt like "Tackle - Normal-type"; skip those.
            guard alt.hasSuffix("-type"), !alt.contains(" - ") else { continue }
            let typeName = alt.replacingOccurrences(of: "-type", with: "")
                .trimmingCharacters(in: .whitespaces)
            guard Self.typeNames.contains(typeName) else { continue }

            // Walk up to the nearest <tr>
            var el: Element? = img.parent()
            while let e = el, e.tagName() != "tr" { el = e.parent() }
            guard let row = el else { continue }
            // Skip type-matchup rows (exactly 18 cells)
            guard (try? row.select("td").count) != 18 else { continue }

            entries.append((row, typeName))
        }

        // Group by row, preserving DOM order, deduplicating types within each row.
        var seen = Set<ObjectIdentifier>()
        var rowOrder: [Element] = []
        var rowTypeMap: [ObjectIdentifier: [String]] = [:]

        for (row, typeName) in entries {
            let id = ObjectIdentifier(row)
            if seen.insert(id).inserted { rowOrder.append(row) }
            if !(rowTypeMap[id]?.contains(typeName) ?? false) {
                rowTypeMap[id, default: []].append(typeName)
            }
        }

        let rawResult = rowOrder.compactMap { rowTypeMap[ObjectIdentifier($0)] }

        // Collapse consecutive identical type sets (same form represented in multiple rows).
        var deduped: [[String]] = []
        for types in rawResult {
            if types != deduped.last { deduped.append(types) }
        }

        return deduped.isEmpty ? [[]] : deduped
    }

    private func parseAllMatchupMaps(doc: Document) throws -> [[String: Double]] {
        let typeOrder = ["Normal","Fire","Water","Electric","Grass","Ice","Fighting",
                         "Poison","Ground","Flying","Psychic","Bug","Rock","Ghost",
                         "Dragon","Dark","Steel","Fairy"]
        var result: [[String: Double]] = []
        for table in try doc.select("table") {
            for row in try table.select("tr") {
                let cells = try row.select("td")
                guard cells.count == 18 else { continue }
                var matchups: [String: Double] = [:]
                for (i, cell) in cells.enumerated() {
                    let text = ((try? cell.text()) ?? "").replacingOccurrences(of: "*", with: "")
                    if let val = Double(text), val != 1.0 { matchups[typeOrder[i]] = val }
                }
                result.append(matchups)
            }
        }
        return result
    }

    private func stripMetric(_ s: String) -> String {
        guard s.contains("'") else { return s }
        return s.components(separatedBy: " ").first ?? s
    }

    private func parseClassificationHeightWeight(doc: Document) throws -> ([String], [String], [String]) {
        for table in try doc.select("table") {
            for row in try table.select("tr") {
                let cells = try row.select("td")
                guard cells.count == 3 else { continue }
                guard let heightText = try? cells[1].text(), heightText.contains("'") || heightText.contains("\"") else { continue }

                // Use text nodes to split on <br>: each text node is one form's value
                let classNodes = cells[0].textNodes().map { $0.text().trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                let heightNodes = cells[1].textNodes().map { $0.text().trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                let weightNodes = cells[2].textNodes().map { $0.text().trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }

                // Imperial height line: first text node (contains '), split by " / " for per-form
                let imperialH = heightNodes.first ?? heightText
                let heights = imperialH.components(separatedBy: " / ").map { stripMetric($0.trimmingCharacters(in: .whitespaces)) }.filter { $0.contains("'") || $0.contains("\"") }

                // Weight line: first text node (lbs), split by " / " for per-form, keep lbs values
                let lbsW = weightNodes.first ?? (try? cells[2].text()) ?? ""
                let weights = lbsW.components(separatedBy: " / ").map { $0.trimmingCharacters(in: .whitespaces) }.filter { $0.hasSuffix("lbs") }

                let classifications = classNodes.isEmpty ? [(try? cells[0].text()) ?? ""] : classNodes

                return (classifications, heights.isEmpty ? [""] : heights, weights.isEmpty ? [""] : weights)
            }
        }
        return ([""], [""], [""])
    }

    private func parseAllFormAbilities(doc: Document) throws -> [[Ability]] {
        var result: [[Ability]] = []
        for table in try doc.select("table") {
            for row in try table.select("tr") {
                for td in try row.select("td") {
                    if let b = try td.select("b").first(), (try? b.text())?.contains("Abilit") == true {
                        let abilities = try parseAbilitiesFromTD(td: td, row: row)
                        if !abilities.isEmpty { result.append(abilities) }
                    }
                }
            }
        }
        return result.isEmpty ? [[]] : result
    }

    private func parseAbilitiesFromTD(td: Element, row: Element) throws -> [Ability] {
        let links = try td.select("a[href*='/abilitydex/']")
        let names = try links.map { try $0.text() }
        guard !names.isEmpty else { return [] }

        // Descriptions are in the next sibling row's first TD, not the names row
        var working = ""
        if let nextRow = try? row.nextElementSibling() {
            working = (try? nextRow.select("td").first()?.text()) ?? ""
        }
        // Fallback: same TD text after ":"
        if working.isEmpty {
            working = (try? td.text()) ?? ""
            if let colonIdx = working.firstIndex(of: ":") {
                working = String(working[working.index(after: colonIdx)...]).trimmingCharacters(in: .whitespaces)
            }
        }

        var abilities: [Ability] = []
        var remaining = working
        for (i, name) in names.enumerated() {
            guard let nameRange = remaining.range(of: name) else {
                abilities.append(Ability(name: name, description: ""))
                continue
            }
            var afterName = String(remaining[nameRange.upperBound...]).trimmingCharacters(in: .whitespaces)
            if afterName.hasPrefix(":") { afterName = String(afterName.dropFirst()).trimmingCharacters(in: .whitespaces) }
            if afterName.hasPrefix("-") { afterName = String(afterName.dropFirst()).trimmingCharacters(in: .whitespaces) }

            var desc: String
            if i + 1 < names.count, let nextRange = afterName.range(of: names[i + 1]) {
                desc = String(afterName[..<nextRange.lowerBound])
            } else {
                desc = afterName
            }
            desc = desc.trimmingCharacters(in: .whitespacesAndNewlines)
                       .trimmingCharacters(in: CharacterSet(charactersIn: ".|:"))
                       .trimmingCharacters(in: .whitespacesAndNewlines)
            abilities.append(Ability(name: name, description: desc))
            remaining = String(remaining[nameRange.upperBound...])
        }
        // Deduplicate by name within this form
        var seen = Set<String>()
        return abilities.filter { seen.insert($0.name).inserted }
    }

    private func parseMoveRows(from table: Element) -> [Move] {
        // Move rows: [name] [type img] [category img] [power] [accuracy] [pp] [effect%]
        // Description rows: [effect text colspan=6] — skipped by colspan guard
        // Type/category are images; parse from alt attribute.
        var moves: [Move] = []
        var loggedFirst = false
        for row in (try? table.select("tr")) ?? Elements() {
            if ((try? row.select("[colspan]").count) ?? 0) > 0 { continue }
            let cells = (try? row.select("td")) ?? Elements()
            guard cells.count >= 6 && cells.count <= 9 else { continue }
            let name = (try? cells[0].text()) ?? ""
            // Type: img alt = "MoveName - TypeName-type"
            let typeAlt = (try? cells[1].select("img").first()?.attr("alt")) ?? ""
            let type = typeAlt.components(separatedBy: " - ").last?
                .replacingOccurrences(of: "-type", with: "")
                .trimmingCharacters(in: .whitespaces) ?? ""
            guard !name.isEmpty, Self.typeNames.contains(type) else { continue }
            if !loggedFirst {
                print("🔍⏳ [Serebii] parseMoveRows — first row: \(cells.count) cells name=\"\(name)\" type=\"\(type)\"")
                loggedFirst = true
            }
            // Category: img alt = "MoveName: Physical Move" / "Special Move" / "Status Move"
            let catAlt = cells.count > 2 ? ((try? cells[2].select("img").first()?.attr("alt")) ?? "") : ""
            let category = catAlt.components(separatedBy: ": ").last?
                .replacingOccurrences(of: " Move", with: "")
                .trimmingCharacters(in: .whitespaces) ?? ""
            let pwrStr = cells.count > 3 ? ((try? cells[3].text()) ?? "") : ""
            let accStr = cells.count > 4 ? ((try? cells[4].text()) ?? "") : ""
            let power: Int? = (pwrStr == "--" || pwrStr.isEmpty) ? nil : (Int(pwrStr) == 101 ? nil : Int(pwrStr))
            let accuracy: Int? = (accStr == "--" || accStr.isEmpty) ? nil : Int(accStr)
            moves.append(Move(
                name: name, type: type, category: category,
                power: power, accuracy: accuracy,
                pp: Int(cells.count > 5 ? ((try? cells[5].text())?.trimmingCharacters(in: .whitespaces) ?? "") : "") ?? 0,
                effect: cells.count > 6 ? ((try? cells[6].text()) ?? "") : ""
            ))
        }
        return moves
    }

    private func parseAllMoveTables(doc: Document, statTables: [Element]) throws -> [[Move]] {
        // Move tables are identified by th.attheader header cells (Attack Name | Type | Cat. | ...)
        // This is more reliable than position-relative-to-stat-tables since moves appear before stats in HTML.
        var result: [[Move]] = []
        for table in try doc.select("table") {
            guard ((try? table.select("th.attheader").count) ?? 0) > 0 else { continue }
            let moves = parseMoveRows(from: table)
            if !moves.isEmpty { result.append(moves) }
        }
        print("🔍⏳ [Serebii] parseAllMoveTables — \(result.count) move tables with counts: \(result.map { $0.count })")
        return result.isEmpty ? [[]] : result
    }

    // MARK: Shared helpers

    private func parseTitle(_ title: String) -> (name: String, number: Int) {
        let parts = title.components(separatedBy: " #")
        var rawName = parts.first?.trimmingCharacters(in: .whitespaces) ?? ""
        rawName = rawName
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
            .trimmingCharacters(in: .whitespaces)
        let rest = parts.dropFirst().first ?? ""
        let numStr = rest.components(separatedBy: " -").first ?? ""
        return (rawName, Int(numStr.trimmingCharacters(in: .whitespaces)) ?? 0)
    }

    private func parseStats(table: Element) -> Stats {
        // Layout: header row = [empty colspan=2, HP, Attack, Defense, Sp. Attack, Sp. Defense, Speed]
        //         data row   = [Base Stats - Total: X (colspan=2), val, val, val, val, val, val]
        // Values are positional — HP first, Speed last.
        for row in (try? table.select("tr")) ?? Elements() {
            let cells = (try? row.select("td")) ?? Elements()
            let texts = (try? cells.map { try $0.text().trimmingCharacters(in: .whitespaces) }) ?? []
            guard let first = texts.first, first.contains("Base Stats") else { continue }
            let values = texts.dropFirst().compactMap { Int($0) }.filter { $0 > 0 && $0 <= 255 }
            guard values.count >= 6 else { continue }
            print("🔍✅ [Serebii] parseStats — HP=\(values[0]) Atk=\(values[1]) Def=\(values[2]) SpA=\(values[3]) SpD=\(values[4]) Spe=\(values[5])")
            return Stats(hp: values[0], attack: values[1], defense: values[2],
                         specialAttack: values[3], specialDefense: values[4], speed: values[5])
        }
        return Stats(hp: 0, attack: 0, defense: 0, specialAttack: 0, specialDefense: 0, speed: 0)
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
