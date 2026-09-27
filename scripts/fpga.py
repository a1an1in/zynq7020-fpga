#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
fpga.py ---- Zynq7020-FPGA 跨平台统一构建入口 (Windows + Linux/WSL2)

用 法（Windows cmd/PowerShell 和 Linux 完全一致）：
    python scripts/fpga.py build   --top 工程名    # 编译: 建工程+综合+实现+出bit+XSA
    python scripts/fpga.py program --top 工程名    # 烧板: 把 bit 通过 Hardware Manager 写入 FPGA
    python scripts/fpga.py sim     --top 工程名    # 仿真(需在工程下有 testbench，可扩展)
    python scripts/fpga.py clean                   # 清理 build/ 产物

说 明：
    - 不依赖 shell，跨平台安全。
    - 自动定位 vivado：优先环境变量 VIVADO，其次 PATH，再次常见安装路径。
    - 各平台各自生成 build/，互不冲突，均不入 git。
"""
import argparse
import glob
import os
import shutil
import subprocess
import sys
import tempfile
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCRIPTS = os.path.join(ROOT, "scripts")
BUILD = os.path.join(ROOT, "build")

# 常见 Vivado 版本，用于兜底搜索（含本机已安装的 2021.1）
COMMON_VERSIONS = ["2023.2", "2022.2", "2021.2", "2021.1", "2020.2", "2019.2"]


def find_vivado():
    """返回可用的 vivado 命令/完整路径，找不到则返回 'vivado'（尝试交给系统）。"""
    # 1) 显式环境变量
    env = os.environ.get("VIVADO")
    if env:
        return env
    # 2) PATH 里是否已有
    on_path = shutil.which("vivado")
    if on_path:
        return on_path
    # 3) 常见安装路径兜底
    candidates = []
    for v in COMMON_VERSIONS:
        candidates.append(rf"C:\Xilinx\Vivado\{v}\bin\vivado.bat")  # Windows
        candidates.append(f"/opt/Xilinx/Vivado/{v}/bin/vivado")     # Linux
        candidates.append(f"/tools/Xilinx/Vivado/{v}/bin/vivado")   # Linux(其他)
    for c in candidates:
        if os.path.isfile(c):
            return c
    print("[warn] vivado not found; will try to invoke 'vivado' directly. If that "
          "fails, set the environment variable VIVADO=<path to vivado>.")
    return "vivado"


def run(full_cmd):
    """在仓库根目录执行命令，Windows 和 Linux 都通过 shell 跑。
    Windows + UNC(WSL) 根目录：cmd 不允许把 UNC 当作工作目录；更关键的是
    Vivado 的 run 流程会靠 cmd 去 `cd <盘符路径>` 切到各 run 目录，因此工程
    （落在相对 build/ 下）必须是盘符路径。这里先 pushd 自动映射盘符再执行，
    让 python 成为跨平台唯一入口，用户无需手动映射盘符。Linux 直接用真实根目录。
    """
    print("-> " + full_cmd)
    if os.name == "nt" and ROOT.startswith("\\\\"):
        # pushd 在同一个 cmd 会话内分配盘符并 cd 过去（WSL 的 \\wsl.localhost
        # 免凭证，会被映射成盘符路径），随后执行相对 build/ 的工程即落在盘符上。
        full_cmd = 'pushd "{}" && {}'.format(ROOT, full_cmd)
        cwd_arg = None            # 让 pushd 决定工作目录
    else:
        cwd_arg = ROOT
    code = subprocess.call(full_cmd, shell=True, cwd=cwd_arg)
    if code != 0:
        sys.exit(code)


def base_opts():
    """Vivado batch 通用参数。"""
    return "-mode batch -nolog -nojournal"


def cmd_build(args):
    script = os.path.join(SCRIPTS, "create_project.tcl")
    opts = ["--top", args.top] if args.top else []
    full = f'{find_vivado()} {base_opts()} -source "{script}" -tclargs ' + " ".join(opts)
    run(full)


def cmd_program(args):
    script = os.path.join(SCRIPTS, "program_fpga.tcl")
    opts = ["--top", args.top] if args.top else []
    full = f'{find_vivado()} {base_opts()} -source "{script}" -tclargs ' + " ".join(opts)
    run(full)


def cmd_sim(args):
    script = os.path.join(SCRIPTS, "simulate.tcl")
    opts = ["--top", args.top] if args.top else []
    full = f'{find_vivado()} {base_opts()} -source "{script}" -tclargs ' + " ".join(opts)
    run(full)


def _ssh(ip, user, passwd, cmd):
    """在板上执行 shell 命令（sshpass + ssh）。"""
    argv = ["sshpass", "-p", passwd, "ssh",
            "-o", "StrictHostKeyChecking=no",
            "-o", "UserKnownHostsFile=/dev/null",
            f"{user}@{ip}", cmd]
    return subprocess.run(argv)


def _scp(ip, user, passwd, src, dst):
    """上传文件到板（sshpass + scp）。"""
    argv = ["sshpass", "-p", passwd, "scp",
            "-o", "StrictHostKeyChecking=no",
            "-o", "UserKnownHostsFile=/dev/null",
            src, f"{user}@{ip}:{dst}"]
    return subprocess.run(argv)


def find_bit(top):
    """跟 program_fpga.tcl 相同的路径约定，定位 <top>.bit。"""
    candidates = [os.path.join(BUILD, "bin", f"{top}.bit")] \
        + sorted(glob.glob(os.path.join(BUILD, f"{top}_prj", "*", "impl_1", f"{top}.bit")))
    for c in candidates:
        if os.path.isfile(c):
            return c
    raise SystemExit(f"[error] 未找到 {top}.bit，请先: python scripts/fpga.py build --top {top}")


def _bootgen_cfg():
    """返回 (bootgen 路径, 加载它的 ld-linux, LD_LIBRARY_PATH)。
    默认用本仓库 SDK 的 buildtools bootgen；可用环境变量 BOOTGEN/BOOTGEN_LD/BOOTGEN_LIBDIR 覆盖。"""
    sdk = "/home/alan/workspace/zynq/zynq7020-arm/sdk/petalinux/components/yocto"
    sysroot = os.path.join(sdk, "buildtools_extended", "sysroots", "x86_64-petalinux-linux")
    bg = os.environ.get("BOOTGEN", os.path.join(sysroot, "usr", "bin", "bootgen"))
    bg_ld = os.environ.get("BOOTGEN_LD", os.path.join(sysroot, "lib", "ld-linux-x86-64.so.2"))
    libdir = os.environ.get(
        "BOOTGEN_LIBDIR",
        os.path.join(sysroot, "usr", "lib") + os.pathsep + os.path.join(sysroot, "lib"))
    return bg, bg_ld, libdir


def _bit_to_bin(bit):
    """把 Vivado 原始 .bit 转成 Zynq 运行时可认的 byte-swapped .bin（bootgen 生成）。"""
    bg, bg_ld, libdir = _bootgen_cfg()
    if not os.path.isfile(bg):
        raise SystemExit(f"[error] bootgen 不存在: {bg}（可用 env BOOTGEN 指定）")
    work = tempfile.mkdtemp(prefix="fpga_bin_")
    bif = os.path.join(work, "x.bif")
    out = os.path.join(work, os.path.splitext(os.path.basename(bit))[0] + ".bin")
    with open(bif, "w") as f:
        f.write("the_ROM_image:\n{\n  %s\n}\n" % bit)
    env = dict(os.environ)
    env["LD_LIBRARY_PATH"] = libdir
    print(f"  -> 转换 .bit → byte-swapped .bin : {out}")
    rc = subprocess.run([bg_ld, bg, "-arch", "zynq", "-image", bif, "-o", "i", out, "-w"],
                        env=env)
    if rc.returncode != 0:
        raise SystemExit("[error] bootgen 转换失败")
    return out


def cmd_load(args):
    """运行时重配 PL：bit→bin → scp 上传 → fpga_manager firmware。不改 BOOT.BIN。"""
    ip = args.ip or "10.10.10.93"
    user = args.user or "root"
    passwd = args.passwd or "root"

    if not args.top:
        raise SystemExit("[error] load 需提供 --top <proj>（自动由 build 产物 .bit 转换并加载）")
    bit = find_bit(args.top)
    print(f"  bit   : {bit}")
    bin_file = _bit_to_bin(bit)
    print(f"  bin   : {bin_file}")

    fw = f"fpga_{int(time.time())}.bin"
    print(f"  上传  : {os.path.basename(bin_file)} -> {ip}:/lib/firmware/{fw}")
    if _scp(ip, user, passwd, bin_file, f"/tmp/{fw}").returncode != 0:
        raise SystemExit("[error] scp 上传失败")
    cmd = (f"mkdir -p /lib/firmware; cp /tmp/{fw} /lib/firmware/{fw}; "
           f"echo 加载前=$(cat /sys/class/fpga_manager/fpga0/state 2>/dev/null); "
           f"echo {fw} > /sys/class/fpga_manager/fpga0/firmware; "
           f"sleep 1; "
           f"echo 加载后=$(cat /sys/class/fpga_manager/fpga0/state 2>/dev/null)")
    p = _ssh(ip, user, passwd, cmd)
    if p.returncode != 0:
        raise SystemExit(f"[error] ssh 执行失败(rc={p.returncode})")
    print("==> PL 已运行时重配（BOOT.BIN 未动）。若该 bit 不含以太网，PL 内网络会中断；"
          "重启即回 BOOT.BIN 内嵌 bit。")


def cmd_clean(args):
    if os.path.isdir(BUILD):
        shutil.rmtree(BUILD, ignore_errors=True)
        print(f"Cleaned {BUILD}")
    else:
        print("No build/ directory; nothing to clean.")


def main():
    p = argparse.ArgumentParser(prog="fpga.py",
                                description="Zynq7020-FPGA cross-platform entry")
    sub = p.add_subparsers(dest="cmd", required=True)

    pb = sub.add_parser("build", help="compile: create project + synth + impl + bit + XSA")
    pb.add_argument("--top", help="project folder name under projects/")
    pb.set_defaults(func=cmd_build)

    pp = sub.add_parser("program", help="program board: flash the bit to the FPGA")
    pp.add_argument("--top", help="project folder name under projects/")
    pp.set_defaults(func=cmd_program)

    ps = sub.add_parser("sim", help="command-line simulation")
    ps.add_argument("--top", help="project folder name under projects/")
    ps.set_defaults(func=cmd_sim)

    pc = sub.add_parser("clean", help="clean build/ artifacts")
    pc.set_defaults(func=cmd_clean)

    pl = sub.add_parser("load", help="runtime-reload PL: bit->bin, upload, fpga_manager (不重打包 BOOT.BIN)")
    pl.add_argument("--top", help="project folder name under projects/")
    pl.add_argument("--ip", help="board IP (default 10.10.10.93)")
    pl.add_argument("--user", help="ssh user (default root)")
    pl.add_argument("--passwd", help="ssh password (default root)")
    pl.set_defaults(func=cmd_load)

    args = p.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()