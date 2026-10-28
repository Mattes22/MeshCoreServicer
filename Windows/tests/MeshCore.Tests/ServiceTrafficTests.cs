using System.Text.Json;
using MeshCore.Core;

internal static partial class Program
{
    private static async Task ServiceTrafficTests()
    {
        await Test("Diagnostic plans are finite with hourly policy on either route", () =>
        {
            Equal(ServiceRoute.Known, ServiceRouting.Classify(0)); Equal(ServiceRoute.Known, ServiceRouting.Classify(0x83));
            foreach (byte p in new byte[] { 255, 0xc1, 0x7f }) Equal(ServiceRoute.FloodOrUnknown, ServiceRouting.Classify(p));
            Equal(720, new DiagnosticPlan(240, 3, ServiceRoute.Known).DurationMinutes);
            Throws(() => new DiagnosticPlan(30, 3, ServiceRoute.FloodOrUnknown));
            Throws(() => new DiagnosticPlan(120, 4, ServiceRoute.Known)); Throws(() => new DiagnosticPlan(60, 7, ServiceRoute.Known));
            Equal(1080, new DiagnosticPlan(180, 6, ServiceRoute.FloodOrUnknown).DurationMinutes);
        });
        await Test("Diagnostic slots wait first interval and skip busy and late slots without catchup", () =>
        {
            var start = DateTimeOffset.UnixEpoch; DiagnosticMeasurement run = new(new(240, 3, ServiceRoute.Known), start);
            Assert(!run.TakeDue(start, false)); Assert(run.TakeDue(start.AddHours(4), false)); run.Finish(true);
            Assert(!run.TakeDue(start.AddHours(8), true)); Assert(!run.TakeDue(start.AddHours(12).AddMinutes(2), false));
            Equal(1, run.Received); Equal(2, run.Skipped); Equal(0, run.Remaining); Assert(!run.Running && run.Next == null);
        });
        await Test("Stopping inflight measurement keeps response but never starts another request", () =>
        { DiagnosticMeasurement run = new(new(240, 3, ServiceRoute.Known), DateTimeOffset.UnixEpoch); Assert(run.TakeDue(run.Next!.Value, false)); run.Stop(); run.Finish(true); Equal(1, run.Received); Assert(!run.Running); Equal(null, run.Next); });
        await Test("Default diagnostic plan schedules first at four hours and final at twelve", () =>
        {
            var start = DateTimeOffset.UnixEpoch; var plan = new DiagnosticPlan();
            Equal(240, plan.IntervalMinutes); Equal(3, plan.Samples); Equal(720, plan.DurationMinutes);
            DiagnosticMeasurement run = new(plan, start); Equal(start.AddHours(4), run.Next);
            Assert(!run.TakeDue(start.AddHours(4).AddSeconds(-1), false));
            foreach (int hour in new[] { 4, 8, 12 }) { Equal(start.AddHours(hour), run.Next); Assert(run.TakeDue(run.Next!.Value, false)); run.Finish(true); }
            Equal(3, run.Received); Assert(!run.Running && run.Next == null); Assert(!run.TakeDue(start.AddHours(24), false));
        });
        await Test("Every minute and sample combination respects the 24 hour cap on both routes", () =>
        {
            foreach (var route in new[] { ServiceRoute.Known, ServiceRoute.FloodOrUnknown })
                for (int minutes = 180; minutes <= 1440; minutes++)
                    for (int count = 1; count <= 6; count++)
                        if (minutes * count <= 1440) Equal(minutes * count, new DiagnosticPlan(minutes, count, route).DurationMinutes);
                        else Throws(() => new DiagnosticPlan(minutes, count, route));
            foreach (int minutes in new[] { int.MinValue, -1, 0, 179, 1441, int.MaxValue }) Throws(() => new DiagnosticPlan(minutes, 1));
            foreach (int count in new[] { int.MinValue, 0, 7, int.MaxValue }) Throws(() => new DiagnosticPlan(240, count));
            Equal(1440, new DiagnosticPlan(1440, 1).DurationMinutes); Equal(1440, new DiagnosticPlan(240, 6).DurationMinutes); Throws(() => new DiagnosticPlan(241, 6));
        });
        await Test("24 hour final slot completes or skips without ever catching up", () =>
        {
            var start = DateTimeOffset.UnixEpoch; DiagnosticMeasurement run = new(new(1440, 1), start);
            Assert(!run.TakeDue(start.AddHours(24).AddSeconds(-1), false)); Assert(run.TakeDue(run.Next!.Value, false)); run.Finish(true);
            Assert(!run.Running); Equal(1, run.Received);
            DiagnosticMeasurement late = new(new(1440, 1), start);
            Assert(!late.TakeDue(start.AddHours(24).AddSeconds(31), false)); Equal(1, late.Skipped); Assert(!late.Running && late.Next == null);
        });
        await Test("Hour input supports Czech decimals and preserves every stored minute", () =>
        {
            Equal(240, DiagnosticPlan.MinutesFromHours("4")); Equal(270, DiagnosticPlan.MinutesFromHours("4,5")); Equal(270, DiagnosticPlan.MinutesFromHours("4.5"));
            Equal("4 h", DiagnosticPlan.HoursText(240)); Equal("3 h 1 min", DiagnosticPlan.HoursText(181));
            for (int minutes = 180; minutes <= 1440; minutes++) Equal(minutes, DiagnosticPlan.MinutesFromHours(DiagnosticPlan.HoursInput(minutes)));
            foreach (var text in new[] { "2.999", "24.001", "NaN", "Infinity", "-4", "", "1e10" }) Throws(() => DiagnosticPlan.MinutesFromHours(text));
        });
        await Test("Diagnostic migration keeps longer intervals and all other preferences idempotently", () =>
        {
            foreach (int minutes in new[] { 5, 30, 60, 179, 180, 181, 240, 360, 480, 1440 })
            {
                var json = JsonSerializer.Serialize(new { DiagnosticMinutes = minutes, DiagnosticSamples = 3, MonitorMinutes = 5, AutoReconnect = false, Suggestions = false, SuggestWrites = true });
                var options = JsonSerializer.Deserialize<DeviceOptions>(json)!; int expected = minutes < 180 ? 240 : minutes;
                Equal(expected, options.DiagnosticMinutes); Equal(Math.Min(3, 1440 / expected), options.DiagnosticSamples);
                Equal(5, options.MonitorMinutes); Assert(!options.AutoReconnect && !options.Suggestions && options.SuggestWrites);
                options.ValidateDiagnostic(); var encoded = JsonSerializer.Serialize(options);
                Equal(encoded, JsonSerializer.Serialize(JsonSerializer.Deserialize<DeviceOptions>(encoded)));
            }
            Equal(240, new DeviceOptions().DiagnosticMinutes);
        });
        await Test("Controller waits full four hours and finishes default plan after twelve", async () =>
        {
            AdvancingClock clock = new(); var (t, m, _) = await AdminModel(measurementClock: clock); var handler = t.Handle;
            t.Handle = f => { if (f[0] == 27) { t.Emit(Sent()); t.Emit([0x87, 0, .. Key[..6], .. Status()]); } else handler!(f); };
            Assert(!m.Monitoring); Equal(240, m.Options.DiagnosticMinutes); m.SetMonitoring(true);
            var start = clock.GetUtcNow(); Equal(start.AddHours(4), m.NextMonitor);
            clock.Advance(TimeSpan.FromHours(4) - TimeSpan.FromSeconds(1)); await m.Tick(); Equal(0, t.Sent.Count(f => f[0] == 27));
            clock.Advance(TimeSpan.FromSeconds(1)); await m.Tick(); Equal(1, m.Measurement!.Received);
            clock.Advance(TimeSpan.FromHours(4)); await m.Tick(); Equal(2, m.Measurement.Received);
            clock.Advance(TimeSpan.FromHours(4)); await m.Tick(); Equal(3, m.Measurement.Received); Assert(!m.Monitoring && m.NextMonitor == null);
            clock.Advance(TimeSpan.FromHours(12)); await m.Tick(); Equal(3, t.Sent.Count(f => f[0] == 27)); Equal(3, m.Operations.Samples.Count);
            foreach (var (minutes, count) in new[] { (179, 3), (300, 6), (1440, 2) }) await Fails(() => m.SetDiagnosticOptions(minutes, count));
        });
        await Test("All inactive profiles and defaults migrate without replacing unrelated library data", async () =>
        {
            LocalStore store = new(); var profiles = new List<CompanionProfile>();
            foreach (int minutes in new[] { 30, 60, 179, 180, 181, 360, 480, 1440 })
            {
                var account = new string((char)('a' + profiles.Count % 6), 63) + profiles.Count;
                profiles.Add(new() { Account = account, Name = "Test", Alias = "Alias " + minutes, Options = new() { DiagnosticMinutes = minutes, AutoReconnect = false, Suggestions = false } });
            }
            LibraryDocument old = new() { Profiles = profiles, Defaults = new() { DiagnosticMinutes = 30 }, InterfaceScale = 130, Theme = "Tmavý", Notifications = true };
            await store.Save("library.json", old, _ => { }); // fixture deliberately uses the former persisted values
            Fake t = new(); Controller m = new(t, new MemoryCredentials(), store); await m.Start();
            Equal(null, m.StorageError); Equal(240, m.Options.DiagnosticMinutes); Assert(!m.Monitoring && t.Sent.Count == 0);
            Equal(130, m.Library.InterfaceScale); Equal("Tmavý", m.Library.Theme); Assert(m.Library.Notifications);
            for (int i = 0; i < profiles.Count; i++)
            {
                var p = m.Library.Profiles[i]; int oldMinutes = profiles[i].Options.DiagnosticMinutes;
                Equal(oldMinutes < 180 ? 240 : oldMinutes, p.Options.DiagnosticMinutes); Equal(profiles[i].Alias, p.Alias); Assert(!p.Options.AutoReconnect && !p.Options.Suggestions);
            }
            await m.SaveLibrary(); var first = JsonSerializer.Serialize(m.Library);
            Controller again = new(t, new MemoryCredentials(), store); await again.Start(); Equal(first, JsonSerializer.Serialize(again.Library)); Assert(!again.Monitoring);
        });
        await Test("Service budgets share all nodes and batches and expire only after an hour", async () =>
        {
            AdvancingClock clock = new(); ServiceTrafficGovernor governor = new(clock, clock.Delay);
            for (int i = 0; i < 12; i++) { governor.Begin(() => true); await governor.Acquire(ServiceRoute.FloodOrUnknown); governor.End(); }
            await Fails(() => governor.Acquire(ServiceRoute.FloodOrUnknown)); Equal(11, clock.Waits.Count);
            Assert(clock.Waits.All(w => w == TimeSpan.FromSeconds(60))); await governor.Acquire(ServiceRoute.Known);
            clock.Advance(TimeSpan.FromHours(1)); await governor.Acquire(ServiceRoute.FloodOrUnknown);
        });
        await Test("Global service limit and multistep cap do not create a queue", async () =>
        {
            AdvancingClock clock = new(); ServiceTrafficGovernor governor = new(clock, clock.Delay); governor.Begin(() => true);
            for (int i = 0; i < 32; i++) await governor.Acquire(ServiceRoute.Known);
            await Fails(() => governor.Acquire(ServiceRoute.Known)); governor.End();
            for (int i = 32; i < 60; i++) await governor.Acquire(ServiceRoute.Known);
            await Fails(() => governor.Acquire(ServiceRoute.Known)); Equal(59, clock.Waits.Count); Assert(clock.Waits.All(w => w == TimeSpan.FromSeconds(15)));
        });
        await Test("Authorization and batch deadline are rechecked after the traffic delay", async () =>
        {
            AdvancingClock clock = new(); bool valid = true;
            ServiceTrafficGovernor governor = new(clock, (wait, token) => { clock.Advance(wait); valid = false; return Task.CompletedTask; });
            governor.Begin(() => valid); await governor.Acquire(ServiceRoute.Known); await Fails(() => governor.Acquire(ServiceRoute.Known)); governor.End();
            valid = true; governor.Begin(() => valid); clock.Advance(TimeSpan.FromMinutes(21)); await Fails(() => governor.Acquire(ServiceRoute.Known));
        });
        await Test("Local BLE reads do not consume service budget and reconnect does not refill it", async () =>
        {
            AdvancingClock clock = new(); Fake t = new(); using MeshSession session = new(t, pacer: clock.Pacer());
            t.Handle = f => t.Emit(f[0] == 4 ? new byte[] { 4, 0, 0, 0, 0 } : new byte[] { 0 });
            for (int i = 0; i < 12; i++) await session.Discover(1);
            await session.Contacts(); session.Reset(); await Fails(() => session.Discover(2)); Equal(12, t.Sent.Count(f => f[0] == 55)); Assert(!session.RequiresReconnect);
        });
        await Test("Concurrent manual command during pacing is rejected without a queue", async () =>
        {
            AdvancingClock clock = new(); Fake t = new(); TaskCompletionSource ready = new(), release = new();
            ServiceTrafficGovernor governor = new(clock, async (wait, token) => { ready.SetResult(); await release.Task; clock.Advance(wait); });
            using MeshSession session = new(t, pacer: clock.Pacer(), traffic: governor); t.Handle = _ => t.Emit([0]);
            await session.Discover(1); var second = session.Discover(2); await ready.Task;
            await Fails(() => session.Contacts()); Equal(1, t.Sent.Count); release.SetResult(); await second; Equal(2, t.Sent.Count);
        });
        await Test("Legacy monitoring preference does not determine diagnostic defaults", () =>
        {
            var options = JsonSerializer.Deserialize<DeviceOptions>("{\"MonitorMinutes\":5,\"AutoReconnect\":false,\"Suggestions\":false}")!;
            Equal(5, options.MonitorMinutes); Equal(240, options.DiagnosticMinutes); Equal(3, options.DiagnosticSamples); Assert(!options.AutoReconnect && !options.Suggestions);
            var restored = JsonSerializer.Deserialize<DeviceOptions>(JsonSerializer.Serialize(options))!; Equal(240, restored.DiagnosticMinutes);
        });
        await Test("Controller finite diagnostics stop at sample count without changing history reads", async () =>
        {
            AdvancingClock clock = new(); var (t, m, _) = await AdminModel(measurementClock: clock); var handler = t.Handle;
            t.Handle = f => { if (f[0] == 27) { t.Emit(Sent()); t.Emit([0x87, 0, .. Key[..6], .. Status()]); } else handler!(f); };
            await m.SetDiagnosticOptions(240, 2); m.SetMonitoring(true); Assert(!t.Sent.Any(f => f[0] == 27));
            clock.Advance(TimeSpan.FromHours(4)); await m.Tick(); Equal(1, m.Measurement!.Received);
            clock.Advance(TimeSpan.FromHours(4)); await m.Tick(); Assert(!m.Monitoring); Equal(2, m.Operations.Samples.Count);
            int sent = t.Sent.Count; clock.Advance(TimeSpan.FromHours(4)); await m.Tick(); _ = m.Operations.Samples; _ = m.Operations.Snapshots; Equal(sent, t.Sent.Count);
        });
        await Test("Late controller diagnostics skip all missed samples and do not resume", async () =>
        {
            AdvancingClock clock = new(); var (t, m, _) = await AdminModel(measurementClock: clock); m.SetMonitoring(true); int before = t.Sent.Count;
            clock.Advance(TimeSpan.FromHours(13)); await m.Tick(); Assert(!m.Monitoring); Equal(3, m.Measurement!.Skipped); Equal(before, t.Sent.Count);
            await m.Tick(); Equal(before, t.Sent.Count);
        });
        await Test("Diagnostic failure and permission loss stop without retrying", async () =>
        {
            AdvancingClock clock = new(); var (t, m, _) = await AdminModel(measurementClock: clock); var old = t.Handle;
            t.Handle = f => { if (f[0] == 27) throw new IOException("failed"); old!(f); };
            m.SetMonitoring(true); clock.Advance(TimeSpan.FromHours(4)); await m.Tick(); Assert(!m.Monitoring); int sent = t.Sent.Count;
            clock.Advance(TimeSpan.FromHours(1)); await m.Tick(); Equal(sent, t.Sent.Count);
            var (other, model, _) = await AdminModel(); model.SetMonitoring(true); other.Emit([0x85, 0, .. Key[..6]]); Assert(!model.Monitoring && !model.Admin);
        });
        await Test("Stop cancels a diagnostic waiting for pacing before any radio frame", async () =>
        {
            AdvancingClock clock = new(); TaskCompletionSource waiting = new();
            ServiceTrafficGovernor held = new(new AdvancingClock(), async (_, token) => { waiting.TrySetResult(); await Task.Delay(Timeout.InfiniteTimeSpan, token); });
            var (transport, model, _) = await AdminModel(measurementClock: clock, traffic: held); model.SetMonitoring(true);
            clock.Advance(TimeSpan.FromHours(4)); int before = transport.Sent.Count; var tick = model.Tick();
            await waiting.Task.WaitAsync(TimeSpan.FromSeconds(2)); model.SetMonitoring(false); await tick.WaitAsync(TimeSpan.FromSeconds(2));
            Assert(!model.Monitoring && !model.Busy); Equal(before, transport.Sent.Count); Equal(null, model.Error);
        });
        await Test("Every remote service API uses the same exhausted budget", async () =>
        {
            AdvancingClock clock = new(); Fake t = new(); using MeshSession session = new(t, pacer: clock.Pacer());
            t.Handle = f => t.Emit(f[0] == 10 ? new byte[] { 10 } : new byte[] { 0 });
            for (int i = 0; i < 12; i++) await session.Discover(1);
            await Fails(() => session.Login(Key, "test")); await Fails(() => session.Status(Key)); await Fails(() => session.Binary(Key, [3, 0, 0, 0])); await Fails(() => session.Cli(Key, "ver"));
            Equal(12, t.Sent.Count(f => f[0] is 26 or 27 or 50 or 55 || f[0] == 2 && f[1] == 1)); Assert(!session.RequiresReconnect);
        });
        await Test("Explicit reauthentication stops diagnostics and can renew admin", async () =>
        {
            var (_, model, _) = await AdminModel(); model.SetMonitoring(true); await model.Login("test", false);
            Assert(model.Admin && !model.Monitoring); Equal(null, model.Error);
        });
        await Test("Known routes require companion contacts and actual flood invalidates them", async () =>
        {
            AdvancingClock clock = new(); Fake t = new(); using MeshSession session = new(t, pacer: clock.Pacer());
            var contact = Contact(); contact[35] = 0; t.Emit(contact); Equal(ServiceRoute.Known, session.RouteFor(Key));
            t.Emit([0x80, .. Enumerable.Repeat((byte)0xee, 32)]); Equal(ServiceRoute.Known, session.RouteFor(Key));
            t.Emit([0x81, .. Key]); Equal(ServiceRoute.FloodOrUnknown, session.RouteFor(Key));
            t.Emit(contact); t.Emit([2, 0, 0, 0, 0]); Equal(ServiceRoute.FloodOrUnknown, session.RouteFor(Key));
            t.Emit(contact); t.Handle = _ => { t.Emit([6, 1, .. Codec.U32(1), .. Codec.U32(2000)]); t.Emit([0x85, 1, .. Key[..6]]); };
            await session.Login(Key, "test"); Equal(ServiceRoute.FloodOrUnknown, session.RouteFor(Key));
        });
        await Test("Old library migrates without starting diagnostics or losing health history", async () =>
        {
            string folder = Path.Combine(Path.GetTempPath(), "MeshCore-migration-" + Guid.NewGuid()); Directory.CreateDirectory(folder);
            try
            {
                await File.WriteAllTextAsync(Path.Combine(folder, "library.json"), "{\"Version\":1,\"Defaults\":{\"MonitorMinutes\":5,\"AutoReconnect\":false},\"Monitoring\":true}");
                LocalStore store = new(folder); AccountDocument archive = new() { Account = Id };
                archive.Nodes[Id] = new() { Samples = [new(DateTimeOffset.UtcNow, (RepeaterStatus)Codec.Decode([0x87, 0, .. Key[..6], .. Status()]).Payload!)] };
                await store.Save("account-" + Id + ".json", archive, a => a.Validate());
                Fake transport = new(); LocalReplies(transport); Controller model = new(transport, new MemoryCredentials(), store, pacer: new AdvancingClock().Pacer());
                await model.Start(); Equal(240, model.Options.DiagnosticMinutes); Equal(3, model.Options.DiagnosticSamples); Assert(!model.Monitoring && !model.Options.AutoReconnect);
                await model.Initialize(123); transport.Emit(Contact()); await model.SelectNode(Id);
                Equal(1, model.Operations.Samples.Count); Assert(!model.Monitoring);
                Assert(transport.Sent.All(f => f[0] is 22 or 1 or 20 or 10));
            }
            finally { Directory.Delete(folder, true); }
        });
        await Test("Clock rollback stops diagnostic schedule instead of extending it", () =>
        {
            var start = DateTimeOffset.UtcNow; DiagnosticMeasurement run = new(new(240, 3, ServiceRoute.Known), start);
            Assert(!run.TakeDue(start.AddSeconds(-1), false)); Assert(!run.Running && run.Next == null);
        });
        await Test("CLI drains replies arriving during pacing before the new command", async () =>
        {
            AdvancingClock clock = new(); Fake transport = new(); Queue<string> queue = new(); uint timestamp = 1;
            ServiceTrafficGovernor governor = new(clock, (wait, _) => { queue.Enqueue("> stale"); clock.Advance(wait); return Task.CompletedTask; });
            using MeshSession session = new(transport, pacer: clock.Pacer(), traffic: governor);
            transport.Handle = frame => {
                if (frame[0] == 10) transport.Emit(queue.Count == 0 ? [10] : Message(queue.Dequeue(), 1, timestamp++));
                else { queue.Enqueue("> " + System.Text.Encoding.UTF8.GetString(frame[13..])); transport.Emit(Sent()); }
            };
            Equal("> first", await session.Cli(Key, "first")); Equal("> second", await session.Cli(Key, "second"));
            Equal(2, transport.Sent.Count(f => f[0] == 2));
        });
    }
}
