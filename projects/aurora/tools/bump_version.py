#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
bump_version.py — 每次构建自动递增 FPGA 固件版本号(点分式)。

版本号形如 M.m.p(主.次.修订, 每段 0..255), 写入 tools/aurora_regs.json;
gen_regs.py 把它编码进 32bit VERSION 寄存器:
    [31:24]主  [23:16]次  [15:8]修订  [7:0]保留(=0)
每次调用把 修订(p) +1, 满 255 进位到次(m), 次满 255 进位到主(M)
(1.0.254 -> 1.0.255 -> 1.1.0)。

用法:
  python3 tools/bump_version.py          # 递增并同步重生成 .vh/.h/regs (默认开启同步)
  python3 tools/bump_version.py --no-gen # 仅写回 aurora_regs.json, 不同步(易致漂移, 仅调试)
  python3 tools/bump_version.py --gen    # (兼容) 等价默认: 递增并同步重生成

已被 scripts/fpga.py `build` 自动调用(build 前自增一次并重生成 RTL)。
上电后用 PS 读 VERSION 寄存器(0x40000004) e.g.: 1.0.1 -> 0x01000100。
"""
import argparse
import io
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
JSON = os.path.join(HERE, "aurora_regs.json")
GEN = os.path.join(HERE, "gen_regs.py")


def parse(s):
    s = s.strip()
    if s.lower().startswith("0x"):
        v = int(s, 0)
        return [(v >> 24) & 0xFF, (v >> 16) & 0xFF, (v >> 8) & 0xFF]
    parts = [int(x) for x in s.split(".")]
    if not (1 <= len(parts) <= 3):
        raise ValueError("version 应为 M.m.p 点分格式: %s" % s)
    parts = parts + [0] * (3 - len(parts))
    if any(not 0 <= x <= 255 for x in parts):
        raise ValueError("version 每段需在 0..255: %s" % s)
    return parts


def bump(maj, mi, patch):
    patch += 1
    if patch > 255:
        patch = 0
        mi += 1
        if mi > 255:
            mi = 0
            maj += 1
    if maj > 255:
        raise ValueError("主版本越界(>255): %d.%d.%d" % (maj, mi, patch))
    return maj, mi, patch


def main() -> int:
    ap = argparse.ArgumentParser(description="递增 FPGA 固件版本号(点分式 M.m.p, 修订+1)")
    ap.add_argument("--gen", action="store_true",
                    help="(默认) 写回 JSON 后自动重跑 gen_regs.py 同步 .vh/.h/regs")
    ap.add_argument("--no-gen", dest="no_gen", action="store_true",
                    help="仅写回 JSON, 跳过 regen(不推荐: 会造成 json/vh/h 版本漂移)")
    ap.add_argument("--set", choices=["major", "minor", "patch"], default="patch",
                    help="递增哪一段(默认 patch=修订); minor/major 时清低段")
    args = ap.parse_args()

    with io.open(JSON, "r", encoding="utf-8") as f:
        data = json.load(f)
    old = parse(str(data["version"]))
    if args.set == "patch":
        new = bump(old[0], old[1], old[2])
    elif args.set == "minor":
        new = (old[0], old[1] + 1, 0)
    else:
        new = (old[0] + 1, 0, 0)
    new = (min(new[0], 255), min(new[1], 255), min(new[2], 255))
    data["version"] = "%d.%d.%d" % new

    with io.open(JSON, "w", encoding="utf-8", newline="\n") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
        f.write("\n")

    print("old version = %d.%d.%d" % tuple(old))
    print("new version = %d.%d.%d" % tuple(new))

    if not args.no_gen:
        subprocess.check_call([sys.executable, GEN])
        # 同步后自检三源一致, 防止版本漂移再发生
        chk = subprocess.run(
            [sys.executable, GEN, "--check"], capture_output=True, text=True)
        if chk.returncode != 0:
            print("[error] gen_regs --check 失败(json/vh/h 不一致):", file=sys.stderr)
            print(chk.stdout, file=sys.stderr)
            print(chk.stderr, file=sys.stderr)
            return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())