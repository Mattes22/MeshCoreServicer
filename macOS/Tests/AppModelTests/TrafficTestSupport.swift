import Foundation
import MeshCoreKit

@MainActor extension ServiceTrafficGovernor {
    static func testing() -> ServiceTrafficGovernor {
        final class Clock { var date = Date(timeIntervalSince1970:1800000000) }
        let clock = Clock()
        return ServiceTrafficGovernor(now:{clock.date},delay:{clock.date = clock.date.addingTimeInterval($0)})
    }
}
