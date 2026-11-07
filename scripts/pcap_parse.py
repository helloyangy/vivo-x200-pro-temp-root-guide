#!/usr/bin/env python3
"""从 pcap 中提取 DNS 查询名、TLS SNI 与 QUIC 目标 IP。

用法: python pcap_parse.py capture.pcap [--top 20]

说明:
- 只解析, 不依赖 scapy / tshark
- 同时支持 IPv4 与 IPv6；移动数据常同时下发 v4/v6 DNS，只看 v4 会漏掉
  App 自研网络栈（Cronet 等）的全部请求
- TLS SNI 扩展按 server_name_list 结构解析（2 字节列表长度 +
  1 字节类型 + 2 字节名称长度 + 名称），不能把头当域名
- QUIC 只统计目标 IP：Initial 包里的 ClientHello 是加密的，纯标准库解不开；
  看到大量 UDP 443 而几乎没有 DNS/SNI，就说明 App 绕过了系统 hosts
- 流量若走 VPN (tun0), 抓到的是代理连接, 域名可能变成节点地址,
  此时应在真实网卡 (如 ccmni1) 上抓包
"""
import collections
import socket
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


def ip_hdr(pkt):
    """返回 (协议号, 载荷起点, 源地址, 目的地址)，解析 IPv4 / IPv6 基本头。

    不处理 IPv6 扩展头链；遇到扩展头时返回 None（移动数据里极少见）。
    """
    if len(pkt) < 20:
        return None
    ver = pkt[0] >> 4
    if ver == 4:
        ihl = (pkt[0] & 0x0F) * 4
        if ihl < 20 or len(pkt) < ihl:
            return None
        return pkt[9], ihl, socket.inet_ntop(socket.AF_INET, pkt[12:16]), \
            socket.inet_ntop(socket.AF_INET, pkt[16:20])
    if ver == 6:
        if len(pkt) < 40:
            return None
        nxt = pkt[6]
        if nxt not in (6, 17):
            return None
        return nxt, 40, socket.inet_ntop(socket.AF_INET6, pkt[8:24]), \
            socket.inet_ntop(socket.AF_INET6, pkt[24:40])
    return None


def parse_sni(payload, out):
    """从 TLS ClientHello 的 record payload 里取 server_name。"""
    if len(payload) < 6 or payload[0] != 0x16 or payload[1] != 0x03:
        return
    hs = payload[5:]
    if not hs or hs[0] != 1:  # handshake type 1 = ClientHello
        return
    try:
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
            if etype != 0 or len(ed) < 5:
                continue
            # server_name_list: 2B 列表长度, 然后若干 (1B 类型 + 2B 长度 + 名称)
            list_len = struct.unpack(">H", ed[0:2])[0]
            q, stop = 2, min(2 + list_len, len(ed))
            while q + 3 <= stop:
                ntype = ed[q]
                nlen = struct.unpack(">H", ed[q + 1:q + 3])[0]
                q += 3
                if ntype == 0 and nlen:
                    out.add(ed[q:q + nlen].decode("ascii", "ignore").strip("\x00"))
                q += nlen
    except (IndexError, struct.error):
        return


def parse(path):
    data = open(path, "rb").read()
    endian = "<" if data[:4] == b"\xd4\xc3\xb2\xa1" else ">"
    off = 24
    dns_names = set()
    quic_ips = collections.Counter()
    stats = collections.Counter()

    while off + 16 <= len(data):
        _, _, incl, _ = struct.unpack(endian + "IIII", data[off:off + 16])
        off += 16
        pkt = data[off:off + incl]
        off += incl
        stats["packets"] += 1
        hdr = ip_hdr(pkt)
        if hdr is None:
            stats["skipped"] += 1
            continue
        proto, ihl, src, dst = hdr
        stats["ipv6" if ":" in dst else "ipv4"] += 1

        if proto == 17 and len(pkt) >= ihl + 8:
            udp = pkt[ihl:]
            sport, dport = struct.unpack(">HH", udp[:4])
            payload = udp[8:]
            if dport == 53 and payload and payload[0] >> 3 == 0:
                name = read_qname(payload, 12)
                if name:
                    dns_names.add(name)
                    stats["dns"] += 1
            elif dport == 443 or sport == 443:
                quic_ips[dst if dport == 443 else src] += 1
                stats["quic"] += 1

        elif proto == 6 and len(pkt) >= ihl + 20:
            tcp = pkt[ihl:]
            doff = (tcp[12] >> 4) * 4
            parse_sni(tcp[doff:], dns_names)
    return dns_names, quic_ips, stats


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 1
    top = 20
    if "--top" in sys.argv:
        top = int(sys.argv[sys.argv.index("--top") + 1])

    names, quic, stats = parse(sys.argv[1])
    print("抓包统计: %d 个包，IPv4 %d / IPv6 %d，跳过 %d，DNS 查询 %d，UDP443 %d"
          % (stats["packets"], stats["ipv4"], stats["ipv6"],
             stats["skipped"], stats["dns"], stats["quic"]))
    print("\nDNS / SNI 域名 (%d):" % len(names))
    for n in sorted(x for x in names if x):
        print("  " + n)
    if quic:
        print("\nQUIC (UDP 443) 目标, 前 %d:" % top)
        for ip, c in quic.most_common(top):
            print("  %-40s %d" % (ip, c))
    if stats["quic"] > stats["dns"] * 3:
        print("\n[!] UDP 443 远多于 DNS 查询：流量很可能走 QUIC/HTTP3 或内置 DNS，"
              "域名不可见，且这类连接可能绕过系统 hosts。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
