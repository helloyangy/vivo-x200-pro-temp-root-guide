#!/system/bin/sh
# 趣智校园 (com.klcxkj.zqxy) 第三方广告域名拦截 —— 旧版回退脚本
#
# 保留不动，作为最小可用的回退路径：新方案出问题时可用它恢复最初的效果。
# 日常请改用全局版：scripts/adblock_all.sh + scripts/ad_domains.txt
# （hosts 是全局的，全局版只是把域名清单换成覆盖所有 App 的通用广告 SDK 清单，
#   并额外提供 dry-run、备份、--rollback；两者写入位置相同，规则兼容。）
#
# 依赖：root（hosts 写入）+ StevenBlock 模块（可选）
# 仅拦截广告 SDK 域名，不影响 App 业务功能

SYS=/system/etc/hosts
MOD=/data/adb/modules/stevenblock/system/etc/hosts
BLOCK=/data/adb/stevenblock/rules/block.list

DOMAINS="
api.yfanads.com
tracker.yfanads.com
adx-data.yfanads.com
yfanads.com
api-access.pangolin-sdk-toutiao.com
api-access.pangolin-sdk-toutiao1.com
log-api.pangolin-sdk-toutiao.com
sf3-fe-tos.pglstatp-toutiao.com
sf6-fe-tos.pglstatp-toutiao.com
s3-fe-scm.pglstatp-toutiao.com
pglstatp-toutiao.com
pglstatp-toutiao-b.com
pangolin-sdk-toutiao.com
pangolin-sdk-toutiao-b.com
gromore.pangolin-sdk-toutiao.com
s.1rtb.net
sdk.1rtb.net
cdn.1rtb.com
dc.sigmob.cn
adservice.sigmob.cn
rtbcallback.sigmob.cn
adxtool.sigmob.cn
tbsasv.sigmob.cn
ads.sigmob.cn
api.sigmob.cn
sdk.sigmob.cn
log.sigmob.cn
track.sigmob.cn
ws.sigmob.cn
rtb.sigmob.cn
dg.sigmob.cn
adx.sigmob.cn
cdn.sigmob.cn
img.sigmob.cn
static.sigmob.cn
sigmob.cn
sdk.beizi.biz
beizi.biz
ad.beizi.biz
api.beizi.biz
ad.lovefree.cc
ad.shunchangzhixing.com
ad-api.adn-plus.com.cn
mores.anythinktech.com
adx-bj.anythinktech.com
onlineapi.anythinktech.com
tk.anythinktech.com
api.anythinktech.com
dsp-api-cn.metricslinks.com
sdktmp.hubcloud.com.cn
sdk.tianmu.mobi
vhs.wwstat.com
c.etoolads.cn
etoolads.cn
s.tuia.cn
tuia.cn
vcs.zijieapi.com
ad.api2.jindaixx.com
jindaixx.com
api.jindaixx.com
adxvip.com
s.adxvip.com
aggrx.com
ipv4.gdt.qq.com
gdt.qq.com
sdk.e.qq.com
sdkquic.e.qq.com
win.gdt.qq.com
v.gdt.qq.com
v2.gdt.qq.com
v3.gdt.qq.com
v3mi.gdt.qq.com
v2mi.gdt.qq.com
mi.gdt.qq.com
c.gdt.qq.com
c2.gdt.qq.com
c3.gdt.qq.com
t.gdt.qq.com
rpt.gdt.qq.com
nc.gdt.qq.com
union.eff.qq.com
qzs.gdtimg.com
adsmind.ugdtimg.com
pgdt.ugdtimg.com
gdtimg.com
ugdtimg.com
open.e.kuaishou.com
open.e.kuaishou.cn
api.kuaishouzt.com
api.kwaizt.com
zt.gifshow.com
ulog-sdk.gifshow.com
ulog-sdk.ksapisrv.com
mobads.baidu.com
mobads-logs.baidu.com
"

N=0
for d in $DOMAINS; do
  if [ -f "$SYS" ]; then
    grep -qE "^0\.0\.0\.0 $d$" "$SYS" || { echo "0.0.0.0 $d" >> "$SYS"; N=$((N+1)); }
  fi
  if [ -f "$MOD" ]; then
    grep -qE "^0\.0\.0\.0 $d$" "$MOD" || echo "0.0.0.0 $d" >> "$MOD"
  fi
  if [ -f "$BLOCK" ]; then
    grep -qxF "$d" "$BLOCK" || echo "$d" >> "$BLOCK"
  fi
done

echo "新增到系统 hosts: $N 条"
[ -f "$SYS" ] && echo "系统 hosts 总行数: $(wc -l < $SYS)"
echo "验证 api.yfanads.com: $(grep -c 'api.yfanads.com' /proc/1/root/system/etc/hosts)"
