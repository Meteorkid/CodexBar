import CodexBarCore
import Foundation

extension UsageStore {
    func persistWidgetSnapshot(reason: String) {
        self.widgetSnapshotBuilder.persistWidgetSnapshot(reason: reason)
    }
}
