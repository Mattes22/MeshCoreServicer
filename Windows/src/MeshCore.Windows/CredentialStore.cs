using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using MeshCore.Core;

namespace MeshCore.Windows;

public sealed class CredentialStore : ICredentialStore
{
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)] private struct Credential
    {
        public uint Flags, Type; public string TargetName; public string? Comment; public long LastWritten; public uint CredentialBlobSize; public IntPtr CredentialBlob; public uint Persist, AttributeCount; public IntPtr Attributes; public string? TargetAlias, UserName;
    }
    [DllImport("advapi32.dll", EntryPoint = "CredReadW", CharSet = CharSet.Unicode, SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)] private static extern bool Read(string target, uint type, uint flags, out IntPtr credential);
    [DllImport("advapi32.dll", EntryPoint = "CredWriteW", CharSet = CharSet.Unicode, SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)] private static extern bool Write(ref Credential credential, uint flags);
    [DllImport("advapi32.dll", EntryPoint = "CredDeleteW", CharSet = CharSet.Unicode, SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)] private static extern bool DeleteNative(string target, uint type, uint flags);
    [DllImport("advapi32.dll")] private static extern void CredFree(IntPtr credential);
    private static string Target(string key) { Codec.Key(key); return "MeshCoreServicer/Admin/" + key.ToLowerInvariant(); }
    private static void Failure() => throw new MeshException("Správce přihlašovacích údajů Windows odmítl operaci (kód " + Marshal.GetLastWin32Error() + "). Heslo se nezapisuje do souboru.");
    public string? Load(string node)
    {
        if (!Read(Target(node), 1, 0, out var pointer)) { if (Marshal.GetLastWin32Error() == 1168) return null; Failure(); }
        try { var credential = Marshal.PtrToStructure<Credential>(pointer); byte[] bytes = new byte[credential.CredentialBlobSize]; try { Marshal.Copy(credential.CredentialBlob, bytes, 0, bytes.Length); return Encoding.UTF8.GetString(bytes); } finally { CryptographicOperations.ZeroMemory(bytes); } }
        finally { CredFree(pointer); }
    }
    public void Save(string node, string password)
    {
        var target = Target(node); Codec.Login(Codec.Key(node), password); byte[] bytes = Encoding.UTF8.GetBytes(password); var pointer = Marshal.AllocHGlobal(bytes.Length);
        try { Marshal.Copy(bytes, 0, pointer, bytes.Length); Credential credential = new() { Type = 1, TargetName = target, UserName = "MeshCore repeater", CredentialBlobSize = (uint)bytes.Length, CredentialBlob = pointer, Persist = 2 }; if (!Write(ref credential, 0)) Failure(); }
        finally { CryptographicOperations.ZeroMemory(bytes); for (int i = 0; i < bytes.Length; i++) Marshal.WriteByte(pointer, i, 0); Marshal.FreeHGlobal(pointer); }
    }
    public void Delete(string node) { if (!DeleteNative(Target(node), 1, 0) && Marshal.GetLastWin32Error() != 1168) Failure(); }
}
