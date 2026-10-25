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
public sealed class BleTransport(Dispatcher dispatcher) : IMeshTransport, IDisposable
{
    public event Action<byte[]>? Received;
    public event Action? Disconnected;
    public event Action? Changed;
    public Func<PairingPrompt, Task<string?>>? PairingInteraction { get; set; }
    private bool pairingBusy;
    public bool IsPairing => pairingBusy;
    public ObservableCollection<BleDevice> Devices { get; } = new();
    public string State { get; private set; } = "Odpojeno";
    public bool Ready => tx != null && rx != null;
    public bool Scanning => watcher?.Status == BluetoothLEAdvertisementWatcherStatus.Started;
    public int MaximumWriteLength => Math.Min(176, Math.Max(0, (session?.MaxPduSize ?? 23) - 3));
    private BluetoothLEAdvertisementWatcher? watcher;
    private BluetoothLEDevice? device;
    private GattSession? session;
    private GattDeviceService? service;
    private GattCharacteristic? rx, tx;
    private int generation;
    private readonly System.Collections.Generic.Dictionary<ulong, string> advertisedNames = new();
    private readonly System.Collections.Generic.HashSet<ulong> compatibleAddresses = new();
    private readonly SemaphoreSlim connecting = new(1, 1);
    private void Status(string value) { State = value; Changed?.Invoke(); }
    private static void Success(GattCommunicationStatus result)
    {
        if (result == GattCommunicationStatus.Success) return;
        throw new MeshException(result == GattCommunicationStatus.AccessDenied ? "Windows odmítl přístup. Zkontrolujte oprávnění Bluetooth a systémové párování (PIN z displeje zařízení)." : result == GattCommunicationStatus.Unreachable ? "Companion není dostupný. Přibližte jej a odpojte MeshCore aplikaci v telefonu; BLE může být obsazené." : "Chyba GATT protokolu; zkuste obnovit BLE spojení.");
    }
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
    public void StopScan() { if (watcher == null) return; watcher.Received -= Advertisement; watcher.Stopped -= WatcherStopped; watcher.Stop(); watcher = null; Changed?.Invoke(); }
    public async Task Pair(ulong address)
    {
        if (pairingBusy || Ready) throw new MeshException("Odpojte companion a dokončete předchozí párování.");
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
    public async Task Connect(ulong address)
    {
        if (pairingBusy) throw new MeshException("Nejprve dokončete systémové párování.");
        if (!await connecting.WaitAsync(0)) throw new MeshException("Připojení již probíhá.");
        Disconnect(); var epoch = generation; StopScan(); Status("Připojuji companion…");
        try
        {
            var candidate = await AwaitNative(BluetoothLEDevice.FromBluetoothAddressAsync(address).AsTask(), d => d?.Dispose());
            if (candidate == null) throw new MeshException("Companion není dostupný nebo Windows odmítl oprávnění Bluetooth.");
            if (epoch != generation) { candidate.Dispose(); throw new OperationCanceledException(); }
            device = candidate;
            var access = await device.RequestAccessAsync(); if (epoch != generation) throw new OperationCanceledException(); if (access != DeviceAccessStatus.Allowed) throw new MeshException("Přístup Bluetooth není povolen: " + access + ". Povolte jej v Nastavení Windows; při požadavku zařízení proveďte systémové párování.");
            var nativeSession = await GattSession.FromDeviceIdAsync(device.BluetoothDeviceId);
            if (epoch != generation) { nativeSession?.Dispose(); throw new OperationCanceledException(); }
            session = nativeSession ?? throw new MeshException("Windows neposkytl GATT relaci."); if (session.CanMaintainConnection) session.MaintainConnection = true;
            var services = await AwaitNative(device.GetGattServicesForUuidAsync(Codec.Service, BluetoothCacheMode.Uncached).AsTask(), r => { foreach (var s in r.Services) s.Dispose(); });
            if (epoch != generation) { foreach (var s in services.Services) s.Dispose(); throw new OperationCanceledException(); }
            Success(services.Status); service = services.Services.FirstOrDefault() ?? throw new MeshException("Zařízení neposkytuje MeshCore Nordic UART službu."); foreach (var s in services.Services.Skip(1)) s.Dispose();
            var chars = await service.GetCharacteristicsAsync(BluetoothCacheMode.Uncached).AsTask().WaitAsync(TimeSpan.FromSeconds(20)); Success(chars.Status);
            if (epoch != generation) throw new OperationCanceledException();
            rx = chars.Characteristics.FirstOrDefault(c => c.Uuid == Codec.Rx && c.CharacteristicProperties.HasFlag(GattCharacteristicProperties.Write));
            tx = chars.Characteristics.FirstOrDefault(c => c.Uuid == Codec.Tx && c.CharacteristicProperties.HasFlag(GattCharacteristicProperties.Notify));
            if (rx == null || tx == null) throw new MeshException("Chybí zapisovací RX nebo notifikační TX charakteristika.");
            tx.ValueChanged += ValueChanged;
            Success(await tx.WriteClientCharacteristicConfigurationDescriptorAsync(GattClientCharacteristicConfigurationDescriptorValue.Notify).AsTask().WaitAsync(TimeSpan.FromSeconds(20)));
            for (int n = 0; n < 30 && MaximumWriteLength < 176; n++) { await Task.Delay(100); if (epoch != generation) throw new OperationCanceledException(); }
            if (MaximumWriteLength < 176) throw new MeshException("Windows nevyjednal BLE MTU pro celý rámec 176 bajtů (ATT MTU alespoň 179). Aktualizujte ovladač adaptéru a firmware; pakety se nesmějí dělit jako sériový proud.");
            device.ConnectionStatusChanged += ConnectionChanged; Status("BLE připojeno · ověřuji MeshCore protokol");
        }
        catch { if (epoch == generation) Disconnect(); throw; }
        finally { connecting.Release(); }
    }
    // Some WinRT operations cannot actually be cancelled. Dispose late results
    // after our deadline instead of adopting objects into a newer connection.
    private static async Task<T> AwaitNative<T>(Task<T> operation, Action<T> discard)
    {
        try { return await operation.WaitAsync(TimeSpan.FromSeconds(20)); }
        catch
        {
            _ = operation.ContinueWith(t => { if (t.Status == TaskStatus.RanToCompletion) discard(t.Result); }, CancellationToken.None, TaskContinuationOptions.ExecuteSynchronously, TaskScheduler.Default);
            throw;
        }
    }
    private void ConnectionChanged(BluetoothLEDevice sender, object args)
    { dispatcher.BeginInvoke(() => { if (ReferenceEquals(sender, device) && sender.ConnectionStatus == BluetoothConnectionStatus.Disconnected) Disconnect(); }); }
    private void ValueChanged(GattCharacteristic sender, GattValueChangedEventArgs e)
    {
        byte[] bytes = new byte[e.CharacteristicValue.Length]; using (var reader = DataReader.FromBuffer(e.CharacteristicValue)) reader.ReadBytes(bytes);
        dispatcher.BeginInvoke(() => { if (ReferenceEquals(sender, tx)) Received?.Invoke(bytes); });
    }
    public async Task WriteAsync(byte[] frame, CancellationToken cancellation = default)
    {
        var characteristic = rx ?? throw new MeshException("BLE není připojeno."); Codec.BleFrame(frame, MaximumWriteLength);
        using var writer = new DataWriter(); writer.WriteBytes(frame);
        var result = await characteristic.WriteValueWithResultAsync(writer.DetachBuffer(), GattWriteOption.WriteWithResponse).AsTask(cancellation); Success(result.Status);
    }
    public void Disconnect()
    {
        generation++; if (tx != null) tx.ValueChanged -= ValueChanged; if (device != null) device.ConnectionStatusChanged -= ConnectionChanged;
        tx = rx = null; service?.Dispose(); service = null; if (session != null) { if (session.CanMaintainConnection) session.MaintainConnection = false; session.Dispose(); } session = null; device?.Dispose(); device = null; Status("Odpojeno"); Disconnected?.Invoke();
    }
    public void Dispose() { StopScan(); Disconnect(); }
}
