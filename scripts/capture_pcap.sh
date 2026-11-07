#!/system/bin/sh
# 设备端抓包：DNS 查询 + TLS SNI + QUIC 端口，用于定位 App 的广告域名
# 用法: su -c "sh /data/local/tmp/capture_pcap.sh [时长秒] [输出文件] [网卡] [包名]"
# 默认抓 30 秒到 /data/local/tmp/capture.pcap，网卡 ccmni1
#
# 第 4 个参数是可选的「冷启动包名」：传入后脚本会先 force-stop 该 App，
# 再启动它，专门抓开屏广告在冷启动头几秒发出的请求。
# force-stop 只结束进程、不删除任何数据；不会重启手机、不影响 root。
DUR="${1:-30}"
OUT="${2:-/data/local/tmp/capture.pcap}"
IFACE="${3:-ccmni1}"
PKG="${4:-}"

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
if [ -n "$PKG" ]; then
  sleep 1
  am force-stop "$PKG" >/dev/null 2>&1
  # vivo / Android 16 的 root shell 里 monkey 未必能拉起 App，
  # 显式解析 launcher activity 并指定 --user 0 更可靠；vivo 实测通过。
  ACT=$(cmd package resolve-activity --brief \
        -c android.intent.category.LAUNCHER "$PKG" 2>/dev/null | grep -m1 '/')
  [ -n "$ACT" ] && am start --user 0 -n "$ACT" >/dev/null 2>&1
  # 兜底：仍尝试 monkey（shell 用户下通常可用）
  pidof "$PKG" >/dev/null 2>&1 \
    || monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
  sleep 1
  if pidof "$PKG" >/dev/null 2>&1; then
    echo "已冷启动: $PKG（pid $(pidof "$PKG")，仅结束进程，未清除数据）"
  else
    echo "[!] $PKG 启动失败，本次抓包可能无效，请手动打开 App 后重跑"
  fi
fi
sleep "$DUR"
kill "$PID" 2>/dev/null
wait "$PID" 2>/dev/null
echo "完成: $(ls -lh "$OUT" 2>/dev/null | awk '{print $5}')"
