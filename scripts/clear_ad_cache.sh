#!/system/bin/sh
# 清理指定 App 的广告 SDK 素材缓存（可逆，只移动不删除）
#
# hosts 拦掉的是「新的」广告请求；已经下载到本地的开屏素材仍可能展示，
# 所以按需清一次缓存。全局化之后不再写死趣智校园，可指定任意 App 包名。
#
# 安全设计：
#   * 默认 dry-run，只有 --apply 才真正移动
#   * 只处理白名单里的「广告 SDK 缓存子目录」，不碰 App 业务数据
#   * mv 到带时间戳的备份目录，绝不 rm -rf，随时可手工放回
#   * 拒绝系统包 / KernelSU 管理器 / 未安装的包
#   * 不重启、不卸载、不清 App 数据（pm clear）、不动 zygote
#
# 用法（电脑上）：
#   adb push scripts/clear_ad_cache.sh /data/local/tmp/clear_ad_cache.sh
#   adb shell su -c "sh /data/local/tmp/clear_ad_cache.sh"                     # 预览趣智校园
#   adb shell su -c "sh /data/local/tmp/clear_ad_cache.sh --apply"             # 执行趣智校园
#   adb shell su -c "sh /data/local/tmp/clear_ad_cache.sh --apply com.xxx.yyy"
#   adb shell su -c "sh /data/local/tmp/clear_ad_cache.sh --apply com.a.b com.c.d"
#
# 注意：一次只传你确实需要的包，不要对全部 App 批量 force-stop。

BACK_ROOT=/data/local/tmp/adcache_backup
MODE=preview
PKGS=""

die()  { echo "[ABORT] $*"; exit 1; }
info() { echo "$*"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --apply) MODE=apply; shift ;;
    --dry-run) MODE=preview; shift ;;
    -h|--help) sed -n '2,22p' "$0"; exit 0 ;;
    -*) die "未知参数: $1" ;;
    *) PKGS="$PKGS $1"; shift ;;
  esac
done
[ -n "$PKGS" ] || PKGS=" com.klcxkj.zqxy"   # 向后兼容：不传包名仍针对趣智校园

[ "$(id -u)" = "0" ] || die "需要 root；请先确认 GhostLock 提权仍然有效"

# 白名单：只碰广告 SDK 自己的缓存目录
PATHS="
cache/wind
cache/beizi
cache/image_manager_disk_cache
cache/pangle_com.byted.pangle/tt_ad
cache/jt_video_cache
cache/sdm
cache/sdm_optres
cache/ksdsdk_ziptmp
cache/pangle_com.byted.pangle
cache/pangle_com.byted.live.lite
files/tktp
files/anythink
files/anythink_optres
files/BeiZi
files/gdt_database
files/jcaches
files/ksadsdk
files/sdm
files/sdm_optres
files/app_tt_pangle_bykv_file
files/ksdsdk_ziptmp
"

info "=== 广告素材缓存清理 / $([ "$MODE" = apply ] && echo 执行 || echo 预览) ==="
for pkg in $PKGS; do
  case "$pkg" in
    android|com.android.*|me.weishu.kernelsu|com.topjohnwu.magisk|*..*)
      die "拒绝处理系统包或保护包: $pkg" ;;
  esac
  printf '%s\n' "$pkg" | grep -qE '^[a-zA-Z][a-zA-Z0-9_]*(\.[a-zA-Z][a-zA-Z0-9_]*)+$' \
    || die "非法包名: $pkg"
  pm path "$pkg" 2>/dev/null | grep -q '^package:' \
    || die "设备上未安装: $pkg"

  D=/data/user/0/$pkg
  [ -d "$D" ] || { info "[$pkg] 无 /data/user/0 目录，跳过"; continue; }

  hits=0
  for p in $PATHS; do
    [ -e "$D/$p" ] && hits=$((hits+1))
  done
  info "[$pkg] 命中白名单缓存目录: $hits 个"

  if [ "$MODE" != apply ]; then
    for p in $PATHS; do
      [ -e "$D/$p" ] && info "    will move: $D/$p"
    done
    continue
  fi

  TS=$(date +%Y%m%d_%H%M%S)
  BACK="$BACK_ROOT/${TS}_$pkg"
  mkdir -p "$BACK" || die "无法创建备份目录 $BACK"

  am force-stop "$pkg" 2>/dev/null
  sleep 1

  moved=0
  for p in $PATHS; do
    [ -e "$D/$p" ] || continue
    n=$(echo "$p" | tr '/' '_')
    dest="$BACK/$n"
    # 目标名冲突时加后缀，绝不覆盖或删除已有备份
    [ -e "$dest" ] && dest="$BACK/${n}_$$"
    if mv "$D/$p" "$dest" 2>/dev/null; then
      moved=$((moved+1))
      info "    moved: $p -> $dest"
    else
      info "    [!] 移动失败（已跳过）: $p"
    fi
  done
  info "[$pkg] 已移动 $moved 个目录到 $BACK（未删除任何文件）"
done

info ""
if [ "$MODE" != apply ]; then
  info "DRY-RUN：未改动任何文件。确认后加 --apply。"
else
  info "完成。缓存目录只是被移走，如需恢复可从 $BACK_ROOT 下的备份手动放回。"
  info "生效无需重启；被 force-stop 的 App 重新打开即可。"
fi
