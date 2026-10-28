using System.Runtime.InteropServices;
using System.Text.Json;
using MeshCore.Core;

internal sealed class ConnectionDriver : IBleConnectionDriver, IBleMtuSource
{
    public int Disposals;
    public int AttMtu => 176;
    public bool ThrowOnDispose;
    public List<BleStage> Calls = [];
    public Func<BleStage, CancellationToken, Task<BleEvidence>> Step = (_, _) => Task.FromResult(new BleEvidence(Mtu: 247));
    public Task<BleEvidence> Execute(BleStage stage, CancellationToken token) { Calls.Add(stage); return Step(stage, token); }
    public void Dispose() { Disposals++; if (ThrowOnDispose) throw new COMException("", unchecked((int)0x80004005)); }
}
internal sealed class LateResource : IDisposable
{ public int Disposals; public void Dispose() => Disposals++; }

internal static partial class Program
{
    private static async Task<BleConnectionException> BleFails(Func<Task> action)
    { try { await action(); } catch (BleConnectionException ex) { return ex; } throw new Exception("Expected BLE failure"); }
    private static async Task BleConnectionTests()
    {
        await Test("Every empty or whitespace exception has a safe message, ID and stage", () => {
            foreach (var error in new Exception[] { new Exception(""), new Exception(" \n\t"), new MeshException(""), new COMException("", unchecked((int)0x80004005)) })
            { var text = BleText.Error(error); Assert(!string.IsNullOrWhiteSpace(text)); Assert(text.Contains("Identifikátor: MC-APP-") && text.Contains("Fáze:")); }
            var hidden = BleText.Error(new Exception("Name=SECRET_HOST PIN=123456 MAC=AABBCCDDEEFF")); Assert(!hidden.Contains("SECRET_HOST") && !hidden.Contains("123456"));
        });
        await Test("BLE failure keeps HRESULT without exporting the exception message", () => {
            var failure = BleFailure.From(new COMException("PRIVATE_NAME AA:BB:CC:DD:EE:FF PIN123456", unchecked((int)0x80070005)), Guid.NewGuid(), BleStage.Access);
            Assert(failure.Message.Contains("0x80070005") && failure.Message.Contains(BleText.Stage(BleStage.Access)));
            Assert(!JsonSerializer.Serialize(failure).Contains("PRIVATE_NAME")); Assert(!failure.Message.Contains("PIN123456"));
        });
        foreach (var failedStage in BleConnectionFlow.Stages)
        {
            await Test("Failure at " + failedStage + " cleans up before returning and permits retry", async () => {
                BleConnectionFlow flow = new(); ConnectionDriver first = new(); int protocols = 0, resets = 0;
                flow.ResetTransport += () => resets++;
                first.Step = (stage, _) => stage == failedStage ? Task.FromException<BleEvidence>(new COMException("", unchecked((int)0x80004005))) : Task.FromResult(new BleEvidence());
                var error = await BleFails(() => flow.Connect(first, () => { protocols++; return Task.CompletedTask; }));
                Equal(failedStage, error.Failure.Stage); Equal(unchecked((int)0x80004005), error.Failure.HResult);
                Equal(1, first.Disposals); Equal(1, resets); Equal(0, protocols);
                Assert(!flow.Connecting && !flow.TransportReady && flow.Driver == null);
                Assert(flow.Journal.Snapshot().Any(e => e.Stage == failedStage && e.Outcome == BleOutcome.Failed && e.Failure?.Id == error.Failure.Id));
                Assert(!first.Calls.Contains(BleStage.MeshCore));
                ConnectionDriver second = new(); await flow.Connect(second, () => { protocols++; return Task.CompletedTask; });
                Assert(flow.TransportReady && !flow.Connecting); Equal(1, protocols); Assert(flow.LastFailure == null);
                Assert(error.Failure.Attempt != flow.Attempt); Equal(0, second.Disposals); flow.Disconnect(); Equal(1, second.Disposals);
            });
        }
        foreach (var timedStage in BleConnectionFlow.Stages)
        {
            await Test("Deadline at " + timedStage + " discards a late native resource", async () => {
                BleConnectionFlow flow = new(phaseTimeout: TimeSpan.FromMilliseconds(25)); ConnectionDriver driver = new();
                TaskCompletionSource<LateResource> late = new(); TaskCompletionSource discarded = new(TaskCreationOptions.RunContinuationsAsynchronously);
                driver.Step = async (stage, token) => {
                    if (stage == timedStage) await BleNativeOperation.Await(late.Task, token, r => r.Dispose(), () => discarded.TrySetResult());
                    return new();
                };
                var failure = await BleFails(() => flow.Connect(driver, () => throw new Exception("Must not initialize")));
                Equal(BleReason.Timeout, failure.Failure.Reason); Equal(timedStage, failure.Failure.Stage); Equal(1, driver.Disposals);
                Assert(!flow.Connecting && !flow.TransportReady);
                ConnectionDriver next = new(); await flow.Connect(next, () => Task.CompletedTask);
                LateResource resource = new(); late.SetResult(resource); await discarded.Task.WaitAsync(TimeSpan.FromSeconds(2));
                Equal(1, resource.Disposals); Assert(flow.TransportReady && ReferenceEquals(next, flow.Driver)); flow.Disconnect();
            });
        }
        await Test("Late native faults are observed with their HRESULT and do not affect the next attempt", async () => {
            using CancellationTokenSource cancel = new(); TaskCompletionSource<LateResource> native = new();
            TaskCompletionSource<int> observed = new(TaskCreationOptions.RunContinuationsAsynchronously);
            var wait = BleNativeOperation.Await(native.Task, cancel.Token, lateFailure: ex => observed.TrySetResult(ex.HResult));
            cancel.Cancel(); await Fails(() => wait);
            native.SetException(new COMException("secret", unchecked((int)0x80004005)));
            Equal(unchecked((int)0x80004005), await observed.Task.WaitAsync(TimeSpan.FromSeconds(2)));
        });
        foreach (bool alreadyFaulted in new[] { true, false })
        {
            await Test("Service discovery 0x80070016 propagates once without false late fault (completed=" + alreadyFaulted + ")", async () => {
                BleConnectionFlow flow = new(); ConnectionDriver driver = new();
                TaskCompletionSource<BleEvidence> native = new(TaskCreationOptions.RunContinuationsAsynchronously);
                var nativeError = new COMException("PRIVATE_NAME PIN123456", unchecked((int)0x80070016));
                if (alreadyFaulted) native.SetException(nativeError);
                driver.Step = (stage, token) => stage == BleStage.Service
                    ? BleNativeOperation.Await(native.Task, token, lateFailure: ex => flow.Record(stage, BleOutcome.LateFaultObserved, failure: BleFailure.From(ex, flow.Attempt, stage)))
                    : Task.FromResult(new BleEvidence());
                var connect = flow.Connect(driver, () => throw new Exception("No protocol or radio writes on discovery failure"));
                Assert(driver.Calls.Contains(BleStage.Service)); native.TrySetException(nativeError);
                var error = await BleFails(() => connect);
                Equal(unchecked((int)0x80070016), error.Failure.HResult); Equal(BleStage.Service, error.Failure.Stage);
                var events = flow.Journal.Snapshot(); Equal(1, events.Count(e => e.Outcome == BleOutcome.Failed));
                Assert(!events.Any(e => e.Outcome == BleOutcome.LateFaultObserved));
                Assert(events.Any(e => e.Stage == BleStage.Cleanup && e.Outcome == BleOutcome.Succeeded));
                Equal(1, driver.Disposals); Assert(!flow.Connecting && flow.Driver == null && !flow.TransportReady);
                Assert(!JsonSerializer.Serialize(events).Contains("PRIVATE_NAME"));
                ConnectionDriver retry = new(); await flow.Connect(retry, () => Task.CompletedTask);
                Assert(flow.TransportReady); flow.Disconnect();
            });
        }
        await Test("Native cancellation without abandoned wait is not a late fault", async () => {
            int late = 0;
            await Fails(() => BleNativeOperation.Await(Task.FromCanceled<int>(new CancellationToken(true)), CancellationToken.None,
                late: () => late++, lateFailure: _ => late++));
            Equal(0, late);
        });
        await Test("Successful native resource racing caller cancellation is discarded exactly once", async () => {
            using CancellationTokenSource cancellation = new(); cancellation.Cancel();
            LateResource resource = new(); int late = 0;
            await Fails(() => BleNativeOperation.Await(Task.FromResult(resource), cancellation.Token, r => r.Dispose(), () => late++));
            Equal(1, resource.Disposals); Equal(1, late);
        });
        await Test("GATT denial and protocol code survive without speculative cause", async () => {
            BleConnectionFlow flow = new(); ConnectionDriver driver = new();
            driver.Step = (stage, _) => stage == BleStage.Notifications ? Task.FromException<BleEvidence>(new BleStepException(BleReason.GattFailure, new(2, 5))) : Task.FromResult(new BleEvidence());
            var error = await BleFails(() => flow.Connect(driver, () => Task.CompletedTask));
            Equal(2, error.Failure.Evidence.GattStatus); Equal((byte)5, error.Failure.Evidence.ProtocolError);
            Assert(error.Message.Contains("0x05")); Assert(!error.Message.Contains("Aktualizujte ovladač"));
        });
        await Test("Insufficient MTU reports the observed value without splitting any frames", async () => {
            BleConnectionFlow flow = new(); ConnectionDriver driver = new();
            driver.Step = (stage, _) => stage == BleStage.Mtu ? Task.FromException<BleEvidence>(new BleStepException(BleReason.MtuInsufficient, new(Mtu:176))) : Task.FromResult(new BleEvidence());
            var error = await BleFails(() => flow.Connect(driver, () => throw new Exception("No protocol until MTU")));
            Equal(176, error.Failure.Evidence.Mtu); Equal(BleStage.Mtu, error.Failure.Stage); Assert(error.Message.Contains("179"));
        });
        await Test("Manual cancellation releases resources once and never labels cleanup as unexpected disconnect", async () => {
            BleConnectionFlow flow = new(); ConnectionDriver driver = new(); TaskCompletionSource entered = new();
            driver.Step = (_, _) => { entered.TrySetResult(); return new TaskCompletionSource<BleEvidence>().Task; };
            var connect = flow.Connect(driver, () => Task.CompletedTask); await entered.Task; flow.Disconnect();
            var failure = await BleFails(() => connect); Equal(BleReason.Cancelled, failure.Failure.Reason);
            Equal(1, driver.Disposals); Assert(!flow.Connecting);
            Assert(!flow.Journal.Snapshot().Any(e => e.Outcome == BleOutcome.UnexpectedDisconnect));
            Equal(BleCloseReason.User, flow.Journal.Snapshot().First(e => e.Stage == BleStage.Cleanup).CloseReason);
        });
        await Test("Connection loss during initialization is distinct from a timeout", async () => {
            BleConnectionFlow flow = new(); ConnectionDriver driver = new(); TaskCompletionSource entered = new();
            driver.Step = (_, _) => { entered.TrySetResult(); return new TaskCompletionSource<BleEvidence>().Task; };
            var connect = flow.Connect(driver, () => Task.CompletedTask); await entered.Task;
            flow.Lost(driver, new(BluetoothError: 3)); flow.Lost(driver, new(BluetoothError: 4)); var failure = await BleFails(() => connect);
            Equal(BleReason.LinkLost, failure.Failure.Reason); Equal(3, failure.Failure.Evidence.BluetoothError); Equal(1, driver.Disposals);
            Equal(1, flow.Journal.Snapshot().Count(e => e.Outcome == BleOutcome.UnexpectedDisconnect));
        });
        await Test("Events from the previous driver cannot disconnect a new connection", async () => {
            BleConnectionFlow flow = new(); ConnectionDriver old = new(), current = new(); int resets = 0; flow.ResetTransport += () => resets++;
            await flow.Connect(old, () => Task.CompletedTask); await flow.Connect(current, () => Task.CompletedTask);
            Equal(1, old.Disposals); Equal(1, resets); flow.Lost(old, new()); Equal(0, current.Disposals); Assert(flow.TransportReady);
            flow.Lost(current, new()); Equal(1, current.Disposals); Assert(!flow.TransportReady);
            Equal(1, flow.Journal.Snapshot().Count(e => e.Outcome == BleOutcome.UnexpectedDisconnect));
        });
        foreach (bool ready in new[] { false, true })
        {
            await Test("Native event error is not a physical disconnect (ready=" + ready + ")", async () => {
                BleConnectionFlow flow = new(); ConnectionDriver driver = new();
                if (!ready) driver.Step = (_, _) => new TaskCompletionSource<BleEvidence>().Task;
                var connection = flow.Connect(driver, () => Task.CompletedTask);
                if (ready) await connection;
                flow.Fault(driver, new COMException("", unchecked((int)0x80004005)), BleStage.Notifications);
                var failure = ready ? flow.LastFailure! : (await BleFails(() => connection)).Failure;
                Equal(unchecked((int)0x80004005), failure.HResult); Equal(BleStage.Notifications,failure.Stage);
                Equal(1,driver.Disposals); Assert(!flow.TransportReady && !flow.Connecting);
                Assert(!flow.Journal.Snapshot().Any(e => e.Outcome == BleOutcome.UnexpectedDisconnect));
                Assert(flow.Journal.Snapshot().Any(e => e.CloseReason == BleCloseReason.Failure));
            });
        }
        await Test("Initial cleanup of an empty flow is not a disconnect event", () => {
            BleConnectionFlow flow = new(); int resets = 0; flow.ResetTransport += () => resets++;
            flow.Disconnect(BleCloseReason.BeforeConnect); flow.Disconnect(); Equal(0, resets); Equal(0, flow.Journal.Snapshot().Length);
        });
        await Test("Concurrent connect is rejected without resetting the active attempt", async () => {
            BleConnectionFlow flow = new(); ConnectionDriver first = new(), second = new(); TaskCompletionSource<BleEvidence> blocked = new();
            first.Step = (stage, _) => stage == BleStage.OpenDevice ? blocked.Task : Task.FromResult(new BleEvidence());
            var connect = flow.Connect(first, () => Task.CompletedTask);
            var error = await BleFails(() => flow.Connect(second, () => Task.CompletedTask)); Equal(BleReason.Busy, error.Failure.Reason);
            Equal(1, second.Disposals); Equal(0, first.Disposals); Assert(flow.Connecting);
            blocked.SetResult(new()); await connect; Assert(flow.TransportReady); flow.Disconnect();
        });
        await Test("Overall deadline bounds a sequence of native operations", async () => {
            BleConnectionFlow flow = new(phaseTimeout: TimeSpan.FromSeconds(5), overallTimeout: TimeSpan.FromMilliseconds(25)); ConnectionDriver driver = new();
            driver.Step = (_, _) => new TaskCompletionSource<BleEvidence>().Task;
            var failure = await BleFails(() => flow.Connect(driver, () => Task.CompletedTask)); Equal(BleReason.Timeout, failure.Failure.Reason);
            Assert(!flow.Connecting && driver.Disposals == 1);
        });
        await Test("Cleanup failure is recorded, remaining state is released and retry works", async () => {
            BleConnectionFlow flow = new(); ConnectionDriver driver = new() { ThrowOnDispose = true };
            await flow.Connect(driver, () => Task.CompletedTask); flow.Disconnect();
            Assert(flow.Driver == null && !flow.TransportReady);
            Assert(flow.Journal.Snapshot().Any(e => e.Outcome == BleOutcome.CleanupFailed && e.Failure!.HResult == unchecked((int)0x80004005)));
            ConnectionDriver next = new(); await flow.Connect(next, () => Task.CompletedTask); Assert(flow.TransportReady); flow.Disconnect();
        });
        await Test("Protocol initialization failure is propagated with its code and Busy cleared", async () => {
            Fake transport = new(); Controller model = new(transport, new MemoryCredentials()); await model.Start();
            transport.Handle = _ => transport.Emit([1, 7]); BleConnectionFlow flow = new(); flow.ResetTransport += transport.Drop;
            var failure = await BleFails(() => flow.Connect(new ConnectionDriver(), () => model.Initialize(123, propagateFailure:true)));
            Equal(BleStage.MeshCore, failure.Failure.Stage); Equal((byte)7, failure.Failure.Evidence.ProtocolError);
            Assert(!model.Initialized && !model.Busy && !flow.Connecting); Assert(transport.Sent.All(b => b[0] == 22));
            LocalReplies(transport); await flow.Connect(new ConnectionDriver(), () => model.Initialize(123, propagateFailure:true));
            Assert(model.Initialized && !model.Busy); Assert(!model.Monitoring);
            Assert(transport.Sent.All(b => b[0] is 22 or 1 or 20 or 31 or 10)); // No LoRa, configuration writes, clock sync or discovery.
            flow.Disconnect();
        });
        await Test("Protocol deadline resets the pending session before returning to the UI", async () => {
            Fake transport = new(); Controller model = new(transport, new MemoryCredentials()); await model.Start();
            BleConnectionFlow flow = new(protocolTimeout:TimeSpan.FromMilliseconds(25)); flow.ResetTransport += transport.Drop;
            var failure = await BleFails(() => flow.Connect(new ConnectionDriver(), () => model.Initialize(123, propagateFailure:true)));
            Equal(BleStage.MeshCore, failure.Failure.Stage); Equal(BleReason.Timeout, failure.Failure.Reason);
            Assert(!model.Busy && !flow.Connecting && !model.Initialized); Equal(1, transport.Sent.Count);
        });
        await Test("Connection-only export works offline and excludes identity, payload and raw exceptions", async () => {
            Fake transport = new(); Controller model = new(transport, new MemoryCredentials()); await model.Start();
            string sensitive = "PRIVATE_NAME AA:BB:CC:DD:EE:FF PIN=123456 key=" + Id + " C:\\Users\\Secret\\host";
            var failure = BleFailure.From(new COMException(sensitive, unchecked((int)0x80004005)), Guid.NewGuid(), BleStage.OpenDevice);
            transport.ConnectionDiagnostics.Add(new(DateTimeOffset.UtcNow, failure.Attempt, failure.Stage, BleOutcome.Failed, Failure: failure));
            var json = model.BleDiagnosticReport(); Assert(json.Contains(failure.Id) && json.Contains("OpenDevice"));
            foreach (var secret in new[] { "PRIVATE_NAME", "AA:BB:CC:DD:EE:FF", "123456", Id, "Secret", "host", "Exception", "StackTrace" }) Assert(!json.Contains(secret),secret);
            Assert(!model.Initialized && transport.Sent.Count == 0); Assert(model.DiagnosticReport().Contains(failure.Id));
            foreach (var report in new[] { json, model.DiagnosticReport() })
                Equal(BleConnectionFlow.Implementation, JsonDocument.Parse(report).RootElement.GetProperty("ConnectionImplementation").GetString());
        });
        await Test("Profile switch preserves BLE failure evidence without exporting either identity", async () => {
            var (transport, model) = await Model();
            var failure = BleFailure.From(new COMException("", unchecked((int)0x80004005)), Guid.NewGuid(), BleStage.Access);
            transport.ConnectionDiagnostics.Add(new(DateTimeOffset.UtcNow, failure.Attempt, failure.Stage, BleOutcome.Failed, Failure:failure));
            transport.Drop(); LocalReplies(transport); var previous = transport.Handle!;
            transport.Handle = frame => { if (frame[0] == 1) { var own = Own("Second private name"); own.AsSpan(4,32).Fill(0xaa); transport.Emit(own); } else previous(frame); };
            await model.Initialize(124, propagateFailure:true);
            Assert(model.Initialized && model.Archive!.Account != Id);
            var report = model.BleDiagnosticReport(); Assert(report.Contains(failure.Id));
            Assert(!report.Contains("Second private name") && !report.Contains(Id) && !report.Contains(model.Archive!.Account));
        });
        await Test("BLE event history is bounded to 256 safe entries", () => {
            BleConnectionJournal journal = new(); for (int i = 0; i < 400; i++) journal.Add(new(DateTimeOffset.UtcNow, Guid.NewGuid(), BleStage.Access, BleOutcome.Started));
            Equal(256,journal.Snapshot().Length);
        });
    }
}
