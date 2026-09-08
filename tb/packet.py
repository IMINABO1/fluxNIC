"""Build real Ethernet/IPv4/UDP frames as bytes and chunk them into AXI-Stream
words, so parser/rewrite tests run against genuine on-the-wire layouts."""
import struct


def ip_checksum(data: bytes) -> int:
    s = 0
    for i in range(0, len(data), 2):
        w = (data[i] << 8) | (data[i + 1] if i + 1 < len(data) else 0)
        s += w
    while s >> 16:
        s = (s & 0xFFFF) + (s >> 16)
    return (~s) & 0xFFFF


def mac(s: str) -> bytes:
    return bytes(int(x, 16) for x in s.split(":"))


def ip(s: str) -> bytes:
    return bytes(int(x) for x in s.split("."))


def ip_int(s: str) -> int:
    return int.from_bytes(ip(s), "big")


def udp_ipv4_frame(dst_mac, src_mac, src_ip, dst_ip, src_port, dst_port,
                   payload=b"", proto=17, ethertype=0x0800):
    eth = mac(dst_mac) + mac(src_mac) + struct.pack("!H", ethertype)
    udp_len = 8 + len(payload)
    l4 = struct.pack("!HHHH", src_port, dst_port, udp_len, 0) + payload
    total_len = 20 + len(l4)
    ip_hdr = (struct.pack("!BBHHHBBH", 0x45, 0, total_len, 0, 0, 64, proto, 0)
              + ip(src_ip) + ip(dst_ip))
    ip_hdr = ip_hdr[:10] + struct.pack("!H", ip_checksum(ip_hdr)) + ip_hdr[12:]
    return eth + ip_hdr + l4


def words_to_bytes(words, bus_bytes: int = 8):
    """Inverse of to_words for [(tdata_int, tkeep_int)] beats."""
    out = bytearray()
    for data, keep in words:
        for j in range(bus_bytes):
            if keep & (1 << j):
                out.append((data >> (8 * j)) & 0xFF)
    return bytes(out)


def to_words(data: bytes, bus_bytes: int = 8):
    """[(tdata_int, tkeep_int, tlast_bool)] with byte 0 in the lowest lane."""
    words = []
    for off in range(0, len(data), bus_bytes):
        chunk = data[off:off + bus_bytes]
        val = 0
        keep = 0
        for j, b in enumerate(chunk):
            val |= b << (8 * j)
            keep |= 1 << j
        words.append((val, keep, off + bus_bytes >= len(data)))
    return words
