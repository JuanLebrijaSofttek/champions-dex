# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands

```bash
# Build for simulator (use an available simulator from the list)
xcodebuild -scheme ChampionsDex -destination 'platform=iOS Simulator,name=iPhone 17 Pro'

# Check available destinations
xcodebuild -scheme ChampionsDex -showdestinations

# Build check only (no run)
xcodebuild -scheme ChampionsDex -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

No test targets exist in this project. Verify correctness by building and running on a real device (`id:00008110-001C4D3C1E0A801E, name:Lebrija13Pro`) or a simulator.

## Architecture

**Deployment target:** iOS 26.2 · **Swift:** 5.0 · **Dependency:** SwiftSoup 2.13.5 (HTML parsing)

### State machine, not navigation

`ContentView` drives the app through `AppViewModel.appState` (an enum: `.launching`, `.downloadingRoster`, `.noDataOffline`, `.ready`). When `.ready`, a three-tab `TabView` is shown. There is no router or coordinator — tab selection is the only top-level navigation.

### Data flow

```
Serebii.net (HTML) → SerebiiService (SwiftSoup) → PersistenceManager (disk) → AppViewModel (@Observable) → Views
```

- `AppViewModel` is `@Observable @MainActor`. Views observe it directly — no `@EnvironmentObject`, no `@ObservedObject`.
- Details are loaded lazily: `viewModel.loadDetail(slug:)` checks memory → disk → network in that order. Details are only fetched when a user navigates to a Pokémon or selects one in the Team Coverage tab.
- Icons (PNG) and details (JSON) are cached separately under `Application Support/ChampionsDex/icons/` and `.../details/`.

### Key models

- `RosterEntry` — lightweight list entry (`id` slug, `name`, `iconCached`). Always in memory after launch.
- `PokemonDetail` — full scraped data per Pokémon, loaded on demand. Contains an array of `PokemonForm` (handles Mega, regional, and alternate forms).
- `PokemonForm.typeMatchups: [String: Double]` — **defensive** matchup map. Keys are the 18 type names; values are damage multipliers (0.0, 0.25, 0.5, 2.0, 4.0). Neutral (×1) entries are **omitted** — treat a missing key as 1.0.

### Serebii scraping quirks

`SerebiiService` scrapes `serebii.net/pokedex-sv/<slug>`. The HTML structure is fragile — type matchup tables are identified by having exactly 18 cells. Multi-form Pokémon produce multiple matchup tables (one per form), parsed in order. If Serebii changes its markup, the parser in `parseAllMatchupMaps` (and surrounding helpers) is the first place to check.

### Team Coverage tab

`TeamCoverageView` uses a `ZStack` with two layers:
1. A `ScrollView` containing 6 slot pickers and the 18-row defensive coverage table.
2. A floating autocomplete overlay, positioned via a `SlotFrameKey` `PreferenceKey` that bubbles each slot row's frame up from inside the `ScrollView` to the `ZStack` layer.

The coordinate space `"teamView"` is applied to the `ZStack` so that `GeometryReader` frames inside the scroll content and the overlay offsets share the same origin.
