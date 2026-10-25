namespace MeshCore.Core;

// A batch is still strictly sequential. Give both radios time after a reply;
// legacy companions forward the app's whole-second timestamp unchanged.
public sealed class RemoteRequestPacer
{
    private readonly TimeProvider clock;
    private readonly Func<TimeSpan, CancellationToken, Task> delay;
    private long? sentAt;
    private uint lastTimestamp;
    public RemoteRequestPacer(TimeProvider? clock = null, Func<TimeSpan, CancellationToken, Task>? delay = null)
    {
        this.clock = clock ?? TimeProvider.System;
        this.delay = delay ?? ((duration, token) => Task.Delay(duration, this.clock, token));
    }
    public void ReplyReceived() => sentAt = clock.GetTimestamp();
    public async Task<uint> Next(CancellationToken cancellation = default)
    {
        if (sentAt is { } previous)
        {
            var remaining = TimeSpan.FromMilliseconds(1200) - clock.GetElapsedTime(previous);
            if (remaining > TimeSpan.Zero) await delay(remaining, cancellation);
        }
        long now = clock.GetUtcNow().ToUnixTimeSeconds();
        if (now <= lastTimestamp)
        {
            var remaining = DateTimeOffset.FromUnixTimeSeconds(lastTimestamp + 1L) - clock.GetUtcNow();
            if (remaining > TimeSpan.FromSeconds(5)) throw new MeshException("Čas PC se posunul zpět. Opravte systémový čas před dalším vzdáleným požadavkem.");
            await delay(remaining, cancellation); now = clock.GetUtcNow().ToUnixTimeSeconds();
        }
        if (now <= lastTimestamp || now is <= 0 or > uint.MaxValue) throw new MeshException("Nelze vytvořit bezpečnou časovou značku požadavku.");
        sentAt = clock.GetTimestamp(); return lastTimestamp = (uint)now;
    }
    // SENT estimates routing, not the repeater's remaining airtime budget or queue.
    public static TimeSpan CliResponseTimeout(uint estimatedMilliseconds) => TimeSpan.FromSeconds(Math.Clamp(estimatedMilliseconds / 1000d + 15, 45, 180));
}
