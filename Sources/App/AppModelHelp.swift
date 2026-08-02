import Foundation

extension AppModel {
    func presentUsageAndUpdates(section: UsageAndUpdatesSection = .help) {
        requestedUsageAndUpdatesSection = section
        usageAndUpdatesWindowPresenter?()
    }
}
