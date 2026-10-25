import SwiftUI

enum AppSettingsTab: Hashable { case general, console }

struct AppSettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var preferences: AppPreferences
    @ObservedObject var notifications: NotificationCoordinator
    @State var tab: AppSettingsTab = .general
    @State private var requesting = false
    var body: some View {
        VStack(spacing:12) {
            Picker("Nastavení",selection:$tab) {
                Text("Obecné").tag(AppSettingsTab.general)
                Text("Konzole").tag(AppSettingsTab.console)
            }.pickerStyle(.segmented).labelsHidden().frame(width:280)
            if tab == .general { general } else { console }
        }.padding().frame(width:600,height:640).background(.background).task { await notifications.refreshStatus() }
    }
    private var general: some View {
        Form {
            Section("Zprávy a oznámení") {
                Toggle("Systémová oznámení nových zpráv",isOn:Binding(get:{ preferences.notifications },set:{ value in
                    if !value { preferences.notifications = false; notifications.clearDelivered(); return }
                    requesting = true
                    Task { preferences.notifications = await notifications.requestPermission(); requesting = false }
                })).disabled(requesting)
                if requesting { ProgressView().controlSize(.small) }
                Text(notifications.status).font(.caption).foregroundStyle(.secondary)
                Toggle("Přehrát zvuk",isOn:$preferences.sound)
                Toggle("Zobrazovat jméno a text zprávy v oznámení",isOn:$preferences.showMessageText).onChange(of:preferences.showMessageText) { _,value in if !value { notifications.clearDelivered() } }
                Text("Ve výchozím stavu je obsah skrytý. Historické zprávy při připojení nevyvolají oznámení. Jednotlivé kanály ztišíte v záhlaví konverzace. Odznak v Docku počítá všechny nepřečtené zprávy.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Bluetooth") {
                Toggle("Obnovovat nečekaně přerušené spojení",isOn:$preferences.autoReconnect)
                Text("Pouze k companionu zvolenému během tohoto běhu aplikace. Prodlevy 1–30 sekund. Ruční odpojení automatické pokusy ukončí. Párovací chybu je nutné vyřešit ručně. Obnovení neopakuje vysílání ani přihlášení správce.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Běh na pozadí") {
                Text("Zavřené nebo minimalizované okno aplikaci neukončuje. Příjem a oznámení vyžadují běžící aplikaci a BLE spojení. Během spánku Macu se příjem negarantuje. Diagnostické měření se při spánku, odpojení nebo chybě zastaví.").font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
    }
    private var console: some View {
        Form {
            Section("Konzole") {
                Text(model.library.profile.map{"Volby pro profil: \($0.displayName)"} ?? "Bez aktivního companionu upravujete výchozí volby pro nové profily. Uložené profily obnoví vlastní nastavení.").font(.caption).foregroundStyle(.secondary)
                Toggle("Našeptávat příkazy při psaní",isOn:$preferences.consoleSuggestions)
                Toggle("Zobrazovat syntaxi a nápovědu příkazu",isOn:$preferences.consoleHelp)
                Toggle("Doplňovat také z místní historie",isOn:$preferences.consoleHistory)
                Toggle("Nabízet příkazy měnící nastavení a vysílání",isOn:$preferences.consoleChanges)
                Toggle("Odesílat příkaz klávesou Enter",isOn:$preferences.consoleEnterSends)
                Text("Tab pouze vyplní vybraný návrh. Šipky vybírají návrhy; po Escape procházejí historii. Našeptávání běží místně, bez internetu. Historie zůstává jen v paměti a vynechává citlivé příkazy. Katalog vychází z firmwaru v1.18; skutečná podpora závisí na vzdáleném uzlu.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Ovládání") {
                Text("Tab nebo kliknutí vloží návrh bez odeslání. Escape zavře nabídku. Bez nabídky šipky procházejí historii; rozepsaný text se zachová. Příkazy i odpovědi se zpracovávají postupně.").font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
    }
}
