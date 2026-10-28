using System;
using System.Collections.ObjectModel;
using System.Collections.Generic;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Threading;
using MeshCore.Core;
using Windows.Devices.Bluetooth;
using Windows.Devices.Bluetooth.Advertisement;
using Windows.Devices.Bluetooth.GenericAttributeProfile;
using Windows.Devices.Enumeration;
using Windows.Devices.Radios;
using Windows.Storage.Streams;

namespace MeshCore.Windows;

public sealed record BleDevice(ulong Address, string Name, short Rssi)
{
    public string Display => $"{Name} · BLE RSSI {Rssi} dBm (advertisement do PC)";
    public override string ToString() => Display;
}
public sealed record PairingPrompt(string Kind, string Pin);
public sealed class BleTransport : IMeshTransport, IBleDiagnosticsSource, IDisposable
{
    public event Action<byte[]>? Received;
    public event Action? Disconnected;
    public event Action? Changed;
    public Func<PairingPrompt, Task<string?>>? PairingInteraction { get; set; }
    private bool pairingBusy;
    public bool IsPairing => pairingBusy;
    public ObservableCollection<BleDevice> Devices { get; } = new();
    public string State { get; private set; } = "Odpojeno";
    private readonly Dispatcher dispatcher;
    private readonly BleConnectionFlow connection = new();
    public BleConnectionJournal ConnectionDiagnostics => connection.Journal;
    public string? ConnectionError => connection.LastFailure?.Message;
    public bool IsConnecting => connection.Connecting;
    public bool Ready => connection.TransportReady;
    public bool Scanning => watcher?.Status == BluetoothLEAdvertisementWatcherStatus.Started;
    public int MaximumWriteLength => (connection.Driver as NativeBleConnection)?.MaximumWriteLength ?? 20;
    private BluetoothLEAdvertisementWatcher? watcher;
    public BleTransport(Dispatcher dispatcher)
    {
        this.dispatcher = dispatcher;
        connection.ResetTransport += () => Disconnected?.Invoke();
        connection.Changed += () => Status(connection.Connecting ? "Připojuji · " + BleText.Stage(connection.Stage) + "…" : connection.LastFailure != null ? "Připojení selhalo · " + connection.LastFailure.Id : Ready ? "BLE připojeno · MeshCore ověřeno" : "Odpojeno");
    }
    private readonly System.Collections.Generic.Dictionary<ulong, string> advertisedNames = new();
    private readonly System.Collections.Generic.HashSet<ulong> compatibleAddresses = new();
    private void Status(string value) { State = value; Changed?.Invoke(); }
    public async Task Scan()
    {
        StopScan(); var adapter = await BluetoothAdapter.GetDefaultAsync();
        if (adapter == null || !adapter.IsLowEnergySupported) throw new MeshException("Tento počítač nemá dostupný Bluetooth LE adaptér.");
        var radio = await adapter.GetRadioAsync(); if (radio != null && radio.State != RadioState.On) throw new MeshException("Bluetooth je vypnutý. Zapněte jej v Nastavení Windows.");
        Devices.Clear(); advertisedNames.Clear(); compatibleAddresses.Clear(); watcher = new() { ScanningMode = BluetoothLEScanningMode.Active };
        // Service and local name may be split between advertisement and scan response.
        // Observe both, but expose only addresses that advertised the exact NUS UUID.
        watcher.Received += Advertisement; watcher.Stopped += WatcherStopped; watcher.Start(); Status("Hledám kompatibilní BLE companiony…");
    }
    private void Advertisement(BluetoothLEAdvertisementWatcher sender, BluetoothLEAdvertisementReceivedEventArgs e)
    {
        var address = e.BluetoothAddress; var name = e.Advertisement.LocalName; var rssi = e.RawSignalStrengthInDBm; bool compatible = e.Advertisement.ServiceUuids.Contains(Codec.Service);
        dispatcher.BeginInvoke(() => { if (!ReferenceEquals(sender, watcher)) return;
            if (!string.IsNullOrEmpty(name)) { if (advertisedNames.Count >= 512 && !advertisedNames.ContainsKey(address)) advertisedNames.Remove(advertisedNames.Keys.First()); advertisedNames[address] = name; }
            if (compatible) compatibleAddresses.Add(address);
            if (!compatibleAddresses.Contains(address)) return;
            if (string.IsNullOrEmpty(name)) name = advertisedNames.GetValueOrDefault(address, "");
            var old = Devices.FirstOrDefault(d => d.Address == address); var item = new BleDevice(address, string.IsNullOrEmpty(name) ? old?.Name ?? "MeshCore / Nordic UART zařízení" : name, rssi); if (old == null) Devices.Add(item); else Devices[Devices.IndexOf(old)] = item; Changed?.Invoke(); });
    }
    private void WatcherStopped(BluetoothLEAdvertisementWatcher sender, BluetoothLEAdvertisementWatcherStoppedEventArgs e)
    { dispatcher.BeginInvoke(() => { if (ReferenceEquals(sender, watcher) && e.Error != BluetoothError.Success) Status("Skenování zastaveno: " + e.Error + ". Zkontrolujte Bluetooth a oprávnění Windows."); }); }
    public void StopScan()
    {
        var old = watcher; watcher = null; if (old == null) return;
        try { old.Received -= Advertisement; old.Stopped -= WatcherStopped; }
        finally { try { old.Stop(); } finally { Changed?.Invoke(); } }
    }
    public async Task Pair(ulong address)
    {
        if (pairingBusy || Ready || IsConnecting) throw new MeshException("Odpojte companion a dokončete předchozí párování.");
        pairingBusy = true; Status("Systémové párování Bluetooth…");
        try
        {
            using var candidate = await BluetoothLEDevice.FromBluetoothAddressAsync(address) ?? throw new MeshException("Zařízení není dostupné.");
            var pairing = candidate.DeviceInformation.Pairing;
            if (pairing.IsPaired) { Status("Zařízení je již systémově spárováno"); return; }
            var custom = pairing.Custom; custom.PairingRequested += PairingRequested;
            try
            {
                var result = await custom.PairAsync(DevicePairingKinds.ConfirmOnly | DevicePairingKinds.ProvidePin | DevicePairingKinds.DisplayPin | DevicePairingKinds.ConfirmPinMatch, DevicePairingProtectionLevel.Default);
                if (result.Status is not (DevicePairingResultStatus.Paired or DevicePairingResultStatus.AlreadyPaired)) throw new MeshException("Systémové párování nedokončeno: " + result.Status + ". Použijte Nastavení Windows → Bluetooth; PIN musí pocházet ze zařízení.");
                Status("Systémové párování dokončeno");
            }
            finally { custom.PairingRequested -= PairingRequested; }
        }
        finally { pairingBusy = false; Changed?.Invoke(); }

    }
    private async void PairingRequested(DeviceInformationCustomPairing sender, DevicePairingRequestedEventArgs args)
    {
        var deferral = args.GetDeferral();
        try
        {
            var kind = args.PairingKind; var pin = kind is DevicePairingKinds.DisplayPin or DevicePairingKinds.ConfirmPinMatch ? args.Pin : "";
            var answer = await dispatcher.InvokeAsync(async () => PairingInteraction == null ? null : await PairingInteraction(new(kind.ToString(), pin))).Task.Unwrap();
            if (answer == null) return;
            if (args.PairingKind == DevicePairingKinds.ProvidePin) args.Accept(answer); else args.Accept();
        }
        catch { _ = dispatcher.BeginInvoke(() => Status("Párování nebylo dokončeno; zkuste Nastavení Windows.")); }
        finally { deferral.Complete(); }
    }
    public async Task Connect(ulong address, Func<Task> initialize)
    {
        if (pairingBusy) throw new MeshException("Nejprve dokončete systémové párování.");
        await connection.Connect(new NativeBleConnection(address, dispatcher, connection, StopScan, bytes => Received?.Invoke(bytes)), initialize);
    }
    public Task WriteAsync(byte[] frame, CancellationToken cancellation = default)
    {
        if (!Ready || connection.Driver is not NativeBleConnection native) throw new MeshException("BLE není připojeno.");
        return native.Write(frame, cancellation);
    }
    public void Disconnect(BleCloseReason reason = BleCloseReason.User) => connection.Disconnect(reason);
    public void Dispose() { try { StopScan(); } finally { Disconnect(BleCloseReason.Shutdown); } }
}
