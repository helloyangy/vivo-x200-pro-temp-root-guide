#!/usr/bin/env python3
"""解析 uiautomator dump 的 XML，列出可见文本与 resource-id。

用法:
  adb shell uiautomator dump /sdcard/ui.xml
  adb pull /sdcard/ui.xml
  python ui_dump.py ui.xml [关键字]

用于定位广告位/推广位的控件（例如 task_adv_channel_*、item_activity_*），
判断内容来自第三方 SDK 还是 App 自有业务接口。
"""
import re
import sys


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 1
    path = sys.argv[1]
    keyword = sys.argv[2].lower() if len(sys.argv) > 2 else None

    text = open(path, encoding="utf-8", errors="ignore").read()
    for m in re.finditer(r"<node[^>]*>", text):
        seg = m.group(0)
        t = re.search(r'text="([^"]*)"', seg)
        rid = re.search(r'resource-id="([^"]*)"', seg)
        cls = re.search(r'class="([^"]*)"', seg)
        label = t.group(1).strip() if t else ""
        res = rid.group(1) if rid else ""
        if not label and not res:
            continue
        if keyword and keyword not in (label + res).lower():
            continue
        print("TXT: %s  | rid=%s | cls=%s"
              % (label, res, cls.group(1) if cls else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main())
