import AppKit
import UserNotifications
import MeshCoreKit

struct MessageNotification: Equatable {
    let id: String
    let title: String
    let body: String
    let account: String
    let conversation: String
    @MainActor static func make(_ record: ChatRecord, account: String, preferences: AppPreferences, live: Bool) -> Self? {
        guard live, preferences.notifications, !record.outgoing, !record.seen, !preferences.isMuted(account:account,conversation:record.conversationID) else { return nil }
        return Self(id:record.id.uuidString,title:preferences.showMessageText ? record.title : "MeshCore · nová zpráva",body:preferences.showMessageText ? String(record.text.prefix(240)) : "Otevřete konverzaci v aplikaci.",account:account,conversation:record.conversationID)
    }
}
@MainActor final class NotificationCoordinator: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    @Published private(set) var status = "Oznámení jsou vypnutá"
    private var reconciliation = UUID()
    var onOpen: ((String,String)->Void)?
    private let center: UNUserNotificationCenter?
    init(systemEnabled: Bool = false) {
        center = systemEnabled ? UNUserNotificationCenter.current() : nil
        super.init(); center?.delegate = self
    }
    func requestPermission() async -> Bool {
        guard let center else { return false }
        do { let granted = try await center.requestAuthorization(options:[.alert,.sound,.badge]); await refreshStatus(); return granted }
        catch { status = "Oprávnění oznámení se nepodařilo získat."; return false }
    }
    func refreshStatus() async {
        guard let center else { return }
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized,.provisional: status = "Systémová oznámení jsou povolená"
        case .denied: status = "Oznámení macOS jsou zakázaná. Povolte je v Nastavení systému → Oznámení."
        default: status = "Povolení oznámení zatím nebylo udělené"
        }
    }
    func deliver(_ notice: MessageNotification, sound: Bool) {
        guard let center else { return }
        let content = UNMutableNotificationContent(); content.title = notice.title; content.body = notice.body
        content.userInfo = ["account":notice.account,"conversation":notice.conversation]
        if sound { content.sound = .default }
        center.add(UNNotificationRequest(identifier:notice.id,content:content,trigger:nil)) { [weak self] error in
            if error != nil { Task { @MainActor in self?.status = "Oznámení se nepodařilo zobrazit." } }
        }
    }
    func clearDelivered() { reconciliation = UUID(); center?.removeAllDeliveredNotifications(); center?.removeAllPendingNotificationRequests() }
    func setUnread(_ count: Int) { guard center != nil else { return }; NSApp?.dockTile.badgeLabel = count == 0 ? nil : String(count) }
    func clearConversation(account: String,conversation: String) {
        center?.getDeliveredNotifications { [weak self] delivered in
            let ids = delivered.filter { $0.request.content.userInfo["account"] as? String == account && $0.request.content.userInfo["conversation"] as? String == conversation }.map{$0.request.identifier}
            Task { @MainActor in self?.center?.removeDeliveredNotifications(withIdentifiers:ids) }
        }
    }
    func removeRead(account: String, unread: Set<String>) {
        let token = UUID(); reconciliation = token
        center?.getDeliveredNotifications { [weak self] delivered in
            let ids = delivered.filter { notice in
                notice.request.content.userInfo["account"] as? String == account && !unread.contains(notice.request.content.userInfo["conversation"] as? String ?? "")
            }.map{ $0.request.identifier }
            Task { @MainActor in if self?.reconciliation == token { self?.center?.removeDeliveredNotifications(withIdentifiers:ids) } }
        }
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions)->Void) { completionHandler(notification.request.content.sound == nil ? [.banner,.list] : [.banner,.list,.sound]) }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping ()->Void) {
        let data = response.notification.request.content.userInfo
        let account = data["account"] as? String, conversation = data["conversation"] as? String
        Task { @MainActor [weak self] in if let account, let conversation { self?.onOpen?(account,conversation) } }
        completionHandler()
    }
}
