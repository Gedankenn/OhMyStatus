#!/usr/bin/env python3
"""One-shot JSON snapshot of this machine, plus tmpfs history."""
from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path

STATS = Path(__file__).with_name("host-stats.py")
TIMEOUT = 8
HIST_MAX = 8640
HIST_DRAW = 120


def empty_hist() -> dict:
    return {"cpu": [], "mem": [], "gpu": [], "vram": [], "disk": [], "pwr": []}


def fail(err: str) -> dict:
    return {
        "ok": False,
        "reachable": False,
        "host": "",
        "cpu": {"percent": 0, "temp": None, "name": "", "cores": 0},
        "mem": {"percent": 0, "used_gb": 0, "total_gb": 0},
        "disk": {"percent": 0, "used_gb": 0, "total_gb": 0, "path": "/"},
        "docker": {"available": False, "items": []},
        "gpu": {
            "percent": 0,
            "temp": None,
            "name": "",
            "vram_percent": 0,
            "vram_used_mb": 0,
            "vram_total_mb": 0,
            "power_w": None,
            "power_cap_w": None,
        },
        "power": {
            "watts": None,
            "cpu_w": None,
            "gpu_w": None,
            "disk_w": None,
            "disk_n": 0,
            "disk_spin": 0,
            "cap_w": None,
            "cpu_source": "",
        },
        "hist": empty_hist(),
        "error": err[:180],
    }


def hist_path(host: str) -> Path:
    runtime = os.environ.get("XDG_RUNTIME_DIR") or "/tmp"
    safe = "".join(c if c.isalnum() or c in ".-" else "_" for c in (host or "host"))
    return Path(runtime) / f"ohmystatus.{safe}.hist.json"


def load_hist(path: Path) -> dict:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {"boot_id": "", "s": []}
    if not isinstance(data, dict):
        return {"boot_id": "", "s": []}
    samples = data.get("s")
    if not isinstance(samples, list):
        samples = []
    return {"boot_id": str(data.get("boot_id") or ""), "s": samples}


def downsample(samples: list, n: int) -> dict:
    if not samples:
        return empty_hist()
    if len(samples) <= n:
        pick = samples
    else:
        pick = []
        size = len(samples) / n
        for i in range(n):
            lo = int(i * size)
            hi = max(lo + 1, int((i + 1) * size))
            chunk = samples[lo:hi]
            pick.append(
                {
                    "cpu": max(float(x.get("cpu") or 0) for x in chunk),
                    "mem": max(float(x.get("mem") or 0) for x in chunk),
                    "gpu": max(float(x.get("gpu") or 0) for x in chunk),
                    "vram": max(float(x.get("vram") or 0) for x in chunk),
                    "disk": max(float(x.get("disk") or 0) for x in chunk),
                    "pwr": max(float(x.get("pwr") or 0) for x in chunk),
                }
            )
    return {
        "cpu": [round(float(x.get("cpu") or 0), 1) for x in pick],
        "mem": [round(float(x.get("mem") or 0), 1) for x in pick],
        "gpu": [round(float(x.get("gpu") or 0), 1) for x in pick],
        "vram": [round(float(x.get("vram") or 0), 1) for x in pick],
        "disk": [round(float(x.get("disk") or 0), 1) for x in pick],
        "pwr": [round(float(x.get("pwr") or 0), 1) for x in pick],
    }


def record(data: dict) -> dict:
    if not data.get("reachable"):
        data["hist"] = empty_hist()
        return data
    host = str(data.get("host") or "host")
    path = hist_path(host)
    hist = load_hist(path)
    boot = str(data.get("boot_id") or "")
    if boot and hist["boot_id"] and hist["boot_id"] != boot:
        hist = {"boot_id": boot, "s": []}
    elif boot:
        hist["boot_id"] = boot
    hist["s"].append(
        {
            "cpu": float((data.get("cpu") or {}).get("percent") or 0),
            "mem": float((data.get("mem") or {}).get("percent") or 0),
            "gpu": float((data.get("gpu") or {}).get("percent") or 0),
            "vram": float((data.get("gpu") or {}).get("vram_percent") or 0),
            "disk": float((data.get("disk") or {}).get("percent") or 0),
            "pwr": float((data.get("power") or {}).get("watts") or 0),
        }
    )
    if len(hist["s"]) > HIST_MAX:
        hist["s"] = hist["s"][-HIST_MAX:]
    try:
        path.write_text(json.dumps(hist, separators=(",", ":")), encoding="utf-8")
    except OSError:
        pass
    data["hist"] = downsample(hist["s"], HIST_DRAW)
    return data


def snapshot() -> dict:
    try:
        proc = subprocess.run(
            [sys.executable, str(STATS)],
            capture_output=True,
            text=True,
            timeout=TIMEOUT,
        )
    except subprocess.TimeoutExpired:
        return fail("timeout")
    except OSError as exc:
        return fail(str(exc))
    if proc.returncode != 0:
        err = (proc.stderr or proc.stdout or f"stats {proc.returncode}").strip()
        return fail(err)
    raw = (proc.stdout or "").strip()
    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        return fail(raw[:180] or "bad json")
    if not isinstance(data, dict):
        return fail("bad json")
    data["reachable"] = True
    data["ok"] = True
    return data


def main() -> None:
    json.dump(record(snapshot()), sys.stdout, ensure_ascii=False)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
