using System;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Threading;
using MeshCore.Core;
using Windows.Devices.Bluetooth;
using Windows.Devices.Bluetooth.GenericAttributeProfile;
using Windows.Devices.Enumeration;
using Windows.Storage.Streams;

namespace MeshCore.Windows;

// One owner per attempt. Late operations/events can only refer to this owner, never a newer connection.
internal sealed class NativeBleConnection(ulong address, Dispatcher dispatcher, BleConnectionFlow flow, Action beforeOpen, Action<byte[]> receive) : IBleConnectionDriver, IBleMtuSource
{
    private BluetoothLEDevice? device;
    private GattSession? session;
    private GattDeviceService? service;
    private GattCharacteristic? rx, tx;
    private volatile bool disposed;
    private bool observedConnection;
    private readonly TaskCompletionSource<bool> mtuReady = new(TaskCreationOptions.RunContinuationsAsynchronously);
    private Guid attempt;
    private readonly CancellationTokenSource owner = new();
    public int AttMtu => session?.MaxPduSize ?? 23;
    public int MaximumWriteLength => Math.Min(176, Math.Max(0, AttMtu - 3));
    private bool Current => !disposed && ReferenceEquals(flow.Driver, this);
    private async Task<T> Native<T>(Task<T> task, CancellationToken token, Action<T>? discard = null)
    {
        using var linked = CancellationTokenSource.CreateLinkedTokenSource(token, owner.Token);
        var stage = flow.Stage;
        return await BleNativeOperation.Await(task, linked.Token, discard,
            () => flow.Journal.Add(new(DateTimeOffset.UtcNow, attempt, stage, BleOutcome.LateResultDiscarded)),
            error => flow.Journal.Add(new(DateTimeOffset.UtcNow, attempt, stage, BleOutcome.LateFaultObserved, Failure: BleFailure.From(error, attempt, stage))));
    }
    private static void Gatt(GattCommunicationStatus status, byte? error)
    {
        if (status != GattCommunicationStatus.Success) throw new BleStepException(status == GattCommunicationStatus.AccessDenied ? BleReason.AccessDenied : BleReason.GattFailure, new((int)status, error));
    }
    public async Task<BleEvidence> Execute(BleStage stage, CancellationToken cancellation)
    {
        cancellation.ThrowIfCancellationRequested();
        if (attempt == Guid.Empty) attempt = flow.Attempt;
        switch (stage)
        {
            case BleStage.OpenDevice:
                beforeOpen();
                device = await Native(BluetoothLEDevice.FromBluetoothAddressAsync(address).AsTask(), cancellation, d => { if (d != null) Release(d.Dispose); }) ?? throw new BleStepException(BleReason.DeviceUnavailable);
                observedConnection = device.ConnectionStatus == BluetoothConnectionStatus.Connected;
                device.ConnectionStatusChanged += ConnectionChanged;
                return new();
            case BleStage.Access:
                var access = await Native(device!.RequestAccessAsync().AsTask(), cancellation);
                if (access != DeviceAccessStatus.Allowed) throw new BleStepException(BleReason.AccessDenied, new(AccessStatus: (int)access));
                return new(AccessStatus: (int)access);
            case BleStage.GattSession:
                session = await Native(GattSession.FromDeviceIdAsync(device!.BluetoothDeviceId).AsTask(), cancellation, value => Release(() => CloseSession(value))) ?? throw new BleStepException(BleReason.MissingSession);
                session.SessionStatusChanged += SessionChanged;
                session.MaxPduSizeChanged += MtuChanged;
                if (session.CanMaintainConnection) session.MaintainConnection = true;
                return new(Mtu: AttMtu);
            case BleStage.Service:
                // Enumerate once, then require the exact NUS UUID locally. The
                // UUID-filtered WinRT query failed with 0x80070016 in the report.
                // This uses the documented GATT enumeration path, without retry,
                // alternate UUIDs, pairing changes or MeshCore/LoRa writes.
                var services = await Native(device!.GetGattServicesAsync(BluetoothCacheMode.Uncached).AsTask(), cancellation, result => { foreach (var item in result.Services) Release(item.Dispose); });
                try
                {
                    Gatt(services.Status, services.ProtocolError);
                    service = services.Services.FirstOrDefault(s => s.Uuid == Codec.Service) ?? throw new BleStepException(BleReason.MissingService);
                }
                finally { foreach (var item in services.Services) if (!ReferenceEquals(item, service)) Release(item.Dispose); }
                return new((int)services.Status, services.ProtocolError);
            case BleStage.Characteristics:
                var chars = await Native(service!.GetCharacteristicsAsync(BluetoothCacheMode.Uncached).AsTask(), cancellation);
                Gatt(chars.Status, chars.ProtocolError);
                rx = chars.Characteristics.FirstOrDefault(c => c.Uuid == Codec.Rx);
                tx = chars.Characteristics.FirstOrDefault(c => c.Uuid == Codec.Tx);
                var properties = new BleEvidence((int)chars.Status, chars.ProtocolError, RxProperties: rx == null ? null : (int)rx.CharacteristicProperties, TxProperties: tx == null ? null : (int)tx.CharacteristicProperties);
                if (rx == null || tx == null || !rx.CharacteristicProperties.HasFlag(GattCharacteristicProperties.Write) || !tx.CharacteristicProperties.HasFlag(GattCharacteristicProperties.Notify))
                    throw new BleStepException(BleReason.MissingCharacteristics, properties);
                return properties;
            case BleStage.Notifications:
                tx!.ValueChanged += ValueChanged;
                var cccd = await Native(tx.WriteClientCharacteristicConfigurationDescriptorWithResultAsync(GattClientCharacteristicConfigurationDescriptorValue.Notify).AsTask(), cancellation);
                Gatt(cccd.Status, cccd.ProtocolError);
                return new((int)cccd.Status, cccd.ProtocolError);
            case BleStage.Mtu:
                if (AttMtu < 179)
                {
                    try { await mtuReady.Task.WaitAsync(TimeSpan.FromSeconds(15), cancellation); }
                    catch (TimeoutException) { throw new BleStepException(BleReason.MtuInsufficient, new(Mtu: AttMtu)); }
                }
                if (AttMtu < 179) throw new BleStepException(BleReason.MtuInsufficient, new(Mtu: AttMtu));
                return new(Mtu: AttMtu);
            default: throw new InvalidOperationException();
        }
    }
    private void MtuChanged(GattSession sender, object args)
    {
        Dispatch(() => { if (ReferenceEquals(sender, session) && sender.MaxPduSize >= 179) mtuReady.TrySetResult(true); }, BleStage.Mtu);
    }
    private void Dispatch(Action action, BleStage? eventStage = null)
    {
        if (dispatcher.HasShutdownStarted || dispatcher.HasShutdownFinished) return;
        try
        {
            dispatcher.BeginInvoke(() => {
                if (!Current) return;
                try { action(); }
                catch (Exception ex) { flow.Fault(this, ex, eventStage ?? flow.Stage); }
            });
        }
        catch (InvalidOperationException) when (dispatcher.HasShutdownStarted || dispatcher.HasShutdownFinished) { }
    }
    private void ConnectionChanged(BluetoothLEDevice sender, object args)
    {
        Dispatch(() => {
            if (!Current || !ReferenceEquals(sender, device)) return;
            if (sender.ConnectionStatus == BluetoothConnectionStatus.Connected) observedConnection = true;
            else if (observedConnection) flow.Lost(this, new());
            else flow.Record(flow.Stage, BleOutcome.InitialDisconnectedIgnored);
        });
    }
    private void SessionChanged(GattSession sender, GattSessionStatusChangedEventArgs args)
    {
        var status = args.Status; var error = args.Error;
        Dispatch(() => {
            if (!Current || !ReferenceEquals(sender, session)) return;
            if (status == GattSessionStatus.Active) observedConnection = true;
            else if (observedConnection || error != BluetoothError.Success) flow.Lost(this, new(BluetoothError: (int)error));
        });
    }
    private void ValueChanged(GattCharacteristic sender, GattValueChangedEventArgs args)
    {
        if (disposed) return;
        try
        {
            byte[] bytes = new byte[args.CharacteristicValue.Length];
            using (var reader = DataReader.FromBuffer(args.CharacteristicValue)) reader.ReadBytes(bytes);
            Dispatch(() => { if (Current && ReferenceEquals(sender, tx)) receive(bytes); });
        }
        catch (Exception ex)
        {
            Dispatch(() => { if (Current) { flow.Fault(this, ex, BleStage.Notifications); } });
        }
    }
    public async Task Write(byte[] frame, CancellationToken cancellation)
    {
        if (!Current || rx == null) throw new MeshException("BLE není připojeno.");
        Codec.BleFrame(frame, MaximumWriteLength);
        using var writer = new DataWriter(); writer.WriteBytes(frame);
        var result = await Native(rx.WriteValueWithResultAsync(writer.DetachBuffer(), GattWriteOption.WriteWithResponse).AsTask(), cancellation);
        Gatt(result.Status, result.ProtocolError);
    }
    private static void CloseSession(GattSession? value)
    { if (value == null) return; try { if (value.CanMaintainConnection) value.MaintainConnection = false; } finally { value.Dispose(); } }
    private void Release(Action action)
    {
        try { action(); }
        catch (Exception ex) { flow.Journal.Add(new(DateTimeOffset.UtcNow, attempt, BleStage.Cleanup, BleOutcome.CleanupFailed, Failure: BleFailure.From(ex, attempt, BleStage.Cleanup))); }
    }
    public void Dispose()
    {
        if (disposed) return; disposed = true; owner.Cancel();
        // Each action is isolated: one failed unsubscribe/dispose cannot retain the other resources.
        var oldTx = tx; var oldService = service; var oldSession = session; var oldDevice = device;
        tx = rx = null; service = null; session = null; device = null;
        if (oldTx != null) Release(() => oldTx.ValueChanged -= ValueChanged);
        if (oldSession != null) { Release(() => oldSession.SessionStatusChanged -= SessionChanged); Release(() => oldSession.MaxPduSizeChanged -= MtuChanged); }
        if (oldDevice != null) Release(() => oldDevice.ConnectionStatusChanged -= ConnectionChanged);
        if (oldService != null) Release(oldService.Dispose);
        if (oldSession != null) Release(() => CloseSession(oldSession));
        if (oldDevice != null) Release(oldDevice.Dispose);
        owner.Dispose();
    }
}
