import Foundation
import Combine
import MeshCoreKit

@MainActor final class AppPreferences: ObservableObject {
    private let defaults: UserDefaults?
    var onProfileChange: (() -> Void)?
    private var applyingProfile = false
    private func profileChanged() { if !applyingProfile { onProfileChange?() } }
    @Published var autoReconnect = true { didSet { defaults?.set(autoReconnect,forKey:"autoReconnect"); profileChanged() } }
    @Published var notifications = false { didSet { defaults?.set(notifications,forKey:"notifications") } }
    @Published var sound = true { didSet { defaults?.set(sound,forKey:"notificationSound") } }
    @Published var showMessageText = false { didSet { defaults?.set(showMessageText,forKey:"notificationText") } }
    @Published var mutedConversations: Set<String> = [] { didSet { defaults?.set(Array(mutedConversations),forKey:"mutedConversations") } }
    @Published var consoleSuggestions = true { didSet { defaults?.set(consoleSuggestions,forKey:"consoleSuggestions"); profileChanged() } }
    @Published var consoleHelp = true { didSet { defaults?.set(consoleHelp,forKey:"consoleHelp"); profileChanged() } }
    @Published var consoleHistory = true { didSet { defaults?.set(consoleHistory,forKey:"consoleHistory"); profileChanged() } }
    @Published var consoleChanges = false { didSet { defaults?.set(consoleChanges,forKey:"consoleChanges"); profileChanged() } }
    @Published var consoleEnterSends = true { didSet { defaults?.set(consoleEnterSends,forKey:"consoleEnterSends"); profileChanged() } }
    init(defaults: UserDefaults? = nil) {
        self.defaults = defaults
        if let defaults {
            autoReconnect = defaults.object(forKey:"autoReconnect") as? Bool ?? true
            notifications = defaults.bool(forKey:"notifications")
            sound = defaults.object(forKey:"notificationSound") as? Bool ?? true
            showMessageText = defaults.bool(forKey:"notificationText")
            mutedConversations = Set(defaults.stringArray(forKey:"mutedConversations") ?? [])
            consoleSuggestions = defaults.object(forKey:"consoleSuggestions") as? Bool ?? true
            consoleHelp = defaults.object(forKey:"consoleHelp") as? Bool ?? true
            consoleHistory = defaults.object(forKey:"consoleHistory") as? Bool ?? true
            consoleChanges = defaults.bool(forKey:"consoleChanges")
            consoleEnterSends = defaults.object(forKey:"consoleEnterSends") as? Bool ?? true
        }
    }
    var deviceOptions: DevicePreferences {
        var result = DevicePreferences()
        result.autoReconnect = autoReconnect; result.suggestions = consoleSuggestions; result.help = consoleHelp
        result.history = consoleHistory; result.changes = consoleChanges; result.enterSends = consoleEnterSends
        return result
    }
    func apply(_ options: DevicePreferences) {
        applyingProfile = true
        autoReconnect = options.autoReconnect; consoleSuggestions = options.suggestions; consoleHelp = options.help
        consoleHistory = options.history; consoleChanges = options.changes; consoleEnterSends = options.enterSends
        applyingProfile = false
    }
    func isMuted(account: String, conversation: String) -> Bool { mutedConversations.contains(account+"/"+conversation) }
    func mute(_ mute: Bool,account: String,conversation: String) {
        let key = account+"/"+conversation
        if mute { mutedConversations.insert(key) } else { mutedConversations.remove(key) }
    }
}
