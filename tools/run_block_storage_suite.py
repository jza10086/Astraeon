"""Bounded, sequential block-storage comparison. Explicit --run; artifacts stay in tmp/.
Uses only Python stdlib. Windows process memory is sampled at Godot's stable markers.
"""
from __future__ import annotations
import argparse
import ctypes
from ctypes import wintypes
import hashlib
import json
import math
import os
from pathlib import Path
import platform
import queue
import statistics
import subprocess
import threading
import time
from datetime import datetime, timezone

ROOT = Path(__file__).resolve().parents[1]
BACKENDS = ["DIRECT32", "DIRECT16", "PALETTE"]
FIXTURES = ["uniform", "terrain", "building"]

class MemoryCounters(ctypes.Structure):
    _fields_ = [("cb", wintypes.DWORD), ("PageFaultCount", wintypes.DWORD)] + [
        (name, ctypes.c_size_t) for name in (
            "PeakWorkingSetSize", "WorkingSetSize", "QuotaPeakPagedPoolUsage",
            "QuotaPagedPoolUsage", "QuotaPeakNonPagedPoolUsage", "QuotaNonPagedPoolUsage",
            "PagefileUsage", "PeakPagefileUsage", "PrivateUsage")]

def memory(process: subprocess.Popen) -> dict:
    if os.name != "nt":
        return {"unavailable": "Windows process counters required"}
    info = MemoryCounters()
    info.cb = ctypes.sizeof(info)
    function = ctypes.windll.psapi.GetProcessMemoryInfo
    function.argtypes = [wintypes.HANDLE, ctypes.POINTER(MemoryCounters), wintypes.DWORD]
    function.restype = wintypes.BOOL
    if not function(wintypes.HANDLE(int(process._handle)), ctypes.byref(info), info.cb):
        return {"unavailable": f"GetProcessMemoryInfo: {ctypes.GetLastError()}"}
    return {"private_bytes": info.PrivateUsage, "working_set_bytes": info.WorkingSetSize}

def save(path: Path, value: object) -> None:
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2), encoding="utf-8")

def percentile(values: list, probability: float) -> float:
    return sorted(values)[max(0, math.ceil(len(values) * probability) - 1)]

def stats(values: list) -> dict:
    return {"n": len(values), "median": statistics.median(values),
            "p95": percentile(values, .95), "min": min(values), "max": max(values)}

def run_job(command: list[str], output: Path, deadline: float) -> tuple[dict, list]:
    started = time.monotonic()
    process = subprocess.Popen(command, cwd=ROOT, stdout=subprocess.PIPE,
                               stderr=subprocess.STDOUT, text=True, encoding="utf-8",
                               errors="replace", creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
    lines: queue.Queue = queue.Queue()
    def reader():
        for line in process.stdout:
            lines.put(line.rstrip())
        lines.put(None)
    thread = threading.Thread(target=reader, daemon=True)
    thread.start()
    log, markers, report = [], {}, None
    eof = False
    peak_private = 0
    try:
        while not eof:
            if time.monotonic() >= deadline:
                raise TimeoutError("Suite wall-time budget reached")
            sample = memory(process)
            peak_private = max(peak_private, sample.get("private_bytes", 0))
            try:
                line = lines.get(timeout=.02)
            except queue.Empty:
                continue
            if line is None:
                eof = True
                continue
            log.append(line)
            if line.startswith("BLOCK_MEMORY "):
                _, stage, engine_pid = line.split()
                if int(engine_pid) != process.pid:
                    raise RuntimeError("Memory target is a wrapper, not the Godot engine")
                markers[stage] = memory(process)
            if line.startswith("BLOCK_RESULT "):
                report = json.loads(line.removeprefix("BLOCK_RESULT "))
        process.wait(timeout=max(.1, deadline-time.monotonic()))
        if process.returncode or report is None or not report["valid"] or any(
                token in line for line in log for token in ("SCRIPT ERROR", "ERROR:", "Parser Error", "BENCHMARK CHECK FAILED")):
            raise RuntimeError(f"Invalid benchmark process: exit={process.returncode}")
        report["memory"] = markers
        report["sampled_peak_private_bytes"] = peak_private
        report["wall_seconds"] = time.monotonic() - started
        for field in ("private_bytes", "working_set_bytes"):
            if all(field in markers.get(stage, {}) for stage in ("baseline", "resident")):
                report[field + "_delta"] = markers["resident"][field] - markers["baseline"][field]
        save(output.with_suffix(".json"), report)
        return report, log
    finally:
        if process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=3)
        output.with_suffix(".log").write_text("\n".join(log), encoding="utf-8")

def summarize(jobs: list[dict]) -> list[dict]:
    result = []
    for fixture in FIXTURES:
        for backend in BACKENDS:
            matching = [j for j in jobs if j["fixture"] == fixture and j["backend"] == backend]
            if not matching:
                continue
            rows = [r for j in matching for r in j["rows"]]
            item = {"fixture": fixture, "backend": backend, "processes": len(matching)}
            for metric in ("scan_1048576_us", "neighbors_1572864_us", "import_128_us", "export_128_us"):
                item[metric] = stats([r[metric] for r in rows])
            for metric in ("edit_batch_128_us", "new_state_us"):
                samples = [v for r in rows for v in r[metric]]
                item[metric] = stats(samples)
                item[metric]["p99"] = percentile(samples, .99)
            for metric in ("load_1024_us", "payload_bytes", "private_bytes_delta", "working_set_bytes_delta"):
                samples = [j[metric] for j in matching if metric in j]
                if samples:
                    item[metric] = stats(samples)
            result.append(item)
    return result

def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--run", action="store_true")
    parser.add_argument("--engine", type=Path, required=True)
    parser.add_argument("--repeats", type=int, default=3)
    parser.add_argument("--budget-seconds", type=int, default=300)
    parser.add_argument("--deadline-utc", help="Absolute task deadline, including preparation time")
    parser.add_argument("--label", default="selection")
    args = parser.parse_args()
    if not args.run:
        parser.error("Pass --run to execute")
    if not 1 <= args.repeats <= 10 or not 1 <= args.budget_seconds <= 10800:
        parser.error("repeats must be 1..10; budget must be 1..10800 seconds")
    started = time.monotonic()
    deadline = started + args.budget_seconds
    if args.deadline_utc:
        remaining = (datetime.fromisoformat(args.deadline_utc).astimezone(timezone.utc) - datetime.now(timezone.utc)).total_seconds()
        deadline = min(deadline, started + remaining)
    if deadline <= started:
        parser.error("Deadline already passed")
    configured_engine = args.engine
    # Windows console executable is a launcher; sample the actual headless engine process.
    if args.engine.name.endswith("_console.exe"):
        actual_engine = args.engine.with_name(args.engine.name.replace("_console.exe", ".exe"))
        if not actual_engine.is_file():
            raise RuntimeError("Cannot locate actual engine sibling for process memory measurement")
        args.engine = actual_engine
    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    folder = ROOT / "tmp" / f"block-storage-{stamp}-{args.label}"
    folder.mkdir(parents=True, exist_ok=False)
    version = subprocess.check_output([str(args.engine), "--version"], text=True, timeout=10).strip()
    if not version.startswith("4.7.stable."):
        raise RuntimeError("Unexpected Godot version: " + version)
    files = sorted((ROOT / "game/world/blocks").rglob("*.gd")) + [ROOT / "tests/blocks/benchmark_block_selection.gd", Path(__file__)]
    metadata = {"started_utc": datetime.now(timezone.utc).isoformat(), "engine": str(args.engine),
                "configured_engine": str(configured_engine), "version": version, "platform": platform.platform(), "processor": platform.processor(),
                "logical_cpus": os.cpu_count(), "repeats": args.repeats, "budget_seconds": args.budget_seconds,
                "deadline_utc": args.deadline_utc, "scope": "Headless GDScript, not rendering FPS",
                "git_head": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
                "source_sha256": {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in files}}
    save(folder / "metadata.json", metadata)
    print(f"OUTPUT {folder}", flush=True)
    jobs, error = [], None
    try:
        regression = subprocess.run([str(args.engine), "--headless", "--path", str(ROOT), "--script",
                                     "res://tests/blocks/test_block_data.gd"], cwd=ROOT, text=True,
                                    encoding="utf-8", errors="replace", stdout=subprocess.PIPE,
                                    stderr=subprocess.STDOUT, timeout=max(.1, deadline-time.monotonic()))
        (folder / "regression.log").write_text(regression.stdout, encoding="utf-8")
        if regression.returncode or "BLOCK_DATA PASS" not in regression.stdout or any(
                token in regression.stdout for token in ("SCRIPT ERROR", "ERROR:", "Parser Error")):
            raise RuntimeError("Correctness regression failed")
        print("REGRESSION PASS", flush=True)
        for repeat in range(args.repeats):
            for fixture_index, fixture in enumerate(FIXTURES):
                for offset in range(3):
                    backend = (offset + repeat + fixture_index) % 3
                    name = f"r{repeat + 1}-{fixture}-{BACKENDS[backend]}"
                    print(f"START {name}", flush=True)
                    command = [str(args.engine), "--headless", "--path", str(ROOT), "--script",
                               "res://tests/blocks/benchmark_block_selection.gd", "--",
                               f"--backend={backend}", f"--fixture={fixture}", f"--seed={73517 + repeat * 1009}"]
                    job, _ = run_job(command, folder / name, min(deadline, time.monotonic() + 90))
                    jobs.append(job)
                    save(folder / "partial_summary.json", summarize(jobs))
                    print(f"DONE {name}: {job['wall_seconds']:.2f}s, private_delta={job.get('private_bytes_delta', 'unavailable')}", flush=True)
        for fixture in FIXTURES:
            for repeat in range(args.repeats):
                checksums = [j["checksum"] for j in jobs if j["fixture"] == fixture and j["seed"] == 73517 + repeat * 1009]
                if len(checksums) != 3 or len(set(checksums)) != 1:
                    raise RuntimeError(f"Cross-backend checksum mismatch: {fixture}/{repeat}")
    except Exception as exc:
        error = str(exc)
    result = {"complete": error is None, "error": error, "wall_seconds": time.monotonic() - started,
              "job_count": len(jobs), "summary": summarize(jobs)}
    save(folder / "summary.json", result)
    print(json.dumps({"output": str(folder), "complete": result["complete"], "error": error,
                      "jobs": len(jobs), "wall_seconds": result["wall_seconds"]}), flush=True)
    return 1 if error else 0

if __name__ == "__main__":
    raise SystemExit(main())
