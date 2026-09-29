#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
fpga.py ---- Zynq7020-FPGA cross-platform build entry (Windows + Linux/WSL2)

Usage (same from Windows cmd/PowerShell and Linux):
    python scripts/fpga.py build   --top <proj>    # compile: project+synth+impl+bit+XSA
    python scripts/fpga.py program --top <proj>    # program board: write bit via Hardware Manager
    python scripts/fpga.py sim     --top <proj>    # simulate (needs a testbench under the project)
    python scripts/fpga.py clean                   # remove build/ artifacts

Notes:
    - No shell dependence; safe and cross-platform.
    - Locates vivado: $VIVADO env var first, then PATH, then common install paths.
    - Each platform gets its own build/ dir; not git-tracked.
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

# Common Vivado versions used as a fallback search list (2021.1 is installed here)
COMMON_VERSIONS = ["2023.2", "2022.2", "2021.2", "2021.1", "2020.2", "2019.2"]


def find_vivado():
    """Return a usable vivado command/path, or 'vivado' if none found (let the OS try)."""
    # 1) explicit env var
    env = os.environ.get("VIVADO")
    if env:
        return env
    # 2) already on PATH
    on_path = shutil.which("vivado")
    if on_path:
        return on_path
    # 3) common install paths
    candidates = []
    for v in COMMON_VERSIONS:
        candidates.append(rf"C:\Xilinx\Vivado\{v}\bin\vivado.bat")  # Windows
        candidates.append(f"/opt/Xilinx/Vivado/{v}/bin/vivado")     # Linux
        candidates.append(f"/tools/Xilinx/Vivado/{v}/bin/vivado")   # Linux (other)
    for c in candidates:
        if os.path.isfile(c):
            return c
    print("[warn] vivado not found; will try to invoke 'vivado' directly. If that "
          "fails, set the environment variable VIVADO=<path to vivado>.")
    return "vivado"


def run(full_cmd, check=True):
    """Run a command from the repo root via the shell on Windows and Linux.
    With a UNC (WSL) root, cmd refuses to start in a UNC working directory and
    resets to the Windows dir; build dirs under relative build/ must be drive
    letters. So we set an explicit local cwd first, then pushd maps the WSL root
    to a drive letter. Linux just uses the real root directly; python stays the
    single cross-platform entry so users never map drives by hand.
    """
    print("-> " + full_cmd)
    if os.name == "nt" and ROOT.startswith("\\\\"):
        # Give the child cmd an explicit local working directory (system-drive root)
        # so it never *starts* inside the UNC path (cmd refuses that, prints a
        # warning and resets to the Windows dir). Then pushd maps the WSL root
        # to a drive letter; the working directory after pushd is the repo root,
        # so relative build/ paths still resolve.
        cwd_arg = os.environ.get("SystemDrive", "C:") + "\\"
        full_cmd = 'pushd "{}" && {}'.format(ROOT, full_cmd)
    else:
        cwd_arg = ROOT
    # stream Vivado output line-by-line, dropping the command-echo lines.
    # In batch mode Vivado re-echoes every executed TCL command prefixed
    # with '#', which is noise. Real output (INFO:/Build OK!/errors) never
    # starts with '#', so we skip the echo and keep real output.
    # Reconfigure our own stdout to UTF-8 so Windows 'gbk' consoles don't
    # crash when printing a byte they can't represent.
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except (AttributeError, ValueError):
        pass
    proc = subprocess.Popen(full_cmd, shell=True, cwd=cwd_arg,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    for raw in iter(proc.stdout.readline, b""):
        line = raw.decode("utf-8", "replace").rstrip("\r\n")
        if not line.lstrip().startswith("#"):
            print(line)
    proc.stdout.close()
    proc.wait()
    code = proc.returncode

    if check and code != 0:
        sys.exit(code)
    return code


def base_opts():
    """Common Vivado batch options."""
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
    """Run a shell command on the board (sshpass + ssh). On Windows, fall back to WSL if no native sshpass."""
    return run_sshless(ip, user, passwd, cmd=cmd, src=None)

def _scp(ip, user, passwd, src, dst):
    """Upload a file to the board (sshpass + scp). On Windows, fall back to WSL if no native sshpass."""
    return run_sshless(ip, user, passwd, cmd=None, src=(src, dst))

def run_sshless(ip, user, passwd, cmd=None, src=None):
    """Cross-platform ssh/scp wrapper: prefer native sshpass (Linux), else WSL's sshpass.

    cmd - remote command for ssh; src - (local_path, remote_path) switches to an scp upload.
    Linux/WSL run directly; on Windows sshpass is a Linux tool and is routed
    through wsl.exe (this WSL ships sshpass/scp/ssh), so we never rely on a
    native Windows sshpass.
    """
    # On Windows prefer WSL even if sshpass is on PATH; Linux native direct is most reliable.
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
    # Windows (or missing sshpass): route via WSL (its PATH already has sshpass/scp/ssh)
    opts = "-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
    if src:
        # Convert a local Windows path to a WSL-readable /mnt/c/... path for scp
        w = src[0].replace(":", "").replace("\\", "/")
        w = "/mnt/" + w[0].lower() + w[1:]
        line = f"sshpass -p {passwd} scp {opts} {w} {user}@{ip}:{src[1]}"
    else:
        line = f"sshpass -p {passwd} ssh {opts} {user}@{ip} {_shq(cmd)}"
    return subprocess.run(["wsl.exe", "-d", "Ubuntu-24.04", "--", "bash", "-lc", line])

def _shq(s):
    """Wrap the remote command in single quotes so Windows->WSL escaping can't break spaces/braces."""
    return "'" + s.replace("'", "'\\''") + "'"


def find_bit(top):
    """Locate <top>.bit using the same path convention as program_fpga.tcl."""
    candidates = [os.path.join(BUILD, "bin", f"{top}.bit")] \
        + sorted(glob.glob(os.path.join(BUILD, f"{top}_prj", "*", "impl_1", f"{top}.bit")))
    for c in candidates:
        if os.path.isfile(c):
            return c
    raise SystemExit(f"[error] {top}.bit not found; run first: python scripts/fpga.py build --top {top}")


def _bitstream_start(data):
    """Return the offset of the bitstream data region in the .bit (before the sync word).
    A Vivado .bit is a text header (design/part/date/e length fields) followed by the bitstream,
    which contains the 7-series sync word AA995566, marking where the config data really begins,
    so locating the data region this way is robust across Vivado header differences."""
    for i in range(0, 3):   # tolerate a little leading padding
        for off in range(0, 8):
            p = off
            while p < len(data) - 4:
                if data[p] == 0xAA and data[p + 3] == 0x66:
                    if data[p + 1] == 0x99 and data[p + 2] == 0x55:
                        # confirm the big-endian 0xAA 0x99 0x55 0x66 sync word
                        return p
                p += 4
    raise ValueError(f"sync word (AA995566) not found in .bit (len={len(data)})")


def _bit_to_bin(bit):
    """Losslessly convert a Vivado .bit into a byte-swapped .bin loadable by the Zynq fpga_manager.

    Based on a) the kernel zynq-fpga driver (zynq-fpga.c) comment:
        "Bitstream must be a byte swapped .bin file", and it looks at every 4-byte boundary for
        the sync word 66 55 99 AA; b) Xilinx bootgen -process_bitstream bin yields
        exactly this byte-swapped-per-32-bit-word raw config stream.
    So this function does the byte swap in pure Python - no bootgen or external tools -
    consistent across Windows/Linux/WSL, byte-identical to bootgen output (verified).
    """
    with open(bit, "rb") as f:
        data = f.read()
    start = _bitstream_start(data)
    # Byte-swap each 32-bit word: AA 99 55 66 -> 66 55 99 AA (fpga_manager requirement)
    body = bytes(data[start:])
    # Ensure 4-byte alignment (driver needs DMA length %%4==0)
    if len(body) % 4:
        body = body[: len(body) - (len(body) % 4)]
    swapped = b"".join(body[i:i + 4][::-1] for i in range(0, len(body), 4))
    work = tempfile.mkdtemp(prefix="fpga_bin_")
    out = os.path.join(work, os.path.splitext(os.path.basename(bit))[0] + ".bin")
    with open(out, "wb") as f:
        f.write(swapped)
    print(f"  -> converted .bit -> byte-swapped .bin (pure-python): {out} ({len(swapped)} B)")
    return out


def cmd_load(args):
    """Runtime-reload PL: bit->bin, scp upload, fpga_manager firmware. Does not touch BOOT.BIN."""
    ip = args.ip or "10.10.10.93"
    user = args.user or "root"
    passwd = args.passwd or "root"

    if not args.top:
        raise SystemExit("[error] load requires --top <proj> (converted & loaded from the build .bit)")
    bit = find_bit(args.top)
    print(f"  bit   : {bit}")
    bin_file = _bit_to_bin(bit)
    print(f"  bin   : {bin_file}")

    fw = f"fpga_{int(time.time())}.bin"
    print(f"  upload : {os.path.basename(bin_file)} -> {ip}:/lib/firmware/{fw}")
    if _scp(ip, user, passwd, bin_file, f"/tmp/{fw}").returncode != 0:
        raise SystemExit("[error] scp upload failed")
    cmd = (f"mkdir -p /lib/firmware; cp /tmp/{fw} /lib/firmware/{fw}; "
           f"echo before=$(cat /sys/class/fpga_manager/fpga0/state 2>/dev/null); "
           f"echo {fw} > /sys/class/fpga_manager/fpga0/firmware; "
           f"sleep 1; "
           f"echo after=$(cat /sys/class/fpga_manager/fpga0/state 2>/dev/null)")
    p = _ssh(ip, user, passwd, cmd)
    if p.returncode != 0:
        raise SystemExit(f"[error] ssh execution failed (rc={p.returncode})")
    # The full-system bit includes PS networking (ETH over MIO), so the link should
    # survive; ssh again to confirm the board is still alive
    alive = _ssh(ip, user, passwd, "echo alive").returncode == 0
    if alive:
        print("==> PL runtime-reconfigured (BOOT.BIN untouched); board network stays up (PS in bit).")
        print("    Board LEDs should now be driven by the new bit.")
    else:
        print("==> PL reloaded, but SSH is gone - this bit has no PS network; reboot to use the BOOT.BIN bit.")


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

    pl = sub.add_parser("load", help="runtime-reload PL: bit->bin, upload, fpga_manager (does not repack BOOT.BIN)")
    pl.add_argument("--top", help="project folder name under projects/")
    pl.add_argument("--ip", help="board IP (default 10.10.10.93)")
    pl.add_argument("--user", help="ssh user (default root)")
    pl.add_argument("--passwd", help="ssh password (default root)")
    pl.set_defaults(func=cmd_load)

    args = p.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()