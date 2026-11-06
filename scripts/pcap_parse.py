#!/usr/bin/env python3
"""从 pcap 中提取 DNS 查询名、TLS SNI 与 QUIC 目标 IP。

用法: python pcap_parse.py capture.pcap [--top 20]

说明:
- 只解析, 不依赖 scapy / tshark
- 流量若走 VPN (tun0), 抓到的是代理连接, 域名可能变成节点地址,
  此时应在真实网卡 (如 ccmni1) 上抓包
"""
import collections
import struct
import sys


def read_qname(msg, i):
    labels = []
    while i < len(msg) and msg[i] != 0:
        n = msg[i]
        if n & 0xC0:  # 压缩指针, 这里不处理
            return None
        labels.append(msg[i + 1:i + 1 + n].decode("ascii", "ignore"))
        i += 1 + n
    return ".".join(labels)


def parse(path):
    data = open(path, "rb").read()
    endian = "<" if data[:4] == b"\xd4\xc3\xb2\xa1" else ">"
    off = 24
    dns_names = set()
    quic_ips = collections.Counter()

    while off + 16 <= len(data):
        _, _, incl, _ = struct.unpack(endian + "IIII", data[off:off + 16])
        off += 16
        pkt = data[off:off + incl]
        off += incl
        if len(pkt) < 20 or (pkt[0] >> 4) != 4:
            continue
        ihl = (pkt[0] & 0x0F) * 4
        proto = pkt[9]
        src = ".".join(str(b) for b in pkt[12:16])
        dst = ".".join(str(b) for b in pkt[16:20])

        if proto == 17 and len(pkt) >= ihl + 8:
            udp = pkt[ihl:]
            sport, dport = struct.unpack(">HH", udp[:4])
            payload = udp[8:]
            if dport == 53 and payload and payload[0] >> 3 == 0:
                name = read_qname(payload, 12)
                if name:
                    dns_names.add(name)
            elif dport == 443 or sport == 443:
                quic_ips[dst if dport == 443 else src] += 1

        elif proto == 6 and len(pkt) >= ihl + 20:
            tcp = pkt[ihl:]
            doff = (tcp[12] >> 4) * 4
            payload = tcp[doff:]
            # ClientHello: record type 0x16 + version 0x03xx
            if payload and payload[0] == 0x16 and payload[1] == 0x03:
                hs = payload[5:]
                if hs and hs[0] == 1:
                    p = 4 + 2 + 32
                    sid = hs[p]
                    p += 1 + sid
                    cs = struct.unpack(">H", hs[p:p + 2])[0]
                    p += 2 + cs
                    cm = hs[p]
                    p += 1 + cm
                    et = struct.unpack(">H", hs[p:p + 2])[0]
                    p += 2
                    end = min(p + et, len(hs))
                    while p + 4 <= end:
                        etype, elen = struct.unpack(">HH", hs[p:p + 4])
                        p += 4
                        ed = hs[p:p + elen]
                        p += elen
                        # server_name
                        if etype == 0 and len(ed) >= 2:
                            nl = struct.unpack(">H", ed[:2])[0]
                            dns_names.add(ed[2:2 + nl].decode("ascii", "ignore"))
    return dns_names, quic_ips


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 1
    top = 20
    if "--top" in sys.argv:
        top = int(sys.argv[sys.argv.index("--top") + 1])

    names, quic = parse(sys.argv[1])
    print("DNS / SNI 域名 (%d):" % len(names))
    for n in sorted(names):
        print("  " + n)
    if quic:
        print("\nQUIC (UDP 443) 目标, 前 %d:" % top)
        for ip, c in quic.most_common(top):
            print("  %-16s %d" % (ip, c))
    return 0


if __name__ == "__main__":
    sys.exit(main())
