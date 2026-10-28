using System.Text.Json.Serialization;

namespace MeshCore.Core;

[JsonConverter(typeof(JsonStringEnumConverter<BleStage>))]
public enum BleStage { Operation, OpenDevice, Access, GattSession, Service, Characteristics, Notifications, Mtu, MeshCore, Ready, Cleanup }
[JsonConverter(typeof(JsonStringEnumConverter<BleOutcome>))]
public enum BleOutcome { Started, Succeeded, Failed, Cancelled, LateResultDiscarded, LateFaultObserved, UnexpectedDisconnect, AdditionalDisconnectEvidence, InitialDisconnectedIgnored, CleanupFailed }
[JsonConverter(typeof(JsonStringEnumConverter<BleReason>))]
public enum BleReason { NativeFailure, Timeout, Cancelled, AccessDenied, DeviceUnavailable, MissingSession, MissingService, MissingCharacteristics, GattFailure, MtuInsufficient, ProtocolRejected, LinkLost, Busy }
[JsonConverter(typeof(JsonStringEnumConverter<BleCloseReason>))]
public enum BleCloseReason { BeforeConnect, User, Sleep, Shutdown, Failure, Unexpected }

// Strictly typed allowlist: never add a device name/address, exception text or packet data here.
public sealed record BleEvidence(int? GattStatus = null, byte? ProtocolError = null, int? AccessStatus = null,
    int? Mtu = null, int? RxProperties = null, int? TxProperties = null, int? BluetoothError = null);
public sealed record BleFailure(string Id, Guid Attempt, BleStage Stage, BleReason Reason, int? HResult, BleEvidence Evidence)
{
    public string Message => $"Připojení se nezdařilo: {BleText.Reason(Reason)}\nFáze: {BleText.Stage(Stage)}.\nIdentifikátor: {Id}." +
        (HResult is { } hr ? $"\nHRESULT: 0x{unchecked((uint)hr):X8}." : "") +
        (Evidence.GattStatus is { } status ? $"\nGATT status: {status}." : "") +
        (Evidence.ProtocolError is { } code ? $"\nProtokolový kód: 0x{code:X2}." : "") +
        (Evidence.Mtu is { } mtu ? $"\nZjištěné ATT MTU: {mtu}; pro úplné rámce je potřeba alespoň 179." : "") +
        "\nPodrobnosti fází lze vyexportovat v Diagnostice i bez připojení. Samotná chyba neurčuje příčinu v zařízení nebo systému.";
    public static BleFailure From(Exception exception, Guid attempt, BleStage stage)
    {
        if (exception is BleConnectionException known) return known.Failure;
        var step = exception as BleStepException;
        var reason = step?.Reason ?? (exception is TimeoutException ? BleReason.Timeout : exception is OperationCanceledException ? BleReason.Cancelled : exception is RequestRejectedException ? BleReason.ProtocolRejected : exception is UnauthorizedAccessException ? BleReason.AccessDenied : BleReason.NativeFailure);
        return new("MC-BLE-" + Guid.NewGuid().ToString("N")[..12], attempt, stage, reason,
            step != null || exception is TimeoutException or OperationCanceledException or RequestRejectedException ? null : exception.HResult,
            step?.Evidence ?? new(ProtocolError: (exception as RequestRejectedException)?.Code));
    }
}
public sealed class BleStepException(BleReason reason, BleEvidence? evidence = null) : Exception(BleText.Reason(reason))
{ public BleReason Reason { get; } = reason; public BleEvidence Evidence { get; } = evidence ?? new(); }
public sealed class BleConnectionException(BleFailure failure) : Exception(failure.Message)
{ public BleFailure Failure { get; } = failure; }
public sealed record BleConnectionEvent(DateTimeOffset Date, Guid Attempt, BleStage Stage, BleOutcome Outcome,
    BleCloseReason? CloseReason = null, BleFailure? Failure = null, BleEvidence? Evidence = null);
public sealed class BleConnectionJournal
{
    private readonly object sync = new();
    private readonly List<BleConnectionEvent> events = [];
    public void Add(BleConnectionEvent entry) { lock (sync) { events.Add(entry); if (events.Count > 256) events.RemoveAt(0); } }
    public BleConnectionEvent[] Snapshot() { lock (sync) return events.ToArray(); }
}
public interface IBleDiagnosticsSource { BleConnectionJournal ConnectionDiagnostics { get; } string ConnectionImplementation => BleConnectionFlow.Implementation; }
public interface IBleConnectionDriver : IDisposable
{
    Task<BleEvidence> Execute(BleStage stage, CancellationToken cancellation);
}
public static class BleText
{
    public static string Stage(BleStage stage) => stage switch {
        BleStage.OpenDevice => "otevření zařízení", BleStage.Access => "oprávnění Bluetooth", BleStage.GattSession => "GATT relace",
        BleStage.Service => "nalezení Nordic UART služby", BleStage.Characteristics => "nalezení RX a TX charakteristik",
        BleStage.Notifications => "povolení notifikací", BleStage.Mtu => "zjištění ATT MTU", BleStage.MeshCore => "inicializace protokolu MeshCore",
        BleStage.Ready => "připojeno", BleStage.Cleanup => "uvolnění BLE prostředků", _ => "operace aplikace" };
    public static string Reason(BleReason reason) => reason switch {
        BleReason.Timeout => "vypršel časový limit čekání", BleReason.Cancelled => "pokus byl zrušen",
        BleReason.AccessDenied => "Systém oznámil odepřený přístup", BleReason.DeviceUnavailable => "Systém neposkytl objekt zařízení",
        BleReason.MissingSession => "Systém neposkytl GATT relaci", BleReason.MissingService => "požadovaná Nordic UART služba nebyla nalezena",
        BleReason.MissingCharacteristics => "chybí RX s Write nebo TX s Notify pro Nordic UART",
        BleReason.GattFailure => "GATT operace neuspěla", BleReason.MtuInsufficient => "vyjednané ATT MTU nestačí pro úplné MeshCore rámce",
        BleReason.ProtocolRejected => "companion odmítl místní inicializační požadavek", BleReason.LinkLost => "Systém oznámil ztrátu otevřeného BLE spoje",
        BleReason.Busy => "jiný pokus o připojení ještě probíhá", _ => "Bluetooth nebo inicializace vrátily chybu bez bezpečně zobrazitelných podrobností" };
    public static string Error(Exception exception, Func<string, string>? redact = null)
    {
        if (exception is BleConnectionException ble) return ble.Failure.Message;
        // Framework/WinRT exception messages can be empty or contain identifiers. Do not display them verbatim.
        var text = exception is MeshException && !string.IsNullOrWhiteSpace(exception.Message) ? (redact?.Invoke(exception.Message) ?? exception.Message).Trim() : "Operaci se nepodařilo dokončit. Zkontrolujte diagnostiku a před novým pokusem stav spojení.";
        if (string.IsNullOrWhiteSpace(text)) text = "Operaci se nepodařilo dokončit.";
        return text + "\nFáze: operace aplikace. Identifikátor: MC-APP-" + Guid.NewGuid().ToString("N")[..12] + ".";
    }
}

public static class BleNativeOperation
{
    // WinRT cancellation/deadlines do not guarantee that the native operation stops.
    // Always observe a late fault and dispose a late successful resource; never adopt it.
    public static async Task<T> Await<T>(Task<T> task, CancellationToken cancellation, Action<T>? discard = null, Action? late = null, Action<Exception>? lateFailure = null)
    {
        try { var result = await task.WaitAsync(cancellation); cancellation.ThrowIfCancellationRequested(); return result; }
        catch (OperationCanceledException) when (cancellation.IsCancellationRequested)
        {
            // Only an abandoned wait owns a late completion. An ordinary native
            // fault was already observed by await and must propagate once.
            _ = task.ContinueWith(t => {
                try { if (t.IsCompletedSuccessfully) { discard?.Invoke(t.Result); late?.Invoke(); } else if (t.Exception is { } error) { lateFailure?.Invoke(error.GetBaseException()); } }
                catch { /* A late disposal must not crash the UI or expose raw exceptions. */ }
            }, CancellationToken.None, TaskContinuationOptions.ExecuteSynchronously, TaskScheduler.Default);
            throw;
        }
    }
}

// UI-thread orchestration with an injectable native driver. No BLE APIs and no LoRa requests in this type.
public sealed class BleConnectionFlow
{
    public const string Implementation = "windows-ble-enumerate-services-2";
    public static IReadOnlyList<BleStage> Stages { get; } = Array.AsReadOnly<BleStage>([BleStage.OpenDevice, BleStage.Access, BleStage.GattSession, BleStage.Service, BleStage.Characteristics, BleStage.Notifications, BleStage.Mtu]);
    public BleConnectionJournal Journal { get; } = new();
    public event Action? Changed;
    public event Action? ResetTransport;
    public bool Connecting { get; private set; }
    public bool TransportReady { get; private set; }
    public BleStage Stage { get; private set; } = BleStage.Operation;
    public BleFailure? LastFailure { get; private set; }
    public IBleConnectionDriver? Driver { get; private set; }
    public Guid Attempt { get; private set; }
    private CancellationTokenSource? lifetime;
    private TaskCompletionSource? cleanup;
    private BleFailure? interrupted;
    private readonly TimeSpan phaseTimeout, protocolTimeout, overallTimeout;
    public BleConnectionFlow(TimeSpan? phaseTimeout = null, TimeSpan? protocolTimeout = null, TimeSpan? overallTimeout = null)
    { this.phaseTimeout = phaseTimeout ?? TimeSpan.FromSeconds(20); this.protocolTimeout = protocolTimeout ?? TimeSpan.FromMinutes(2); this.overallTimeout = overallTimeout ?? TimeSpan.FromMinutes(3); }
    public void Record(BleStage stage, BleOutcome outcome, BleEvidence? evidence = null, BleCloseReason? close = null, BleFailure? failure = null)
        => Journal.Add(new(DateTimeOffset.UtcNow, Attempt, stage, outcome, close, failure, evidence));
    public async Task Connect(IBleConnectionDriver driver, Func<Task> initialize)
    {
        if (Connecting) { driver.Dispose(); throw new BleConnectionException(BleFailure.From(new BleStepException(BleReason.Busy), Attempt, Stage)); }
        Disconnect(BleCloseReason.BeforeConnect);
        Attempt = Guid.NewGuid(); LastFailure = null; interrupted = null; Connecting = true; Driver = driver;
        using var deadline = new CancellationTokenSource(overallTimeout);
        using var cancellation = CancellationTokenSource.CreateLinkedTokenSource(deadline.Token);
        lifetime = cancellation;
        Task? initialization = null;
        try
        {
            foreach (var stage in Stages) await Phase(stage, token => driver.Execute(stage, token), phaseTimeout);
            TransportReady = true;
            await Phase(BleStage.MeshCore, async token => { initialization = initialize(); await initialization.WaitAsync(token); return new BleEvidence(); }, protocolTimeout);
            Stage = BleStage.Ready; Record(Stage, BleOutcome.Succeeded); Changed?.Invoke();
        }
        catch (Exception ex)
        {
            LastFailure = interrupted ?? BleFailure.From(ex, Attempt, Stage);
            Record(LastFailure.Stage, LastFailure.Reason == BleReason.Cancelled ? BleOutcome.Cancelled : BleOutcome.Failed, failure: LastFailure);
            Disconnect(BleCloseReason.Failure);
            if (cleanup is { } closing) await closing.Task;
            // ResetTransport aborts the protocol wait; allow its finally blocks to finish before the UI shows the error.
            if (initialization != null)
            {
                try { await initialization.WaitAsync(TimeSpan.FromSeconds(2)); }
                catch { _ = initialization.ContinueWith(t => { _ = t.Exception; }, CancellationToken.None, TaskContinuationOptions.OnlyOnFaulted | TaskContinuationOptions.ExecuteSynchronously, TaskScheduler.Default); }
            }
            throw new BleConnectionException(LastFailure);
        }
        finally { lifetime = null; Connecting = false; Changed?.Invoke(); }

        async Task Phase(BleStage stage, Func<CancellationToken, Task<BleEvidence>> operation, TimeSpan timeout)
        {
            cancellation.Token.ThrowIfCancellationRequested(); Stage = stage; Record(stage, BleOutcome.Started); Changed?.Invoke();
            using var phase = CancellationTokenSource.CreateLinkedTokenSource(cancellation.Token); phase.CancelAfter(timeout);
            try
            {
                var evidence = await operation(phase.Token).WaitAsync(phase.Token);
                phase.Token.ThrowIfCancellationRequested(); Record(stage, BleOutcome.Succeeded, evidence);
            }
            catch (OperationCanceledException) when (!cancellation.IsCancellationRequested || deadline.IsCancellationRequested)
            { throw new BleStepException(BleReason.Timeout, stage == BleStage.Mtu && driver is IBleMtuSource mtu ? new(Mtu: mtu.AttMtu) : null); }
            finally { phase.Cancel(); }
        }
    }
    public void Lost(IBleConnectionDriver driver, BleEvidence evidence)
    {
        if (!ReferenceEquals(driver, Driver)) return;
        // Device and GattSession can report the same loss. Keep one failure ID,
        // but retain any numeric status supplied by the second notification.
        if (interrupted != null) { Record(Stage, BleOutcome.AdditionalDisconnectEvidence, evidence); return; }
        interrupted = BleFailure.From(new BleStepException(BleReason.LinkLost, evidence), Attempt, Stage);
        Record(Stage, BleOutcome.UnexpectedDisconnect, evidence, failure: interrupted);
        if (Connecting) { lifetime?.Cancel(); return; }
        LastFailure = interrupted; Disconnect(BleCloseReason.Unexpected); Changed?.Invoke();
    }
    public void Fault(IBleConnectionDriver driver, Exception exception, BleStage stage)
    {
        if (!ReferenceEquals(driver, Driver) || interrupted != null) return;
        interrupted = BleFailure.From(exception, Attempt, stage);
        if (Connecting) { lifetime?.Cancel(); return; }
        LastFailure = interrupted; Record(stage, BleOutcome.Failed, failure: LastFailure);
        Disconnect(BleCloseReason.Failure); Changed?.Invoke();
    }
    public void Disconnect(BleCloseReason reason = BleCloseReason.User)
    {
        TransportReady = false;
        var old = Driver; Driver = null;
        if (old == null) { lifetime?.Cancel(); return; } // Initial cleanup is not a physical disconnect.
        var closing = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously); cleanup = closing;
        Record(BleStage.Cleanup, BleOutcome.Started, close: reason);
        try { old.Dispose(); Record(BleStage.Cleanup, BleOutcome.Succeeded, close: reason); }
        catch (Exception ex) { Record(BleStage.Cleanup, BleOutcome.CleanupFailed, close: reason, failure: BleFailure.From(ex, Attempt, BleStage.Cleanup)); }
        finally
        {
            try { ResetTransport?.Invoke(); lifetime?.Cancel(); Changed?.Invoke(); }
            finally { closing.TrySetResult(); if (ReferenceEquals(cleanup, closing)) cleanup = null; }
        }
    }
}
public interface IBleMtuSource { int AttMtu { get; } }
