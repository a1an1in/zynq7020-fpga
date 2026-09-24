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
import os
import shutil
import subprocess
import sys

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

    args = p.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()