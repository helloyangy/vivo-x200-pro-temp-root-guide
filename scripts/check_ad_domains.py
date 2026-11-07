#!/usr/bin/env python3
"""静态校验全局广告域名清单，防止误拦业务/推送/支付域名。

用法:
  python scripts/check_ad_domains.py [清单文件] [--hosts 设备hosts文件] [--allow allow.list]

只做本地静态检查，不联网、不连设备、不写任何文件。
退出码 0 = 通过，1 = 存在必须修正的问题。
"""
import argparse
import os
import re
import sys
from collections import Counter, OrderedDict

# 这些是核心业务域名的「顶点」。清单里不能出现它们本身，也不能出现它们的父域
# （例如写了 qq.com，就会连带把 gdt.qq.com、weixin.qq.com 等全挡掉）。
PROTECTED_EXACT = {
    "qq.com", "weixin.qq.com", "wechat.com", "tencent.com", "weibo.com",
    "weibo.cn", "sina.com.cn", "baidu.com", "taobao.com", "tmall.com",
    "alipay.com", "jd.com", "360buyimg.com", "1688.com", "bytedance.com",
    "douyin.com", "kuaishou.com", "zhihu.com", "bilibili.com",
    "xiaohongshu.com", "meituan.com", "dianping.com", "pinduoduo.com",
    "google.com", "googleapis.com", "gstatic.com", "youtube.com",
    "apple.com", "icloud.com", "microsoft.com", "vivo.com", "vivo.com.cn",
    "mi.com", "oppo.com", "huawei.com", "hicloud.com", "aliyun.com",
    "tencentcloudapi.com", "umeng.com", "jpush.cn", "getui.com",
    "igexin.com", "tpns.tencent.com", "localhost", "local", "arpa",
}

# 推送 / 账号 / 支付 / 登录 相关关键字，出现在任何域名里都视为危险。
FORBIDDEN_TOKENS = (
    "jpush", "getui", "igexin", "tpns", "weixin", "alipay", "passport",
    "oauth", "login", "account", "pay.", "payment", ".push.", "push-",
    "auth.", "auth-", "360buyimg", "alicdn", "tbcdn",
)

# 合法域名：小写字母/数字/连字符组成的标签，至少一个点，不含通配符与端口。
DOMAIN_RE = re.compile(
    r"^(?=.{1,253}$)[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?"
    r"(?:\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)+$"
)
IPV4_RE = re.compile(r"^[0-9.]+$")
GROUP_RE = re.compile(r"^#\s*===\s*(.+?)\s*===")


def parse(path):
    groups = OrderedDict()
    current = "未分组"
    with open(path, encoding="utf-8", errors="replace") as fh:
        for lineno, raw in enumerate(fh, 1):
            line = raw.rstrip("\r\n")
            stripped = line.strip()
            if not stripped:
                continue
            gm = GROUP_RE.match(stripped)
            if gm:
                current = gm.group(1)
                groups.setdefault(current, [])
                continue
            if stripped.startswith("#"):
                continue  # 注释行（含默认关闭的可选条目）
            # 允许行尾注释
            domain = stripped.split("#", 1)[0].strip().lower()
            groups.setdefault(current, []).append((lineno, domain))
    return groups


def check_domain(domain):
    problems = []
    if not DOMAIN_RE.match(domain):
        problems.append("域名格式非法（大小写/通配符/端口/路径/标签长度）")
        return problems
    if IPV4_RE.match(domain):
        problems.append("不能写 IP 地址")
    if any(tok in domain for tok in FORBIDDEN_TOKENS):
        problems.append("命中推送/账号/支付/共享 CDN 关键字，禁止拦截")
    for protected in PROTECTED_EXACT:
        if domain == protected or protected.endswith("." + domain):
            problems.append("是核心业务域名 %s 本身或其父域，会连带破坏正常功能" % protected)
            break
    return problems


def read_hosts_domains(path):
    if not path:
        return None
    out = set()
    with open(path, encoding="utf-8", errors="ignore") as fh:
        for line in fh:
            parts = line.split()
            if len(parts) >= 2 and parts[0] in ("0.0.0.0", "127.0.0.1", "::1"):
                out.add(parts[1].lower())
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("listfile", nargs="?",
                    default=os.path.join(os.path.dirname(__file__), "ad_domains.txt"))
    ap.add_argument("--hosts", help="可选：从设备 pull 下来的 hosts，用于统计覆盖率")
    ap.add_argument("--allow", help="可选：StevenBlock 的 allow.list，用于检查冲突")
    args = ap.parse_args()

    if not os.path.isfile(args.listfile):
        print("清单文件不存在: %s" % args.listfile)
        return 1
    groups = parse(args.listfile)

    seen = {}
    errors = []
    all_domains = []
    for group, items in groups.items():
        for lineno, domain in items:
            problems = check_domain(domain)
            if domain in seen:
                problems.append("重复，首次出现在第 %d 行" % seen[domain])
            else:
                seen[domain] = lineno
            if problems:
                errors.append((lineno, domain, problems))
            else:
                all_domains.append(domain)

    print("分组统计：")
    for group, items in groups.items():
        active = sum(1 for _, d in items if d not in ("",))
        print("  %-28s %3d 条" % (group, active))
    print("\n有效域名: %d 个（去重后 %d 个）"
          % (sum(len(v) for v in groups.values()), len(set(all_domains))))
    print("问题条目: %d 个" % len(errors))

    if args.allow and os.path.isfile(args.allow):
        allow = {l.strip().lower() for l in open(args.allow, encoding="utf-8",
                                                 errors="ignore") if l.strip()}
        conflict = sorted(set(all_domains) & allow)
        if conflict:
            print("\n[!] 与 allow.list 冲突（StevenBlock 会优先放行，规则无效）:")
            for d in conflict:
                print("    " + d)

    hosts = read_hosts_domains(args.hosts)
    if hosts is not None:
        covered = sorted(set(all_domains) & hosts)
        print("\n设备 hosts 已有: %d / %d 条，本次将新增约 %d 条"
              % (len(covered), len(set(all_domains)),
                 len(set(all_domains) - hosts)))

    if errors:
        print("\n必须修正：")
        for lineno, domain, problems in errors:
            print("  第 %d 行  %-42s %s" % (lineno, domain, "；".join(problems)))
        return 1
    print("\nPASS: 未发现危险域名。仍需真机 dry-run 后再 --apply。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
