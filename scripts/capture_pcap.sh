#!/system/bin/sh
# 设备端抓包：DNS 查询 + TLS SNI + QUIC 端口，用于定位 App 的广告域名
# 用法: su -c "sh /data/local/tmp/capture_pcap.sh [时长秒] [输出文件] [网卡]"
# 默认抓 30 秒到 /data/local/tmp/capture.pcap
DUR="${1:-30}"
OUT="${2:-/data/local/tmp/capture.pcap}"
IFACE="${3:-ccmni1}"

TCPDUMP=""
for p in /system/bin/tcpdump /system/xbin/tcpdump /data/local/tmp/tcpdump; do
  [ -x "$p" ] && TCPDUMP="$p" && break
done
if [ -z "$TCPDUMP" ]; then
  echo "未找到 tcpdump。可先安装含 tcpdump 的模块（例如 StevenBlock 自带的 busybox）"
  exit 1
fi

# 手机流量卡通常走 ccmni1；连 Wi-Fi 时可能是 wlan0
if ! ip link show "$IFACE" >/dev/null 2>&1; then
  echo "[!] 网卡 $IFACE 不存在，可用网卡:"
  ip -o link show | awk -F': ' '{print "  " $2}'
  exit 1
fi

rm -f "$OUT"
echo "抓包 $DUR 秒: $IFACE -> $OUT"
"$TCPDUMP" -i "$IFACE" -n -s 0 -w "$OUT" \
  'udp port 53 or tcp port 443 or udp port 443' 2>/dev/null &
PID=$!
sleep "$DUR"
kill "$PID" 2>/dev/null
wait "$PID" 2>/dev/null
echo "完成: $(ls -lh "$OUT" 2>/dev/null | awk '{print $5}')"
