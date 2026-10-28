namespace MeshCore.Core;

public sealed partial class Controller
{
    private readonly Dictionary<string, (int Count, DateTimeOffset Date, List<Capture> Captures)> observations = [];
    private readonly Dictionary<uint, DateTimeOffset> earlyAcks = [];
    public IReadOnlyList<(string Id, string Title)> Conversations => Channels.Where(c => c.Configured).Select(c => (c.Id, c.DisplayName))
        .Concat(Contacts.Where(c => c.Stored && c.Kind == 1).Select(c => ("dm:" + c.Id[..12], c.Name)))
        .Concat((Archive?.Messages ?? []).Select(m => (m.Conversation, m.Title))).DistinctBy(c => c.Item1).ToArray();
    public IEnumerable<ChatRecord> Messages => (Archive?.Messages ?? []).Where(m => m.Conversation == Conversation);
    public bool Muted => Archive != null && Conversation != null && Library.Muted.Contains(Archive.Account + "/" + Conversation);
    public void SelectConversation(string? id) { Conversation = id; MarkRead(); Update(); }
    public void MarkRead() { if (!ReadingConversation || Conversation == null) return; bool changed = false; foreach (var m in Messages.Where(m => !m.Seen)) { m.Seen = true; changed = true; } if (changed) { Persist(); Update(); } }
    public async Task Mute(bool mute) { if (Archive == null || Conversation == null) return; var key = Archive.Account + "/" + Conversation; if (mute) Library.Muted.Add(key); else Library.Muted.Remove(key); await SaveLibrary(); Update(); }
    public Task RefreshMessages() => Run("Načítám kanály a frontu zpráv…", async () => { if (!Initialized) throw new MeshException("Připojte companion."); if (Device != null) await Session.Channels(Device.Channels); await Session.SyncMessages(); });
    private bool AlreadySeen(string identity) => !accountReady || Archive == null || Archive.Messages.Any(m => m.Deduplication == identity);
    private void AppendIncoming(ChatRecord record)
    {
        if (Archive == null) return; record.Seen = ReadingConversation && Conversation == record.Conversation;
        Archive.Messages.Add(record); Persist();
        if (liveMessages && !record.Seen && Library.Notifications && !Library.Muted.Contains(Archive.Account + "/" + record.Conversation)) NotifyMessage?.Invoke(record);
    }
    private void ReceiveDirect(Incoming m)
    {
        if (m.Type is not (0 or 2) || AlreadySeen(m.Identity)) return;
        var prefix = Convert.ToHexStringLower(m.Prefix); var peers = Contacts.Where(c => c.Id.StartsWith(prefix, StringComparison.Ordinal)).ToArray();
        var title = peers.Length == 1 ? peers[0].Name : "Kontakt " + prefix;
        AppendIncoming(new() { Conversation = "dm:" + prefix, Title = title, Sender = m.Sender == null ? title : "Autor " + Convert.ToHexStringLower(m.Sender), Text = m.Text, Timestamp = m.Timestamp, Snr = m.Snr, Hops = Codec.Hops(m.Path), Deduplication = m.Identity });
    }
    private void ReceiveChannel(ChannelIncoming m)
    {
        if (m.Type != 0 || AlreadySeen(m.Identity)) return;
        var c = Channels.FirstOrDefault(c => c.Index == m.Index); string? fingerprint = null;
        if (c?.Configured == true) fingerprint = c.PacketFingerprint(m.Timestamp, m.Text);
        if (fingerprint != null && Archive?.Messages.FirstOrDefault(m => m.Outgoing && m.PacketFingerprint == fingerprint) is { } own)
        { own.Hops = Codec.Hops(m.Path); own.Snr = m.Snr; Persist(); return; }
        var split = m.Text.IndexOf(": ", StringComparison.Ordinal); var named = split >= 0 && System.Text.Encoding.UTF8.GetByteCount(m.Text[..split]) <= 31;
        ChatRecord record = new() { Conversation = c?.Id ?? $"channel:{m.Index}:unknown", Title = c?.DisplayName ?? $"Kanál {m.Index}", Sender = named ? m.Text[..split] : "Jméno neuvedeno", Text = named ? m.Text[(split + 2)..] : m.Text, Timestamp = m.Timestamp, Snr = m.Snr, Hops = Codec.Hops(m.Path), Deduplication = m.Identity, PacketFingerprint = fingerprint, Forwardings = fingerprint == null ? null : 0 };
        if (fingerprint != null && observations.TryGetValue(fingerprint, out var o)) { record.Forwardings = o.Count; record.Captures = o.Captures.ToList(); }
        AppendIncoming(record);
    }
    private void Observe(Observation o)
    {
        if (!accountReady || Archive == null) return; var now = DateTimeOffset.UtcNow; var capture = new Capture(now, o.Hops, o.Rssi, o.Snr);
        if (observations.Count >= 512) observations.Remove(observations.MinBy(x => x.Value.Date).Key);
        var value = observations.GetValueOrDefault(o.Fingerprint, (Count: 0, Date: now, Captures: new List<Capture>()));
        value.Count += o.Hops > 0 ? 1 : 0; value.Date = now; value.Captures.Add(capture); value.Captures = value.Captures.TakeLast(64).ToList(); observations[o.Fingerprint] = value;
        foreach (var m in Archive.Messages.Where(m => m.PacketFingerprint == o.Fingerprint)) { m.Forwardings = (m.Forwardings ?? 0) + (o.Hops > 0 ? 1 : 0); m.Captures.Add(capture); m.Captures = m.Captures.TakeLast(64).ToList(); }
        Persist();
    }
    private void Acknowledge(uint code)
    {
        if (Archive == null || code == 0) return; var matches = Archive.Messages.Where(m => m.Outgoing && m.Ack == code && (m.Delivery == "Čekám na ACK" || m.Delivery.StartsWith("ACK nedorazil", StringComparison.Ordinal))).ToArray();
        if (matches.Length == 1) { matches[0].Delivery = "Protějšek potvrdil ACK"; matches[0].AckDeadline = null; earlyAcks.Remove(code); Persist(); }
        else if (matches.Length == 0 && !Archive.Messages.Any(m => m.Ack == code))
        { if (earlyAcks.Count >= 256) earlyAcks.Remove(earlyAcks.MinBy(x => x.Value).Key); earlyAcks[code] = DateTimeOffset.UtcNow; }
    }
    public Task SendMessage(string text) => Run("Předávám zprávu companionu…", async () =>
    {
        if (!Initialized || Self == null || Archive == null || Conversation == null) throw new MeshException("Vyberte připojený companion a konverzaci.");
        var channel = Channels.FirstOrDefault(c => c.Id == Conversation && c.Configured);
        var peers = Contacts.Where(c => Conversation == "dm:" + c.Id[..12]).ToArray();
        var peer = peers.Length == 1 && peers[0].Stored && peers[0].Kind == 1 ? peers[0] : null;
        if (channel == null && peer == null) throw new MeshException("Vyberte aktuální kanál nebo jednoznačný uložený companion kontakt. Text repeateru by se provedl jako CLI.");
        Codec.ValidateText(text, channel == null ? 133 : Math.Max(0, Math.Min(133, 160 - System.Text.Encoding.UTF8.GetByteCount(Self.Name) - 2)));
        var last = Archive.Messages.Where(m => m.Outgoing).Select(m => m.Timestamp).DefaultIfEmpty().Max();
        var timestamp = Math.Max((uint)DateTimeOffset.UtcNow.ToUnixTimeSeconds(), checked(last + 1)); var account = Archive;
        ChatRecord record = new() { Conversation = Conversation, Title = channel?.DisplayName ?? peer!.Name, Sender = Self.Name, Text = text, Timestamp = timestamp, Outgoing = true, Seen = true, Delivery = "Odesílám" };
        if (channel != null) { record.PacketFingerprint = channel.PacketFingerprint(timestamp, Self.Name + ": " + text); record.Forwardings = 0; }
        account.Messages.Add(record); Persist(); Update();
        try
        {
            Receipt? receipt = null;
            if (channel != null) await Session.SendChannel(channel.Index, text, Self.Name, timestamp); else receipt = await Session.SendDirect(peer!.Key, text, timestamp);
            if (!ReferenceEquals(account, Archive) || !Initialized) return;
            if (receipt?.Ack > 0)
            {
                if (account.Messages.Any(m => m != record && m.Ack == receipt.Ack)) record.Delivery = "Kolize ACK · doručení neověřeno";
                else { record.Ack = receipt.Ack; record.AckDeadline = DateTimeOffset.UtcNow.AddMilliseconds(Math.Max(1000, receipt.Timeout) + 3000d); record.Delivery = "Čekám na ACK"; if (earlyAcks.TryGetValue(receipt.Ack, out var when) && when >= record.Date) Acknowledge(receipt.Ack); }
            }
            else record.Delivery = "Přijato companionem · doručení nepotvrzeno";
        }
        catch (Exception e) { record.Delivery = e is RequestRejectedException ? "Companion odmítl" : "Výsledek neověřený · před opakováním zvažte duplicitu"; throw; }
        finally { Persist(); }
    });
}
