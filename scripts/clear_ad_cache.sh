#!/system/bin/sh
# 清理趣智校园 (com.klcxkj.zqxy) 的广告素材缓存
# 不会删除 App 业务数据，仅移动广告 SDK 缓存目录到备份位置

PKG=com.klcxkj.zqxy
D=/data/user/0/$PKG
BACK=/data/local/tmp/zqxy_adcache_backup

am force-stop "$PKG"
sleep 1
mkdir -p "$BACK"

for p in cache/wind cache/beizi cache/image_manager_disk_cache \
  cache/pangle_com.byted.pangle/tt_ad cache/jt_video_cache \
  cache/sdm cache/sdm_optres cache/ksdsdk_ziptmp \
  cache/pangle_com.byted.pangle cache/pangle_com.byted.live.lite \
  files/tktp files/anythink files/anythink_optres files/BeiZi \
  files/gdt_database files/jcaches files/ksadsdk files/sdm \
  files/sdm_optres files/app_tt_pangle_bykv_file files/ksdsdk_ziptmp
do
  if [ -e "$D/$p" ]; then
    n=$(echo "$p" | tr '/' '_')
    rm -rf "$BACK/$n"
    mv "$D/$p" "$BACK/$n" 2>/dev/null
  fi
done

ls -la "$BACK"
