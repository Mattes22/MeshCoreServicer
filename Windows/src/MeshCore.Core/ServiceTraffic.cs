namespace MeshCore.Core;

public sealed class ServiceOperationCancelledException() : Exception("Servisní požadavek byl zrušen před odesláním: změna relace, oprávnění nebo zastavení měření.");

public enum ServiceRoute { Known, FloodOrUnknown }
public static class ServiceRouting
{
    public static ServiceRoute Classify(byte? path, int bytes = 64) => path is { } p && p != 255 && (p >> 6) < 3 && (p & 63) * ((p >> 6) + 1) <= bytes ? ServiceRoute.Known : ServiceRoute.FloodOrUnknown;
    public static int MinimumMinutes(ServiceRoute route) => route == ServiceRoute.Known ? 30 : 60;
}

// Shared across all remote service commands and retained across BLE resets.
// No unbounded queue; the MeshSession gate owns at most one waiting request.
public sealed class ServiceTrafficGovernor
{
    private readonly TimeProvider clock;
    private readonly Func<TimeSpan, CancellationToken, Task> delay;
    private readonly List<(DateTimeOffset Date, ServiceRoute Route)> sent = [];
    private (DateTimeOffset Date, ServiceRoute Route)? last;
    private DateTimeOffset? scopeStart;
    private int scopeCount;
    private Func<bool>? valid;
    public ServiceTrafficGovernor(TimeProvider? clock = null, Func<TimeSpan, CancellationToken, Task>? delay = null)
    { this.clock = clock ?? TimeProvider.System; this.delay = delay ?? ((duration, token) => Task.Delay(duration, this.clock, token)); }
    public void Begin(Func<bool> valid)
    { if (scopeStart != null) throw new MeshException("Probíhá jiná servisní operace; požadavky se neřadí do fronty."); scopeStart = clock.GetUtcNow(); scopeCount = 0; this.valid = valid; }
    public void ConfirmFlood() { if (last is { } value && sent.Count > 0) { last = (value.Date, ServiceRoute.FloodOrUnknown); sent[^1] = last.Value; } }
    public void End() { scopeStart = null; scopeCount = 0; valid = null; }
    public void ValidateContext()
    {
        if (scopeStart is { } start && clock.GetUtcNow() - start > TimeSpan.FromMinutes(20)) throw new MeshException("Vypršel dvacetiminutový limit servisní operace; další krok se neposlal.");
        if (valid?.Invoke() == false) throw new ServiceOperationCancelledException();
    }
    private void Check(ServiceRoute route)
    {
        var now = clock.GetUtcNow();
        if (scopeStart is { } start && (now - start > TimeSpan.FromMinutes(20) || scopeCount >= 32)) throw new MeshException("Servisní operace dosáhla limitu 32 požadavků nebo 20 minut. Zbývající kroky se neposlaly; načtěte stav ručně.");
        if (valid?.Invoke() == false) throw new ServiceOperationCancelledException();
        if (last is { } previous && now < previous.Date) throw new MeshException("Systémový čas se posunul zpět; servisní požadavek se neposlal.");
        sent.RemoveAll(e => now - e.Date >= TimeSpan.FromHours(1));
        var lane = route == ServiceRoute.Known ? sent : sent.Where(e => e.Route == ServiceRoute.FloodOrUnknown).ToList();
        if (sent.Count >= 60 || route != ServiceRoute.Known && lane.Count >= 12)
        {
            var first = sent.Count >= 60 ? sent[0].Date : lane[0].Date;
            var seconds = Math.Max(1, Math.Ceiling((first.AddHours(1) - now).TotalSeconds));
            throw new MeshException($"Limit sdílené LoRa sítě: nejvýše 60 servisních požadavků/h, z toho 12 bez známé trasy. Zkuste ručně za {seconds} s. Požadavek nebyl zařazen do fronty.");
        }
    }
    public async Task Acquire(ServiceRoute route, Action<string>? progress = null, CancellationToken cancellation = default)
    {
        Check(route);
        if (last is { } previous)
        {
            var gap = TimeSpan.FromSeconds(route == ServiceRoute.Known && previous.Route == ServiceRoute.Known ? 15 : 60);
            var wait = gap - (clock.GetUtcNow() - previous.Date);
            if (wait > TimeSpan.Zero) { progress?.Invoke($"Šetřím LoRa síť: další servisní krok nejdříve za {Math.Ceiling(wait.TotalSeconds)} s ({(route == ServiceRoute.Known ? "uložená trasa" : "flood / neznámá trasa")}). Další operace se neřadí do fronty."); await delay(wait, cancellation); }
        }
        cancellation.ThrowIfCancellationRequested(); Check(route); last = (clock.GetUtcNow(), route); sent.Add(last.Value); scopeCount++;
    }
}

public sealed record DiagnosticPlan
{
    public int IntervalMinutes { get; }
    public int Samples { get; }
    public int DurationMinutes => IntervalMinutes * Samples;
    public DiagnosticPlan(int intervalMinutes, int samples, ServiceRoute route)
    {
        if (intervalMinutes < ServiceRouting.MinimumMinutes(route) || intervalMinutes > 360 || samples is < 1 or > 6 || intervalMinutes * samples > 360) throw new MeshException($"Měření: interval nejméně {ServiceRouting.MinimumMinutes(route)} min, 1–6 vzorků, celkem nejvýše 6 hodin.");
        IntervalMinutes = intervalMinutes; Samples = samples;
    }
}
public sealed class DiagnosticMeasurement(DiagnosticPlan plan, DateTimeOffset start)
{
    public DiagnosticPlan Plan { get; } = plan;
    public DateTimeOffset Started { get; } = start;
    public int Consumed { get; private set; }
    public int Received { get; private set; }
    public int Skipped { get; private set; }
    public bool Running { get; private set; } = true;
    public bool InFlight { get; private set; }
    public bool Transmitted { get; private set; }
    public int Remaining => Plan.Samples - Consumed;
    public DateTimeOffset? Next => Running && Remaining > 0 ? Started.AddMinutes((Consumed + 1) * Plan.IntervalMinutes) : null;
    public bool TakeDue(DateTimeOffset now, bool busy)
    {
        if (now < Started) { Running = false; return false; }
        if (!Running || InFlight || Next is not { } next || now < next) return false;
        if (now - next > TimeSpan.FromSeconds(30)) { int missed = Math.Min(Remaining, (int)((now - next).TotalMinutes / Plan.IntervalMinutes) + 1); Consumed += missed; Skipped += missed; }
        else { Consumed++; if (busy) Skipped++; else { InFlight = true; return true; } }
        if (Remaining == 0) Running = false;
        return false;
    }
    public void MarkTransmitted() { if (InFlight) Transmitted = true; }
    public void Finish(bool success) { if (!InFlight) return; InFlight = false; Transmitted = false; if (success) Received++; else Running = false; if (Remaining == 0) Running = false; }
    public void Stop() => Running = false;
}
