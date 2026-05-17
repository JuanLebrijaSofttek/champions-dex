import Foundation

enum AppState: Equatable{
    case launching
    case noDataOffline
    case ready
    case rosterUpdateAvailable(newSlugs: [String])
    case downloadingRoster
}
