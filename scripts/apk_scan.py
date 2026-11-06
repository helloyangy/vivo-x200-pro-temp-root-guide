#!/usr/bin/env python3
"""静态扫描 APK：广告 SDK 标记 + 广告相关域名/URL。

用法: python apk_scan.py app.apk [--sdk] [--domains]

说明:
- 只读 zip 内的 classes*.dex、assets 文本资源, 不解包、不执行
- 对加固 App (dex 加密) 通常扫不到东西, 需要动态抓包
"""
import collections
import io
import re
import sys
import zipfile

SDK_MARKS = [
    "com/qq/e", "com/bytedance/sdk/openadsdk", "com/kwad", "com/baidu/mobads",
    "com/mbridge/msdk", "com/sigmob", "com/topon", "com/anythink",
    "com/applovin", "com/unity3d/ads", "com/ironsource",
    "com/google/android/gms/ads", "com/umeng", "com/talkingdata",
    "com/gromore", "com/pangle",
]

KEYWORDS = [
    "ad", "ads", "gdt", "pangle", "pangolin", "bytedance", "kuaishou", "kwad",
    "mobads", "mintegral", "mbridge", "sigmob", "topon", "anythink", "applovin",
    "unityads", "ironsource", "doubleclick", "googleads", "umeng", "talkingdata",
    "cnzz", "adview", "gromore", "adcolony", "vungle", "chartboost", "admaster",
    "miaozhen", "irs01", "adchina", "allyes", "advertising", "union", "cps",
]

DOMAIN_RE = re.compile(
    rb"[a-zA-Z0-9][a-zA-Z0-9._-]{2,}\."
    rb"(?:com|cn|net|io|org|cc|top|xyz|tv|me|app|info|biz|vip|site|cloud|api|gg|co)\b"
)
STR_RE = re.compile(rb"[ -~]{4,}")


def scan_text(data, marks, domains, counter):
    for mark in SDK_MARKS:
        if mark.encode() in data:
            marks.add(mark)
    for s in STR_RE.findall(data):
        low = s.lower()
        if not any(k.encode() in low for k in KEYWORDS):
            continue
        for d in DOMAIN_RE.findall(s):
            counter[d.decode("ascii", "ignore")] += 1
        if b"http" in low:
            domains.add(s.decode("ascii", "ignore")[:200])


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 1
    apk = sys.argv[1]
    show_sdk = "--domains" not in sys.argv
    show_domains = "--sdk" not in sys.argv

    marks = set()
    urls = set()
    counter = collections.Counter()

    with zipfile.ZipFile(apk) as z:
        names = [n for n in z.namelist()
                 if (n.startswith("classes") and n.endswith(".dex"))
                 or (n.startswith("assets/") and n.lower().endswith((".json", ".xml", ".txt", ".js", ".html", ".jar")))
                 or n.startswith("res/raw")]
        for name in names:
            try:
                data = z.read(name)
            except Exception:
                continue
            if len(data) > 120 * 1024 * 1024:
                continue
            scan_text(data, marks, urls, counter)
            if name.lower().endswith(".jar"):
                try:
                    inner = zipfile.ZipFile(io.BytesIO(data))
                    for jn in inner.namelist():
                        try:
                            scan_text(inner.read(jn), marks, urls, counter)
                        except Exception:
                            pass
                except Exception:
                    pass

    if show_sdk:
        print("=== 广告 SDK 标记 ===")
        for m in sorted(marks):
            print("  " + m)
        if not marks:
            print("  (未命中, 可能已加固或使用动态加载)")

    if show_domains:
        print("\n=== 广告相关域名 ===")
        for d, c in counter.most_common():
            print("  %-50s %d" % (d, c))
        if urls:
            print("\n=== 含 http 的字符串 (前 20) ===")
            for u in sorted(urls)[:20]:
                print("  " + u)

    return 0


if __name__ == "__main__":
    sys.exit(main())
