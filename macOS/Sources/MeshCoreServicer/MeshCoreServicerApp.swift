import SwiftUI
import AppKit
import MeshCoreKit

@main struct MeshCoreServicerApp: App {
    @NSApplicationDelegateAdaptor(AppLifecycle.self) private var lifecycle
    @StateObject private var model = AppModel()
    var body: some Scene {
        WindowGroup("MeshCore Servicer",id:"main") { MainAppWindow(model:model,lifecycle:lifecycle).frame(minWidth:1080,minHeight:740) }
            .defaultSize(width:1240,height:850)
            .commands { CommandGroup(replacing:.newItem) {} }
        Settings { AppSettingsView(model:model,preferences:model.preferences,notifications:model.notifications) }
    }
}
private struct MainAppWindow: View {
    @ObservedObject var model: AppModel
    let lifecycle: AppLifecycle
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        ContentView(model:model,ble:model.ble)
            .background(MainWindowProbe())
            .onAppear {
                lifecycle.model = model; lifecycle.openingWindow = false; lifecycle.observe()
                model.openMainWindow = { lifecycle.showWindow { openWindow(id:"main") } }
                lifecycle.updatePresence()
            }
    }
}
private struct MainWindowProbe: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { Probe() }
    func updateNSView(_ nsView: NSView,context: Context) {}
    final class Probe: NSView { override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); window?.identifier = NSUserInterfaceItemIdentifier("meshcore-main") } }
}
@MainActor final class AppLifecycle: NSObject, NSApplicationDelegate {
    weak var model: AppModel?
    private var observers: [NSObjectProtocol] = []
    var openingWindow = false
    func showWindow(create: ()->Void) {
        if let window = NSApp.windows.first(where:{ $0.identifier?.rawValue == "meshcore-main" && ($0.isVisible || $0.isMiniaturized) }) {
            window.deminiaturize(nil); window.makeKeyAndOrderFront(nil)
        } else if !openingWindow {
            openingWindow = true; create()
            Task { [weak self] in try? await Task.sleep(nanoseconds:500_000_000); self?.openingWindow = false }
        }
        NSApp.activate(ignoringOtherApps:true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication,hasVisibleWindows flag: Bool) -> Bool { if !flag { model?.openMainWindow?() }; return true }
    func observe() {
        guard observers.isEmpty else { return }
        for name in [NSApplication.didBecomeActiveNotification,NSApplication.didResignActiveNotification,NSWindow.didMiniaturizeNotification,NSWindow.didDeminiaturizeNotification,NSWindow.didChangeOcclusionStateNotification,NSWindow.willCloseNotification] {
            observers.append(NotificationCenter.default.addObserver(forName:name,object:nil,queue:.main) { [weak self] _ in Task { @MainActor in await Task.yield(); self?.updatePresence() } })
        }
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName:NSWorkspace.willSleepNotification,object:nil,queue:.main) { [weak self] _ in Task { @MainActor in self?.model?.ble.prepareForSleep(); self?.model?.stopMonitoring(); self?.model?.messages.readingAllowed = false } })
        observers.append(center.addObserver(forName:NSWorkspace.didWakeNotification,object:nil,queue:.main) { [weak self] _ in Task { @MainActor in self?.model?.ble.resumeAfterWake(); self?.updatePresence() } })
        Task { await model?.notifications.refreshStatus() }
    }
    func updatePresence() {
        model?.messages.readingAllowed = NSApp.isActive && NSApp.windows.contains { $0.identifier?.rawValue == "meshcore-main" && $0.isVisible && !$0.isMiniaturized && $0.occlusionState.contains(.visible) }
        model?.messages.markRead()
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model else { return .terminateNow }
        model.stopMonitoring(); model.ble.disconnect()
        Task { await model.messages.flush(); await model.operations.flush(); sender.reply(toApplicationShouldTerminate:true) }
        return .terminateLater
    }
}
