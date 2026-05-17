import Network
import Observation

@Observable final class NetworkMonitor {
    var isConnected: Bool = false
    private var hasReceivedInitialState = false

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")
    private var initialStateContinuation: CheckedContinuation<Bool, Never>?

    init() {
        print("📡⏳ [NetworkMonitor] Starting NWPathMonitor...")
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let connected = path.status == .satisfied
            print("📡\(connected ? "✅" : "❌") [NetworkMonitor] Path update — connected=\(connected)")
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isConnected = connected
                self.hasReceivedInitialState = true
                if let cont = self.initialStateContinuation {
                    print("📡✅ [NetworkMonitor] Resolving pending continuation — connected=\(connected)")
                    self.initialStateContinuation = nil
                    cont.resume(returning: connected)
                }
            }
        }
        monitor.start(queue: queue)
        print("📡⏳ [NetworkMonitor] Monitor started")
    }

    /// Returns the real connectivity state.
    /// If the first path update already fired, returns immediately.
    /// Otherwise waits up to 2 s for the callback, then falls back.
    func waitForInitialState(timeout: Duration = .seconds(2)) async -> Bool {
        if hasReceivedInitialState {
            print("📡✅ [NetworkMonitor] Initial state already known — connected=\(isConnected)")
            return isConnected
        }

        print("📡⏳ [NetworkMonitor] Waiting for first path update (up to 2 s)...")

        return await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                await withCheckedContinuation { cont in
                    Task { @MainActor [weak self] in
                        guard let self else { cont.resume(returning: false); return }
                        // Check again now that we're on MainActor — may have arrived
                        if self.hasReceivedInitialState {
                            print("📡✅ [NetworkMonitor] State arrived before continuation set — connected=\(self.isConnected)")
                            cont.resume(returning: self.isConnected)
                        } else {
                            self.initialStateContinuation = cont
                        }
                    }
                }
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                print("📡⏳ [NetworkMonitor] Timeout — falling back to isConnected=\(self.isConnected)")
                return self.isConnected
            }
            let result = await group.next()!
            group.cancelAll()
            print("📡✅ [NetworkMonitor] Resolved — connected=\(result)")
            return result
        }
    }

    deinit { monitor.cancel() }
}
