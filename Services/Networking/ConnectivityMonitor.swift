import Foundation
import Network
import Observation

/// Tracks whether the device has a usable network path, so the UI can show an
/// offline state and refresh again when connectivity returns. Uses
/// `NWPathMonitor`, which needs no entitlement or permission.
@MainActor
@Observable
final class ConnectivityMonitor {
    private(set) var isOnline = true

    @ObservationIgnored private var monitor: NWPathMonitor?

    func start() {
        guard self.monitor == nil else { return }
        let newMonitor = NWPathMonitor()
        newMonitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in
                self?.isOnline = online
            }
        }
        newMonitor.start(queue: DispatchQueue(label: "by.thekammy.pwned.connectivity"))
        self.monitor = newMonitor
    }
}
