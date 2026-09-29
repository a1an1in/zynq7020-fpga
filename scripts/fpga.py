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


def run(full_cmd, check=True):
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
    if check and code != 0:
        sys.exit(code)
    return code


def base_opts():
    """Vivado batch 通用参数。"""
    return "-mode batch -nolog -nojournal"


def cmd_build(args):
    script = os.path.join(SCRIPTS, "create_project.tcl")
    opts = ["--top", args.top] if args.top else []
    full = f'{find_vivado()} {base_opts()} -source "{script}" -tclargs ' + " ".join(opts)
    # Build failure still surfaces via vivado's exit code, but we don't let it
    # short-circuit: we want to print a clean final verdict below.
    rc = run(full, check=False)

    # ---- decisive, noise-free verdict printed LAST by fpga.py itself ----
    proj       = args.top or "proj1_template"
    bit_file   = os.path.join(BUILD, f"{proj}_prj", f"{proj}.runs",
                              "impl_1", f"{proj}.bit")
    bit_ready  = os.path.isfile(bit_file)
    passed     = (rc == 0) and bit_ready

    sep = "=" * 60
    print(sep)
    if passed:
        print(f"  fpga.py: BUILD PASSED   (vivado exit={rc}, bitstream ready)")
        print(f"           {bit_file}")
    else:
        reason = "bitstream not found" if not bit_ready else "vivado reported an error"
        print(f"  fpga.py: BUILD FAILED   ({reason}; vivado exit={rc})")
    print(sep)
    sys.exit(0 if passed else 1)


def cmd_program(args):
    script = os.path.join(SCRIPTS, "program_fpga.tcl")
    opts = ["--top", args.top] if args.top else []
    full = f'{find_vivado()} {base_opts()} -source "{script}" -tclargs ' + " ".join(opts)
    run(full)


def cmd_sim(args):
    script = os.path.join(SCRIPTS, "simulate.tcl")
    opts = ["--top", args.top] if args.top else []
    full = f'{find_vivado()} {base_opts()} -source "{script}" -tclargs ' + " ".join(opts)
    # Don't let a non-zero vivado exit short-circuit: we want to print a clean
    # verdict below, after the (noisy) vivado transcript has fully finished.
    rc = run(full, check=False)

    # ---- decisive, noise-free verdict printed LAST by fpga.py itself ----
    proj       = args.top or "proj1_template"
    verdict_file = os.path.join(BUILD, f"{proj}_prj", f"{proj}.sim",
                                "sim_1", "behav", "xsim", "sim_verdict.txt")
    verdict = None
    if os.path.isfile(verdict_file):
        with open(verdict_file, "r") as fh:
            verdict = fh.read().strip()
    passed = (verdict == "PASS")

    sep = "=" * 60
    print(sep)
    if passed:
        print(f"  fpga.py: SIMULATION PASSED   (vivado exit={rc})")
    else:
        reason = "no verdict file written (did simulation even run?)" \
                 if verdict is None else f"testbench verdict = '{verdict}'"
        print(f"  fpga.py: SIMULATION FAILED   ({reason}; vivado exit={rc})")
    print(sep)
    sys.exit(0 if passed else 1)


def _ssh(ip, user, passwd, cmd):
    """在板上执行 shell 命令（sshpass + ssh）。Windows 若无原生 sshpass 则经 WSL 执行。"""
    return run_sshless(ip, user, passwd, cmd=cmd, src=None)

def _scp(ip, user, passwd, src, dst):
    """上传文件到板（sshpass + scp）。Windows 若无原生 sshpass 则经 WSL 执行。"""
    return run_sshless(ip, user, passwd, cmd=None, src=(src, dst))

def run_sshless(ip, user, passwd, cmd=None, src=None):
    """跨平台 ssh/scp 封装：优先原生 sshpass（Linux），缺失时回退到 WSL 自带 sshpass。

    cmd —— ssh 要执行的远端命令；src —— (本地路径, 远端路径) 时改为执行 scp 上传。
    Linux/WSL 直接跑；Windows 上 sshpass 属 Linux 工具，统一经 wsl.exe 转发
    （本机 WSL 已装 sshpass/scp/ssh），避免 Windows 无原生 sshpass 时找不到工具。
    """
    # Windows 上就算 PATH 里有直呼 sshpass 也建议走 WSL；Linux 原生直接跑最稳。
    if os.name != "nt" and shutil.which("sshpass"):
        if src:
            argv = ["sshpass", "-p", passwd, "scp",
                    "-o", "StrictHostKeyChecking=no",
                    "-o", "UserKnownHostsFile=/dev/null",
                    src[0], f"{user}@{ip}:{src[1]}"]
        else:
            argv = ["sshpass", "-p", passwd, "ssh",
                    "-o", "StrictHostKeyChecking=no",
                    "-o", "UserKnownHostsFile=/dev/null",
                    f"{user}@{ip}", cmd]
        return subprocess.run(argv)
    # Windows(或缺 sshpass)：走 WSL（其 PATH 内已有 sshpass/scp/ssh）
    opts = "-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
    if src:
        # 把本地 Windows 路径转成 WSL 可读的 /mnt/c/... 路径交给 scp
        w = src[0].replace(":", "").replace("\\", "/")
        w = "/mnt/" + w[0].lower() + w[1:]
        line = f"sshpass -p {passwd} scp {opts} {w} {user}@{ip}:{src[1]}"
    else:
        line = f"sshpass -p {passwd} ssh {opts} {user}@{ip} {_shq(cmd)}"
    return subprocess.run(["wsl.exe", "-d", "Ubuntu-24.04", "--", "bash", "-lc", line])

def _shq(s):
    """Shell 单引号包裹远端命令，避免 Windows→WSL 多层转义破坏空格/花括号。"""
    return "'" + s.replace("'", "'\\''") + "'"


def find_bit(top):
    """跟 program_fpga.tcl 相同的路径约定，定位 <top>.bit。"""
    candidates = [os.path.join(BUILD, "bin", f"{top}.bit")] \
        + sorted(glob.glob(os.path.join(BUILD, f"{top}_prj", "*", "impl_1", f"{top}.bit")))
    for c in candidates:
        if os.path.isfile(c):
            return c
    raise SystemExit(f"[error] 未找到 {top}.bit，请先: python scripts/fpga.py build --top {top}")


def _bitstream_start(data):
    """返回 .bit 中 bitstream 数据区（同步字之前）的偏移。
    Vivado .bit = 文本头(design/part/date/e 长度字段) 之后跟着的 bitstream，
    其中含 7-series 同步字 AA995566。同步字是配置数据真正开始的标志，
    据此定位数据区可免受各 Vivado 版本头部字段差异影响。"""
    for i in range(0, 3):   # 容忍开头少量 padding
        for off in range(0, 8):
            p = off
            while p < len(data) - 4:
                if data[p] == 0xAA and data[p + 3] == 0x66:
                    if data[p + 1] == 0x99 and data[p + 2] == 0x55:
                        # 确认 0xAA 0x99 0x55 0x66 大端同步字
                        return p
                p += 4
    raise ValueError(f"sync word (AA995566) not found in .bit (len={len(data)})")


def _bit_to_bin(bit):
    """把 Vivado .bit 无损转成 Zynq fpga_manager 可加载的 byte-swapped .bin。

    依据 a) 内核 zynq-fpga 驱动(zovn-fpga.c)注释明确：
        “Bitstream must be a byte swapped .bin file”，并在每个 4 字节边界找
        sync 字 66 55 99 AA；b) Xilinx 官方用 bootgen -process_bitstream bin
        转出的正是“每 32-bit 字做字节交换”的原始配置流。
    因此本函数用纯 Python 完成字节交换，无需任何外部 bootgen/系统工具，
    Windows/Linux/WSL 跨平台一致，产物与 bootgen 输出字节级一致(已实测比对)。
    """
    with open(bit, "rb") as f:
        data = f.read()
    start = _bitstream_start(data)
    # 交换每个 32-bit 字的字节序：AA 99 55 66 -> 66 55 99 AA（fpga_manager 要求）
    body = bytes(data[start:])
    # 确保 4 字节对齐（驱动要求 DMA 长度 %4==0）
    if len(body) % 4:
        body = body[: len(body) - (len(body) % 4)]
    swapped = b"".join(body[i:i + 4][::-1] for i in range(0, len(body), 4))
    work = tempfile.mkdtemp(prefix="fpga_bin_")
    out = os.path.join(work, os.path.splitext(os.path.basename(bit))[0] + ".bin")
    with open(out, "wb") as f:
        f.write(swapped)
    print(f"  -> 转换 .bit → byte-swapped .bin (pure-python) : {out} ({len(swapped)} B)")
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
    # 整系统 bit 内含 PS 网络（以太走 MIO），加载后网络应保持；再 ssh 一次确认存活
    alive = _ssh(ip, user, passwd, "echo alive").returncode == 0
    if alive:
        print("==> PL 已运行时重配（BOOT.BIN 未动），板子网络保持（整系统 bit 含 PS）。")
        print("    板子 LED 应由新 bit 驱动。")
    else:
        print("==> PL 已重配，但加载后 SSH 失联——此 bit 不含 PS 网络，需重启回 BOOT.BIN 内嵌 bit。")


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