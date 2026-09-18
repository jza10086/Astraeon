"""Run current native contracts plus a short graphical streaming matrix."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True, help="Godot 4.7 console executable")
    parser.add_argument("--seconds", type=float, default=1.5, help="Seconds per movement phase")
    args = parser.parse_args()
    version = subprocess.check_output([args.godot, "--version"], text=True).strip()
    if not version.startswith("4.7.stable."):
        raise RuntimeError("Expected Godot 4.7 stable, got " + version)
    out = ROOT / "tmp/native-probe" / str(int(time.time()))
    out.mkdir(parents=True)
    base = [args.godot, "--path", str(ROOT)]
    def run(name, command):
        with (out / (name + ".log")).open("w", encoding="utf8") as log:
            result = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, timeout=180)
        text = (out / (name + ".log")).read_text(encoding="utf8")
        if result.returncode or "SCRIPT ERROR" in text or "ERROR:" in text:
            raise RuntimeError(name + " failed: " + text[-5000:])
        print(name + " passed", flush=True)
        return text
    contract_log = run("contracts", base + ["--headless", "--script", "res://tests/native_world/test_native_world.gd"])
    contract = next(json.loads(line) for line in contract_log.splitlines() if line.startswith('{"checks"'))
    rows = []
    for prediction in (0, 1):
        world = out / ("world_" + str(prediction))
        for phase in ("fresh", "reload"):
            name = "p" + str(prediction) + "_" + phase
            report = out / (name + ".json")
            log = run(name, base + ["--script", "res://tests/native_world/runtime_probe.gd", "--", "--prediction=" + str(prediction), "--seconds=" + str(args.seconds), "--world=" + world.as_posix(), "--output=" + report.as_posix()])
            data = json.loads(report.read_text())
            if data["failures"]:
                raise RuntimeError(str(data["failures"]))
            samples = data.pop("samples")
            data["near_mesh_ready"] = sum(s["near_meshed"] for s in samples)
            data["near_collision_ready"] = sum(s["collision_present"] for s in samples)
            data["sample_count"] = len(samples)
            data["final_io"] = samples[-1]["io"]
            data["final_generation"] = samples[-1]["generation"]
            data["peak_tasks"] = {key: max(s["engine"]["tasks"][key] for s in samples) for key in samples[0]["engine"]["tasks"]}
            regions = list(world.glob("*.avr"))
            data["region_files"] = len(regions)
            data["logical_file_bytes"] = sum(p.stat().st_size for p in regions)
            data["graphics_device"] = next((line for line in log.splitlines() if "Using Device" in line), "unknown")
            rows.append(data)
    summary = {"engine": version, "contract": contract, "runs": rows, "binary": json.loads((ROOT / "tmp/native-build/editor_manifest.json").read_text()), "driver_sha256": hashlib.sha256((ROOT / "tests/native_world/runtime_probe.gd").read_bytes()).hexdigest()}
    (out / "summary.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf8")
    print("Summary: " + str(out / "summary.json"), flush=True)


if __name__ == "__main__":
    main()
