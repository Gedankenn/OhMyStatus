#!/usr/bin/env python3
"""One-shot JSON snapshot of this machine, plus tmpfs history."""
from __future__ import annotations

import importlib.util
import json
import os
import subprocess
import sys
import time
from pathlib import Path

STATS = Path(__file__).with_name("host-stats.py")
TIMEOUT = 8
HIST_HOURS = 1.0
HIST_MAX = 8640  # safety cap only; age window is the real limit
HIST_DRAW = 120
GPU_MAX = 6


def empty_hist() -> dict:
    return {"cpu": [], "mem": [], "disk": [], "pwr": [], "gpu": [], "vram": []}


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


def write_json_atomic(path: Path, data) -> None:
    """Write via tmp + rename so a reader never sees a partial file."""
    tmp = path.with_name(f".{path.name}.{os.getpid()}.tmp")
    try:
        with open(tmp, "w", encoding="utf-8") as fh:
            json.dump(data, fh, separators=(",", ":"))
        os.replace(tmp, path)
    except OSError:
        try:
            tmp.unlink()
        except OSError:
            pass


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


def gpu_pairs(sample: dict) -> list[tuple[float, float]]:
    """Per-GPU (usage, vram_pct) pairs for one sample."""
    raw = sample.get("g")
    if not isinstance(raw, list):
        # Legacy single-GPU sample.
        try:
            return [(float(sample.get("gpu") or 0), float(sample.get("vram") or 0))]
        except (TypeError, ValueError):
            return []
    pairs: list[tuple[float, float]] = []
    for item in raw[:GPU_MAX]:
        try:
            if isinstance(item, (list, tuple)):
                pairs.append((float(item[0] or 0), float(item[1] or 0)))
            else:
                pairs.append((float(item or 0), 0.0))
        except (TypeError, ValueError):
            pairs.append((0.0, 0.0))
    return pairs


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
            pairs = [gpu_pairs(x) for x in chunk]
            width = max((len(p) for p in pairs), default=0)
            gpu_peak = []
            for gi in range(width):
                col = [p[gi] for p in pairs if gi < len(p)]
                gpu_peak.append(
                    [max(c[0] for c in col), max(c[1] for c in col)] if col else [0.0, 0.0]
                )
            pick.append(
                {
                    "cpu": max(float(x.get("cpu") or 0) for x in chunk),
                    "mem": max(float(x.get("mem") or 0) for x in chunk),
                    "disk": max(float(x.get("disk") or 0) for x in chunk),
                    "pwr": max(float(x.get("pwr") or 0) for x in chunk),
                    "g": gpu_peak,
                }
            )
    ngpu = max((len(gpu_pairs(x)) for x in pick), default=0)
    gpu_series: list[list[float]] = []
    vram_series: list[list[float]] = []
    for gi in range(ngpu):
        util: list[float] = []
        vram: list[float] = []
        for sample in pick:
            pairs = gpu_pairs(sample)
            if gi < len(pairs):
                util.append(round(pairs[gi][0], 1))
                vram.append(round(pairs[gi][1], 1))
        gpu_series.append(util)
        vram_series.append(vram)
    return {
        "cpu": [round(float(x.get("cpu") or 0), 1) for x in pick],
        "mem": [round(float(x.get("mem") or 0), 1) for x in pick],
        "disk": [round(float(x.get("disk") or 0), 1) for x in pick],
        "pwr": [round(float(x.get("pwr") or 0), 1) for x in pick],
        "gpu": gpu_series,
        "vram": vram_series,
    }


def prune(samples: list, now: float) -> list:
    """Keep only samples inside the retention window (newest last)."""
    cutoff = now - HIST_HOURS * 3600.0
    kept = []
    for s in samples:
        try:
            ts = float(s.get("t") or 0)
        except (TypeError, ValueError):
            continue
        # Legacy samples (no timestamp) and future/clock-skewed ones are dropped.
        if cutoff <= ts <= now + 300.0:
            kept.append(s)
    if len(kept) > HIST_MAX:
        kept = kept[-HIST_MAX:]
    return kept


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
    now = time.time()
    cards = data.get("gpus")
    if not isinstance(cards, list) or not cards:
        cards = [data.get("gpu") or {}]
    pairs = []
    for card in cards[:GPU_MAX]:
        try:
            pairs.append(
                [
                    float((card or {}).get("percent") or 0),
                    float((card or {}).get("vram_percent") or 0),
                ]
            )
        except (TypeError, ValueError):
            pairs.append([0.0, 0.0])
    hist["s"].append(
        {
            "t": round(now, 3),
            "cpu": float((data.get("cpu") or {}).get("percent") or 0),
            "mem": float((data.get("mem") or {}).get("percent") or 0),
            "disk": float((data.get("disk") or {}).get("percent") or 0),
            "pwr": float((data.get("power") or {}).get("watts") or 0),
            "g": pairs,
        }
    )
    hist["s"] = prune(hist["s"], now)
    write_json_atomic(path, hist)
    data["hist"] = downsample(hist["s"], HIST_DRAW)
    return data


_STATS_MODULE = None


def stats_module():
    """Import host-stats.py in-process: no interpreter startup per poll."""
    global _STATS_MODULE
    if _STATS_MODULE is False:
        return None
    if _STATS_MODULE is not None:
        return _STATS_MODULE
    try:
        spec = importlib.util.spec_from_file_location("ohmystatus_host_stats", STATS)
        if spec is None or spec.loader is None:
            _STATS_MODULE = False
            return None
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        _STATS_MODULE = module
        return module
    except Exception:  # noqa: BLE001 - fall back to the subprocess path
        _STATS_MODULE = False
        return None


def snapshot() -> dict:
    module = stats_module()
    if module is not None:
        try:
            data = module.snapshot()
        except Exception:  # noqa: BLE001 - fall back to the subprocess path
            data = None
        if isinstance(data, dict):
            data["reachable"] = True
            data["ok"] = True
            return data
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
