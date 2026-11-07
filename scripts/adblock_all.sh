#!/system/bin/sh
# 全局开屏广告拦截（设备端）
#
# 适用范围：手机上所有 App。hosts 本来就是全局的，这里只是把规则源从
# 「趣智校园专用清单」换成「通用广告 SDK 清单」。
#
# 安全设计（针对 GhostLock 临时 root）：
#   * 默认 dry-run，只有显式 --apply 才写入
#   * 只写 StevenBlock 的 bind mount 文件与规则源，绝不写真实 /system 分区
#   * 不重启、不软重启、不 force-stop、不删 App 数据、不动 zygote
#   * 写入前整份备份，--rollback 可精确还原到上一次应用前的状态
#   * 幂等：已存在的规则不会重复追加
#   * 拒绝拦截业务/推送/支付/共享 CDN 域名
#   * 单次最多 1000 条规则（StevenBlock 上限），超出直接中止
#
# 用法（在电脑上）：
#   adb push scripts/ad_domains.txt /data/local/tmp/ad_domains.txt
#   adb push scripts/adblock_all.sh  /data/local/tmp/adblock_all.sh
#   adb shell su -c "sh /data/local/tmp/adblock_all.sh"                 # 预览
#   adb shell su -c "sh /data/local/tmp/adblock_all.sh --apply"          # 应用
#   adb shell su -c "sh /data/local/tmp/adblock_all.sh --rollback"       # 还原
#   adb shell su -c "sh /data/local/tmp/adblock_all.sh --rules-only"     # 只写规则源
#   adb shell su -c "sh /data/local/tmp/adblock_all.sh --rules /path/to/list --apply"
#
# 注意：临时 root 下请勿为了「让规则生效」而重启手机 —— 重启会丢 root，
# 必须重跑 GhostLock。本脚本的设计目标就是「当场生效、零重启」。

SYS=/system/etc/hosts
MOD=/data/adb/modules/stevenblock/system/etc/hosts
BLOCK=/data/adb/stevenblock/rules/block.list
ALLOW=/data/adb/stevenblock/rules/allow.list
RULEFILE=/data/local/tmp/ad_domains.txt
BACKUP_ROOT=/data/local/tmp/adblock_all_backup
MAX_RULES=1000
MODE=preview

die()  { echo "[ABORT] $*"; exit 1; }
info() { echo "$*"; }

usage() {
  sed -n '2,28p' "$0"
  exit 0
}

while [ $# -gt 0 ]; do
  case "$1" in
    --apply)      MODE=apply; shift ;;
    --rules-only) MODE=rulesonly; shift ;;
    --rollback)   MODE=rollback; shift ;;
    --dry-run)    MODE=preview; shift ;;
    --rules)      [ -n "${2:-}" ] || die "--rules 缺少路径"; RULEFILE=$2; shift 2 ;;
    -h|--help)    usage ;;
    *)            die "未知参数: $1（可用 --apply / --rules-only / --rollback / --dry-run / --rules / -h）" ;;
  esac
done

[ "$(id -u)" = "0" ] || die "需要 root；请先确认 GhostLock 提权仍然有效（adb shell su -c id）"
[ -f "$SYS" ] || die "找不到 $SYS"
[ -f "$BLOCK" ] || die "找不到 StevenBlock 规则文件 $BLOCK（模块未安装？）"

TMP=/data/local/tmp/adblock_all.$$
cleanup() { rm -f "$TMP".domains "$TMP".valid "$TMP".invalid "$TMP".havehosts \
                    "$TMP".havemod "$TMP".havemod2 "$TMP".hosts_todo \
                    "$TMP".mod_todo "$TMP".mod_todo2 "$TMP".rules_todo; }
trap cleanup EXIT
trap 'cleanup; exit 1' HUP INT TERM

# ---------------------------------------------------------------- 还原
latest_backup() {
  ls -1 "$BACKUP_ROOT" 2>/dev/null | sort | tail -n 1
}

restore_from() {
  _bd=$1
  [ -n "$_bd" ] && [ -d "$BACKUP_ROOT/$_bd" ] || die "没有可用备份（$BACKUP_ROOT 为空）"
  info "从备份还原: $BACKUP_ROOT/$_bd"
  # 用 cat 重定向而非 mv/cp 覆盖，保持 bind mount 指向的 inode 不变
  [ -f "$BACKUP_ROOT/$_bd/hosts" ] && cat "$BACKUP_ROOT/$_bd/hosts" > "$SYS" \
    || die "备份里的 hosts 缺失"
  if [ -f "$BACKUP_ROOT/$_bd/module_hosts" ] && [ -f "$MOD" ]; then
    cat "$BACKUP_ROOT/$_bd/module_hosts" > "$MOD" || die "模块 hosts 还原失败"
  fi
  if [ -f "$BACKUP_ROOT/$_bd/block.list" ]; then
    cat "$BACKUP_ROOT/$_bd/block.list" > "$BLOCK" || die "规则列表还原失败"
  fi
  grep -q '^127.0.0.1 localhost' "$SYS" || die "还原后 hosts 校验失败，请检查 StevenBlock WebUI"
  info "还原完成。备份仍保留，未删除任何文件。"
  info "hosts 行数: $(wc -l < "$SYS")；block.list 行数: $(wc -l < "$BLOCK")"
}

if [ "$MODE" = rollback ]; then
  restore_from "$(latest_backup)"
  exit 0
fi

# ---------------------------------------------------------------- 解析清单
[ -f "$RULEFILE" ] || die "找不到规则清单 $RULEFILE（先 adb push 上去）"

sed 's/#.*//' "$RULEFILE" | tr -d '\r' | tr 'A-Z' 'a-z' \
  | awk 'NF {print $1}' | sort -u > "$TMP.domains"

: > "$TMP.valid"
: > "$TMP.invalid"

while IFS= read -r d; do
  [ -n "$d" ] || continue
  # 合法域名：小写字母/数字/连字符 + 至少一个点，无通配符/端口/路径/IP
  if ! printf '%s\n' "$d" | grep -qE '^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$' \
     || printf '%s\n' "$d" | grep -qE '^[0-9.]+$'; then
    echo "$d" >> "$TMP.invalid"; continue
  fi
  # 推送 / 账号 / 支付 / 共享 CDN：一律拒绝
  case "$d" in
    *jpush*|*getui*|*igexin*|*tpns*|*weixin*|*alipay*|*passport*|*oauth*|*login*|*account*|*360buyimg*|*alicdn*|*tbcdn*)
      echo "$d" >> "$TMP.invalid"; continue ;;
  esac
  # 核心业务域名的顶点或其父域：一律拒绝（双重保险，与本地校验脚本一致）
  bad=0
  for p in qq.com weixin.qq.com weibo.com weibo.cn baidu.com taobao.com tmall.com \
           alipay.com jd.com 1688.com bytedance.com douyin.com kuaishou.com \
           zhihu.com bilibili.com xiaohongshu.com meituan.com pinduoduo.com \
           google.com googleapis.com gstatic.com apple.com icloud.com \
           vivo.com mi.com oppo.com huawei.com aliyun.com tencent.com \
           jpush.cn getui.com igexin.com umeng.com; do
    case "$p" in
      "$d"|*."$d") bad=1; break ;;
    esac
  done
  [ "$bad" = 0 ] || { echo "$d" >> "$TMP.invalid"; continue; }
  # 与白名单冲突时跳过（StevenBlock 会优先放行，写了也没用）
  if [ -f "$ALLOW" ] && grep -qxF "$d" "$ALLOW"; then
    echo "$d" >> "$TMP.invalid"; continue
  fi
  printf '%s\n' "$d" >> "$TMP.valid"
done < "$TMP.domains"

NVALID=$(wc -l < "$TMP.valid")
NINVALID=$(wc -l < "$TMP.invalid")
[ "$NVALID" -gt 0 ] || die "清单里没有有效域名"

# ---------------------------------------------------------------- 计算差量
awk '$1 == "0.0.0.0" {print $2}' "$SYS" | sort -u > "$TMP.havehosts"
awk -v hf="$TMP.havehosts" 'BEGIN{while((getline l < hf)>0){sub(/\r$/,"",l); h[l]=1}} !($0 in h){print}' \
  "$TMP.valid" > "$TMP.hosts_todo"

if [ -f "$MOD" ]; then
  awk '$1 == "0.0.0.0" {print $2}' "$MOD" | sort -u > "$TMP.havemod"
  awk -v hf="$TMP.havemod" 'BEGIN{while((getline l < hf)>0){sub(/\r$/,"",l); h[l]=1}} !($0 in h){print}' \
    "$TMP.valid" > "$TMP.mod_todo"
else
  : > "$TMP.mod_todo"
fi

awk -v hf="$BLOCK" 'BEGIN{while((getline l < hf)>0){sub(/\r$/,"",l); h[l]=1}} !($0 in h){print}' \
  "$TMP.valid" > "$TMP.rules_todo"

NHOSTS=$(wc -l < "$TMP.hosts_todo")
NMOD=$(wc -l < "$TMP.mod_todo")
NRULES=$(wc -l < "$TMP.rules_todo")
NBLOCK=$(wc -l < "$BLOCK")

SI=$(stat -Lc '%d:%i' "$SYS" 2>/dev/null || true)
MI=$(stat -Lc '%d:%i' "$MOD" 2>/dev/null || true)
if [ -n "$SI" ] && [ "$SI" = "$MI" ]; then SAME=1; else SAME=0; fi

if grep -q " /system/etc/hosts " /proc/mounts; then MOUNTED=1; else MOUNTED=0; fi

# ---------------------------------------------------------------- 预览
info "=== 全局开屏广告拦截 / 预览 ==="
info "清单:            $RULEFILE"
info "有效域名:        $NVALID 个（其中跳过非法/危险/白名单 $NINVALID 个）"
info "系统 hosts:      待新增 $NHOSTS 条（当前 $(wc -l < "$SYS") 行）"
info "模块 hosts:      待新增 $NMOD 条（与系统 hosts 同一 inode: $SAME）"
info "block.list:      待新增 $NRULES 条（当前 $NBLOCK 行，上限 $MAX_RULES）"
info "挂载检查:        /system/etc/hosts $([ "$MOUNTED" = 1 ] && echo '是 bind mount（可安全写入）' || echo '不是 bind mount（禁止写入）')"
if [ "$NINVALID" -gt 0 ]; then
  info "--- 被跳过的条目 ---"
  cat "$TMP.invalid"
fi
if [ "$NHOSTS" -gt 0 ]; then
  info "--- hosts 新增示例（最多 15 条）---"
  head -n 15 "$TMP.hosts_todo"
fi
if [ "$NRULES" -gt 0 ]; then
  info "--- block.list 新增示例（最多 15 条）---"
  head -n 15 "$TMP.rules_todo"
fi
[ "$((NBLOCK + NRULES))" -le "$MAX_RULES" ] \
  || die "规则总数将达 $((NBLOCK + NRULES))，超过 StevenBlock 上限 $MAX_RULES，已中止"

if [ "$MODE" = preview ]; then
  info ""
  info "DRY-RUN：未写入任何文件。确认无误后加 --apply 才会生效。"
  exit 0
fi

# ---------------------------------------------------------------- 写入
# 只有需要写 hosts 的模式才要求 bind mount，避免碰到真实 /system 分区
if [ "$MODE" = apply ]; then
  [ "$MOUNTED" = 1 ] \
    || die "/system/etc/hosts 不是 StevenBlock 的挂载文件，拒绝写真实系统分区。请重跑 GhostLock 后再试，或改用 --rules-only 只更新规则源。"
  grep -q '^127.0.0.1 localhost' "$SYS" \
    || die "hosts 缺少 localhost 基线行，疑似损坏，拒绝写入"
fi

TS=$(date +%Y%m%d_%H%M%S)
BD="$BACKUP_ROOT/$TS"
mkdir -p "$BD" || die "无法创建备份目录 $BD"
cp -p "$SYS" "$BD/hosts" || die "hosts 备份失败"
[ -f "$MOD" ] && cp -p "$MOD" "$BD/module_hosts"
cp -p "$BLOCK" "$BD/block.list" || die "block.list 备份失败"
{ echo "time=$TS"; echo "mode=$MODE"; echo "rules=$RULEFILE";
  echo "hosts_lines_before=$(wc -l < "$SYS")";
  echo "block_lines_before=$NBLOCK"; } > "$BD/info.txt"
info "备份: $BD"

ensure_newline() {
  _f=$1
  _last=$(tail -c 1 "$_f" | od -An -tu1 | tr -d ' \n')
  [ "$_last" = "10" ] || printf '\n' >> "$_f" || die "补尾换行失败: $_f"
}

if [ "$MODE" = apply ]; then
  ensure_newline "$SYS"
  while IFS= read -r d; do
    printf '0.0.0.0 %s\n' "$d" >> "$SYS" || die "写 hosts 失败: $d"
  done < "$TMP.hosts_todo"
  # 关键：写模块 hosts 前重新读一次它的实际内容。
  # 若 SYS 与 MOD 其实是同一个 bind mount inode，写 SYS 后 MOD 已经带上新行，
  # 用旧的差量清单会重复追加；重新计算差量可彻底避免重复。
  if [ "$SAME" = 0 ] && [ -f "$MOD" ]; then
    awk '$1 == "0.0.0.0" {print $2}' "$MOD" | sort -u > "$TMP.havemod2"
    awk -v hf="$TMP.havemod2" 'BEGIN{while((getline l < hf)>0){sub(/\r$/,"",l); h[l]=1}} !($0 in h){print}' \
      "$TMP.valid" > "$TMP.mod_todo2"
    N2=$(wc -l < "$TMP.mod_todo2")
    if [ "$N2" -gt 0 ]; then
      ensure_newline "$MOD"
      while IFS= read -r d; do
        printf '0.0.0.0 %s\n' "$d" >> "$MOD" || die "写模块 hosts 失败: $d"
      done < "$TMP.mod_todo2"
      info "已写入模块 hosts: $N2 条"
    fi
  fi
  info "已写入系统 hosts: $NHOSTS 条"
fi

if [ "$NRULES" -gt 0 ]; then
  ensure_newline "$BLOCK"
  while IFS= read -r d; do
    printf '%s\n' "$d" >> "$BLOCK" || die "写 block.list 失败: $d"
  done < "$TMP.rules_todo"
fi
info "已写入 block.list: $NRULES 条（规则源，重启/模块重建后仍保留）"

# ---------------------------------------------------------------- 校验
bad=0
if [ "$MODE" = apply ]; then
  while IFS= read -r d; do
    grep -qxF "0.0.0.0 $d" "$SYS" || { info "校验失败: $d"; bad=1; }
  done < "$TMP.hosts_todo"
  grep -q '^127.0.0.1 localhost' "$SYS" || { info "校验失败: localhost 基线行丢失"; bad=1; }
fi
while IFS= read -r d; do
  grep -qxF "$d" "$BLOCK" || { info "校验失败: block.list 缺少 $d"; bad=1; }
done < "$TMP.rules_todo"
[ "$(wc -l < "$BLOCK")" -le "$MAX_RULES" ] || { info "校验失败: 规则数超上限"; bad=1; }

if [ "$bad" != 0 ]; then
  info "校验未通过，自动还原到写入前状态…"
  restore_from "$TS"
  die "已还原，手机状态未改变"
fi

info ""
info "=== 完成（未重启，root 会话保持）==="
info "系统 hosts: $(wc -l < "$SYS") 行；block.list: $(wc -l < "$BLOCK") 行"
if [ "$MODE" = rulesonly ]; then
  info "仅更新了规则源，当前 hosts 未改动，要等 StevenBlock 重建 hosts 才生效。"
  info "临时 root 下不要为此重启手机；建议直接跑 --apply 当场生效。"
else
  info "生效无需重启；个别 App 有 DNS 缓存，开关一次飞行模式或重开该 App 即可。"
fi
info "如需撤销: adb shell su -c \"sh /data/local/tmp/adblock_all.sh --rollback\""
