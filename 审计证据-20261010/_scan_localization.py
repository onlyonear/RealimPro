#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""只读审计：解析 Localizable.strings，扫描 Swift 中 NSLocalizedString key，
输出 漏key（代码用了但 strings 表没有）与 未使用 key。"""
import os, re, sys, json

ROOT = "/Users/onlyonear/Desktop/Improlyze/Real imPro"
STRINGS = os.path.join(ROOT, "en.lproj", "Localizable.strings")

# 1) parse strings table: "key" = "value";
kv = {}
order = []
with open(STRINGS, encoding="utf-8") as f:
    for line in f:
        m = re.match(r'\s*"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)"\s*;', line)
        if m:
            k, v = m.group(1), m.group(2)
            kv[k] = v
            order.append(k)

print(f"# strings table entries: {len(kv)}")

# 2) collect swift files
swift_files = []
for dp, dn, fn in os.walk(ROOT):
    for x in fn:
        if x.endswith(".swift"):
            swift_files.append(os.path.join(dp, x))

# 3) find NSLocalizedString("KEY"  and  String(localized:) etc.
# pattern: NSLocalizedString("...."
nls_re = re.compile(r'NSLocalizedString\(\s*"((?:[^"\\]|\\.)*)"')
used = {}  # key -> list of (file, line)
for path in swift_files:
    rel = os.path.relpath(path, ROOT)
    with open(path, encoding="utf-8") as f:
        for i, line in enumerate(f, 1):
            for m in nls_re.finditer(line):
                key = m.group(1)
                used.setdefault(key, []).append(f"{rel}:{i}")

print(f"# distinct NSLocalizedString keys used in code: {len(used)}")

# 4) missing keys (used but not in table)
missing = {k: v for k, v in used.items() if k not in kv}
print("\n===== MISSING KEYS (used in code, absent from .strings -> fallback shows raw key) =====")
for k in sorted(missing):
    print(f"KEY: {k}")
    for loc in missing[k]:
        print(f"    {loc}")

# 5) unused keys (in table but never referenced)
unused = [k for k in kv if k not in used]
print("\n===== UNUSED KEYS (in .strings, never referenced) =====")
for k in unused:
    print(f"  {k}  =>  {kv[k]}")

# 6) keys that are Chinese (will fallback to Chinese if missing)
print("\n===== CHINESE KEYS present in table (fallback risk if missing) =====")
cjk = re.compile(r'[一-鿿]')
ch_keys = [k for k in kv if cjk.search(k)]
print(f"  count Chinese keys in table: {len(ch_keys)}")
