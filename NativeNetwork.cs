// SPDX-License-Identifier: Unlicense
using System;
using System.ComponentModel;
using System.Net;
using System.Net.Sockets;
using System.Runtime.InteropServices;

// Only documented IP Helper read/query and ICMP APIs are used; no policy or route changes.
public static class NativeNetwork {
    [StructLayout(LayoutKind.Explicit, Size=28)]
    struct SockaddrInet {
        [FieldOffset(0)] public ushort Family;
        [FieldOffset(4)] public uint IPv4;
    }
    [DllImport("iphlpapi.dll", ExactSpelling=true)]
    static extern uint GetBestRoute2(IntPtr luid, uint index, ref SockaddrInet source, ref SockaddrInet destination, uint options, IntPtr route, out SockaddrInet bestSource);
    [DllImport("iphlpapi.dll", ExactSpelling=true, SetLastError=true)]
    static extern IntPtr IcmpCreateFile();
    [DllImport("iphlpapi.dll", ExactSpelling=true, SetLastError=true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    static extern bool IcmpCloseHandle(IntPtr handle);
    [DllImport("iphlpapi.dll", ExactSpelling=true, SetLastError=true)]
    static extern uint IcmpSendEcho2Ex(IntPtr handle, IntPtr evt, IntPtr apc, IntPtr context, uint source, uint destination, byte[] request, ushort requestSize, IntPtr options, IntPtr reply, uint replySize, uint timeout);
    static uint Address(IPAddress value) {
        if(value.AddressFamily!=AddressFamily.InterNetwork) throw new ArgumentException("Esta função requer IPv4.");
        return BitConverter.ToUInt32(value.GetAddressBytes(),0);
    }
    public static void VerifyRoute(IPAddress source, IPAddress destination, int index) {
        if(index<=0) throw new ArgumentException("Índice de interface IPv4 indisponível.");
        var from=new SockaddrInet {Family=2,IPv4=Address(source)};
        var to=new SockaddrInet {Family=2,IPv4=Address(destination)};
        SockaddrInet bestSource;
        // MIB_IPFORWARD_ROW2 begins with NET_LUID (8 bytes) and NET_IFINDEX (4).
        // A 256-byte buffer accommodates the full structure on supported Windows architectures.
        IntPtr buffer=Marshal.AllocHGlobal(256);
        try {
            uint result=GetBestRoute2(IntPtr.Zero,(uint)index,ref from,ref to,0,buffer,out bestSource);
            if(result!=0) throw new InvalidOperationException("Sem rota pela interface selecionada: "+new Win32Exception((int)result).Message);
            if(Marshal.ReadInt32(buffer,8)!=index || bestSource.Family!=2 || bestSource.IPv4!=from.IPv4) throw new InvalidOperationException("A rota ou a origem não corresponde à Ethernet selecionada.");
        } finally {Marshal.FreeHGlobal(buffer);}
    }
    public static uint Echo(IPAddress source, IPAddress destination, out uint latency) {
        latency=0;
        IntPtr handle=IcmpCreateFile();
        if(handle==new IntPtr(-1) || handle==IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error());
        IntPtr reply=IntPtr.Zero;
        try {
            reply=Marshal.AllocHGlobal(256);
            byte[] request=new byte[32];
            uint count=IcmpSendEcho2Ex(handle,IntPtr.Zero,IntPtr.Zero,IntPtr.Zero,Address(source),Address(destination),request,(ushort)request.Length,IntPtr.Zero,reply,256,1000);
            if(count==0) { uint error=(uint)Marshal.GetLastWin32Error(); return error==0?1:error; }
            // The first three DWORD fields of ICMP_ECHO_REPLY have identical offsets on x86/x64.
            uint status=unchecked((uint)Marshal.ReadInt32(reply,4));
            uint responder=unchecked((uint)Marshal.ReadInt32(reply,0));
            if(status==0 && responder!=Address(destination)) throw new InvalidOperationException("Resposta de origem inesperada.");
            latency=unchecked((uint)Marshal.ReadInt32(reply,8));
            return status;
        } finally {if(reply!=IntPtr.Zero) Marshal.FreeHGlobal(reply); IcmpCloseHandle(handle);}
    }
}
