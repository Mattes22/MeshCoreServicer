using System.Buffers.Binary;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json.Serialization;

namespace MeshCore.Core;

public sealed class MeshException(string message) : Exception(message);
public record Contact(byte[] Key, byte Kind, string Name, uint LastAdvert, double Latitude, double Longitude, bool Stored)
{
    public string Id => Convert.ToHexStringLower(Key);
    public string Type => Kind switch { 1 => "Companion", 2 => "Repeater", 3 => "Room server", 4 => "Senzor", _ => "Neznámý" };
    public byte Flags { get; init; }
    public byte PathLength { get; init; } = 255;
    public byte[] Path { get; init; } = new byte[64];
    public override string ToString() => $"{Name} · {Type} · {(Stored ? "uložený kontakt" : "objevený uzel")}";
}
public record SelfInfo(byte[] Key, string Name, double Frequency, double Bandwidth, byte Sf, byte Cr) { public string Id => Convert.ToHexStringLower(Key); }
public record DeviceInfo(byte Protocol, byte Channels, string Build, string Model, string Version);
public record Receipt(bool Flood, uint Ack, uint Timeout);
public record Incoming(byte[] Prefix, byte Path, byte Type, uint Timestamp, string Text, double? Snr, byte[]? Sender = null)
{ public string Identity => $"{Convert.ToHexStringLower(Prefix)}:{Type}:{Timestamp}:{Convert.ToHexStringLower(Sender ?? [])}:{Text}"; }
public record ChannelIncoming(byte Index, byte Path, byte Type, uint Timestamp, string Text, double? Snr)
{ public string Identity => $"channel:{Index}:{Type}:{Timestamp}:{Text}"; }
public sealed class ChannelInfo(byte index, string name, byte[] secret)
{
    private readonly byte[] key = secret.Length == 16 ? secret.ToArray() : throw new MeshException("Klíč kanálu musí mít 16 bajtů.");
    public byte Index { get; } = index;
    public string Name { get; } = name;
    public string Fingerprint => Convert.ToHexStringLower(SHA256.HashData(key));
    public string Id => $"channel:{Index}:{Fingerprint}";
    public bool Configured => Name.Length != 0 || key.Any(b => b != 0);
    public string DisplayName => string.IsNullOrEmpty(Name) ? $"Kanál {Index}" : Name;
    public override string ToString() => DisplayName;
    public string PacketFingerprint(uint timestamp, string wireText)
    {
        if (!Configured || Encoding.UTF8.GetByteCount(wireText) > 160 || wireText.Contains('\0')) throw new MeshException("Neplatný text kanálu.");
        byte[] plain = new byte[((5 + Encoding.UTF8.GetByteCount(wireText) + 15) / 16) * 16];
        BinaryPrimitives.WriteUInt32LittleEndian(plain, timestamp); Encoding.UTF8.GetBytes(wireText).CopyTo(plain, 5);
        using var aes = Aes.Create(); aes.Key = key;
        var encrypted = aes.EncryptEcb(plain, PaddingMode.None);
        byte[] hmacKey = new byte[32]; key.CopyTo(hmacKey, 0);
        var mac = HMACSHA256.HashData(hmacKey, encrypted);
        return Convert.ToHexStringLower(SHA256.HashData([5, SHA256.HashData(key)[0], mac[0], mac[1], .. encrypted]));
    }
}
public record Observation(string Fingerprint, int? Hops, sbyte Rssi, double Snr);
public record Discovery(byte[] Key, uint Tag, byte Kind, sbyte CompanionRssi, double CompanionSnr, double RepeaterSnr);
public record RepeaterStatus(ushort Battery, ushort Queue, short Noise, short LastRssi, uint Received, uint Sent, uint TxAirtime, uint Uptime,
    uint SentFlood, uint SentDirect, uint ReceivedFlood, uint ReceivedDirect, ushort Errors, double LastSnr, ushort DirectDuplicates, ushort FloodDuplicates, uint? RxAirtime, uint? ReceiveErrors)
{
    public static RepeaterStatus Decode(byte[] bytes)
    {
        var r = new Reader(bytes);
        return new(r.U16(), r.U16(), r.I16(), r.I16(), r.U32(), r.U32(), r.U32(), r.U32(), r.U32(), r.U32(), r.U32(), r.U32(), r.U16(), r.I16() / 4d,
            r.U16(), r.U16(), r.Remaining >= 4 ? r.U32() : null, r.Remaining >= 4 ? r.U32() : null);
    }
    [JsonIgnore] public string Display => $"Baterie {Battery / 1000d:F3} V · uptime {TimeSpan.FromSeconds(Uptime)} · RX {Received} · TX {Sent}\nPoslední paket přijatý repeaterem: RSSI {LastRssi} dBm · SNR {LastSnr:F2} dB · odesílatel neurčen\nNoise floor {Noise} dBm · fronta {Queue} · TX airtime {TxAirtime} s · RX airtime {RxAirtime?.ToString() ?? "nedostupné"} s";
}
public sealed class Reader(byte[] bytes)
{
    private int position;
    public int Remaining => bytes.Length - position;
    public byte[] Bytes(int count)
    {
        if (count < 0 || count > Remaining) throw new MeshException("Zkrácený nebo neplatný rámec.");
        var result = bytes.AsSpan(position, count).ToArray(); position += count; return result;
    }
    public byte U8() => Bytes(1)[0];
    public sbyte I8() => unchecked((sbyte)U8());
    public ushort U16() => BinaryPrimitives.ReadUInt16LittleEndian(Bytes(2));
    public short I16() => BinaryPrimitives.ReadInt16LittleEndian(Bytes(2));
    public uint U32() => BinaryPrimitives.ReadUInt32LittleEndian(Bytes(4));
    public int I32() => BinaryPrimitives.ReadInt32LittleEndian(Bytes(4));
    public string Text(int? count = null) { var b = Bytes(count ?? Remaining); var n = Array.IndexOf(b, (byte)0); return Encoding.UTF8.GetString(b, 0, n < 0 ? b.Length : n); }
}
public record Frame(byte Code, object? Payload = null, byte[]? Prefix = null, uint Tag = 0);
public static class Codec
{
    public const string FirmwareCommit = "81dbae592ffad40b4212bc0b37e82b38da08f4bc";
    public static readonly Guid Service = new("6E400001-B5A3-F393-E0A9-E50E24DCCA9E");
    public static readonly Guid Rx = new("6E400002-B5A3-F393-E0A9-E50E24DCCA9E");
    public static readonly Guid Tx = new("6E400003-B5A3-F393-E0A9-E50E24DCCA9E");
    public static byte[] U32(uint value) { byte[] d = new byte[4]; BinaryPrimitives.WriteUInt32LittleEndian(d, value); return d; }
    public static byte[] BleFrame(byte[] frame, int maximum = 176)
    { if (frame.Length is < 1 or > 176 || frame.Length > maximum) throw new MeshException("Rámec se nevejde do jednoho BLE zápisu; fragmentace není podporována."); return frame; }
    public static byte[] Key(string value)
    { if (value.Length != 64 || !value.All(Uri.IsHexDigit)) throw new MeshException("Veřejný klíč musí mít 64 hexadecimálních znaků."); return Convert.FromHexString(value); }
    public static void ValidateText(string text, int limit = 133)
    { if (string.IsNullOrWhiteSpace(text) || text.Contains('\0') || Encoding.UTF8.GetByteCount(text) > limit) throw new MeshException($"Text musí mít 1–{limit} UTF-8 bajtů, bez NUL."); }
    public static byte[] Direct(byte[] key, string text, uint time, bool cli = false)
    {
        ValidateText(text); if (key.Length != 32 || (cli && text.Any(c => c is '\r' or '\n'))) throw new MeshException("Neplatný klíč nebo víceřádkový CLI příkaz.");
        return [2, (byte)(cli ? 1 : 0), 0, .. U32(time), .. key[..6], .. Encoding.UTF8.GetBytes(text)];
    }
    public static byte[] Login(byte[] key, string password)
    { if (key.Length != 32 || password.Contains('\0') || Encoding.UTF8.GetByteCount(password) > 15) throw new MeshException("Heslo nejvýše 15 UTF-8 bajtů."); return [26, .. key, .. Encoding.UTF8.GetBytes(password)]; }
    public static byte[] SendChannel(byte index, string text, string sender, uint time)
    { ValidateText(text, Math.Max(0, Math.Min(133, 160 - Encoding.UTF8.GetByteCount(sender) - 2))); return [3, 0, index, .. U32(time), .. Encoding.UTF8.GetBytes(text)]; }
    public static byte[] AddContact(Contact c)
    {
        if (c.Key.Length != 32 || c.Path.Length != 64 || Encoding.UTF8.GetByteCount(c.Name) > 31) throw new MeshException("Neplatný kontakt nebo příliš dlouhý název.");
        byte[] name = new byte[32]; Encoding.UTF8.GetBytes(c.Name).CopyTo(name, 0);
        return [9, .. c.Key, c.Kind, c.Flags, c.PathLength, .. c.Path, .. name, .. U32(c.LastAdvert), .. U32(unchecked((uint)(int)(c.Latitude * 1e6))), .. U32(unchecked((uint)(int)(c.Longitude * 1e6)))];
    }
    public static int? Hops(byte path) => path != 255 && (path >> 6) < 3 && (path & 63) * ((path >> 6) + 1) <= 64 ? path & 63 : null;
    public static Observation? Observe(byte[] raw, sbyte rssi, double snr)
    {
        var r = new Reader(raw); var header = r.U8(); int route = header & 3;
        if ((header >> 6) != 0 || ((header >> 2) & 15) != 5) return null;
        if (route is 0 or 3) r.Bytes(4);
        var path = r.U8(); int size = (path >> 6) + 1, count = path & 63;
        if (size > 3 || size * count > 64) throw new MeshException("Neplatná cesta rádiového paketu.");
        r.Bytes(size * count); var payload = r.Bytes(r.Remaining);
        if (payload.Length < 19 || (payload.Length - 3) % 16 != 0) throw new MeshException("Neplatný skupinový payload.");
        return new(Convert.ToHexStringLower(SHA256.HashData([5, .. payload])), route is 0 or 1 ? count : null, rssi, snr);
    }
    public static Frame Decode(byte[] bytes)
    {
        BleFrame(bytes); var r = new Reader(bytes); byte code = r.U8();
        switch (code)
        {
            case 0: case 10: case 0x83: return new(code);
            case 1: return new(code, r.Remaining > 0 ? r.U8() : (byte)0);
            case 2: case 4: return new(code, r.U32());
            case 3: case 0x8a:
                var key = r.Bytes(32); byte kind = r.U8(), flags = r.U8(), path = r.U8(); var route = r.Bytes(64);
                var name = r.Text(32); var advert = r.U32(); double lat = r.I32() / 1e6, lon = r.I32() / 1e6; r.U32();
                return new(code, new Contact(key, kind, name, advert, lat, lon, code == 3) { Flags = flags, PathLength = path, Path = route });
            case 5:
                r.Bytes(3); var own = r.Bytes(32); r.Bytes(12); double f = r.U32() / 1000d, bw = r.U32() / 1000d; byte sf = r.U8(), cr = r.U8();
                return new(code, new SelfInfo(own, r.Text(), f, bw, sf, cr));
            case 6: return new(code, new Receipt(r.U8() != 0, r.U32(), r.U32()));
            case 7: case 16:
                double? snr = null; if (code == 16) { snr = r.I8() / 4d; r.Bytes(2); }
                var prefix = r.Bytes(6); byte dmPath = r.U8(), type = r.U8(); uint time = r.U32(); var sender = type == 2 ? r.Bytes(4) : null;
                return new(code, new Incoming(prefix, dmPath, type, time, r.Text(), snr, sender));
            case 8: case 17:
                double? groupSnr = null; if (code == 17) { groupSnr = r.I8() / 4d; r.Bytes(2); }
                byte index = r.U8(), groupPath = r.U8(), groupType = r.U8(); uint groupTime = r.U32();
                return new(code, new ChannelIncoming(index, groupPath, groupType, groupTime, r.Text(), groupSnr));
            case 12: return new(code, r.U16());
            case 13:
                byte version = r.U8(); if (version < 3) return new(code, new DeviceInfo(version, 0, "", "", ""));
                r.U8(); var channels = r.U8(); r.Bytes(4); // BLE PIN is deliberately neither exposed nor logged.
                return new(code, new DeviceInfo(version, channels, r.Text(12), r.Text(40), r.Text(20)));
            case 18: var channel = r.U8(); var channelName = r.Text(32); return new(code, new ChannelInfo(channel, channelName, r.Bytes(16)));
            case 0x80: case 0x81: return new(code, Prefix: r.Bytes(32));
            case 0x82: return new(code, r.U32(), Tag: r.U32());
            case 0x85: var permission = r.U8(); return new(code, permission, r.Bytes(6));
            case 0x86: r.U8(); return new(code, Prefix: r.Bytes(6));
            case 0x87: r.U8(); var statusPrefix = r.Bytes(6); return new(code, RepeaterStatus.Decode(r.Bytes(r.Remaining)), statusPrefix);
            case 0x88:
                var obsSnr = r.I8() / 4d; var obsRssi = r.I8(); return new(code, Observe(r.Bytes(r.Remaining), obsRssi, obsSnr));
            case 0x8c: r.U8(); uint tag = r.U32(); return new(code, r.Bytes(r.Remaining), Tag: tag);
            case 0x8e:
                double discoverySnr = r.I8() / 4d; sbyte discoveryRssi = r.I8(); r.U8(); byte info = r.U8();
                if ((info & 0xf0) != 0x90) return new(code);
                double remoteSnr = r.I8() / 4d; uint discoveryTag = r.U32(); var discoveryKey = r.Bytes(r.Remaining);
                if (discoveryKey.Length is not (8 or 32)) throw new MeshException("Neplatná délka discovery klíče.");
                return new(code, new Discovery(discoveryKey, discoveryTag, (byte)(info & 15), discoveryRssi, discoverySnr, remoteSnr));
            default: return new(code);
        }
    }
}
