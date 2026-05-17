import Foundation

enum AppState: Equatable {
    case launching
    case noDataOffline
    case loadingDetails
    case ready
    case rosterUpdateAvailable(newSlugs: [String])
}
