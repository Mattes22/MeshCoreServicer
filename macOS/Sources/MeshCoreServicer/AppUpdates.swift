import Foundation
import Combine
import SwiftUI
import Sparkle

enum AppVersion {
    static var version: String { Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "vývojová" }
    static var build: String { Bundle.main.object(forInfoDictionaryKey:"CFBundleVersion") as? String ?? "vývojové" }
    static var display: String { "Verze \(version) · sestavení \(build)" }
}

@MainActor final class AppUpdates: NSObject, ObservableObject, SPUUpdaterDelegate {
    @Published var automaticChecks = UserDefaults.standard.object(forKey:"checkUpdatesAutomatically") as? Bool ?? true {
        didSet { UserDefaults.standard.set(automaticChecks,forKey:"checkUpdatesAutomatically"); controller?.updater.automaticallyChecksForUpdates = automaticChecks }
    }
    @Published private(set) var canCheck = false
    @Published private(set) var installing = false
    private var controller: SPUStandardUpdaterController?
    private var token: AnyCancellable?
    private weak var model: AppModel?
    func start(model: AppModel) {
        guard controller == nil, Bundle.main.bundleURL.pathExtension == "app" else { return }
        self.model = model
        let c = SPUStandardUpdaterController(startingUpdater:false,updaterDelegate:self,userDriverDelegate:nil)
        controller = c
        c.updater.automaticallyDownloadsUpdates = false
        c.updater.automaticallyChecksForUpdates = automaticChecks
        c.updater.updateCheckInterval = 24*3600
        token = c.updater.publisher(for:\.canCheckForUpdates).sink { [weak self] in self?.canCheck = $0 }
        c.startUpdater()
    }
    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) { installing = false }
    func check() { controller?.checkForUpdates(nil) }
    func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        if model?.busy == true || model?.usbRepeater.busy == true || model?.usb.connecting == true { throw NSError(domain:"MeshCoreUpdates",code:1,userInfo:[NSLocalizedDescriptionKey:"Nejprve dokončete probíhající operaci s companionem nebo repeaterem."]) }
    }
    func updater(_ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem, untilInvokingBlock installHandler: @escaping () -> Void) -> Bool {
        installing = true
        model?.stopMonitoring()
        Task { [weak self] in
            guard let self else { return }
            // Finish an already sent LoRa operation; never interrupt it halfway.
            while self.model?.busy == true || self.model?.usbRepeater.busy == true || self.model?.usb.connecting == true { try? await Task.sleep(nanoseconds:100_000_000) }
            self.model?.disconnectAll()
            await self.model?.messages.flush(); await self.model?.operations.flush()
            installHandler()
        }
        return true
    }
}
struct UpdateSettingsSection: View {
    @ObservedObject var updates: AppUpdates
    var body: some View {
        Section("Aktualizace") {
            Toggle("Automaticky zjišťovat nové verze",isOn:$updates.automaticChecks)
            Button("Zkontrolovat aktualizace…") { updates.check() }.disabled(!updates.canCheck || updates.installing)
            Text("Kontrola probíhá přes HTTPS na servicer.zavadilmatej.cz. Stažení a instalace vyžadují potvrzení. Je-li dostupná podepsaná rozdílová aktualizace pro vaši verzi, stáhnou se jen její změny. Když rozdíl nelze bezpečně použít, Sparkle nabídne úplný podepsaný balíček. Po instalaci se aplikace restartuje; diagnostické měření a přihlášení správce se neobnoví.").font(.caption).foregroundStyle(.secondary)
        }
    }
}
