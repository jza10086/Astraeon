"""Explicit world experiment runner. Default invocation prints a plan, never runs Godot.
Uses no external Python packages. All engine execution requires --run.
"""
from __future__ import annotations
import argparse
import csv
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time
import platform
import statistics

ROOT = Path(__file__).resolve().parents[1]
CANDIDATES = [
    (0, 1, 0, 1), (1, 1, 0, 1), (2, 1, 0, 1),
    (1, 0, 0, 1), (1, 2, 0, 1), (1, 1, 1, 1),
    (1, 1, 2, 1), (1, 1, 4, 1),
]


def plan(stage: str, repeats: int, candidates: list) -> list[dict]:
    jobs = []
    if stage in ('all', 'correctness'):
        jobs.append(dict(kind='data', mode='correctness', label='correctness'))
    for repeat in range(repeats):
        if stage in ('all', 'data'):
            for generator in range(3):
                for backend in range(3):
                    jobs.append(dict(kind='data', mode='generation', generator=generator,
                                     backend=backend, label=f'g{generator}b{backend}-r{repeat}'))
            for backend in range(3):
                for codec in range(5):
                    jobs.append(dict(kind='data', mode='storage', generator=1, backend=backend,
                                     codec=codec, label=f'b{backend}s{codec}-r{repeat}'))
        if stage in ('all', 'files'):
            for codec in (0, 1, 2):
                for files in range(2):
                    jobs.append(dict(kind='data', mode='storage', generator=1, backend=1,
                                     codec=codec, files=files, label=f'f{files}s{codec}-r{repeat}'))
        if stage in ('all', 'graphics'):
            # Rotate candidates to reduce fixed ordering bias. Same world reused only for restart.
            order = candidates[repeat % len(candidates):] + candidates[:repeat % len(candidates)]
            for generator, backend, codec, files in order:
                world = f'g{generator}b{backend}s{codec}f{files}-r{repeat}'
                for visit in ('fresh', 'restart'):
                    jobs.append(dict(kind='graphics', generator=generator, backend=backend,
                                     codec=codec, files=files, world=world,
                                     label=f'{world}-{visit}', visit=visit))
    return jobs


def engine_path(explicit: str | None) -> str:
    if explicit:
        return str(Path(explicit).resolve(strict=True))
    resolver = ROOT / '.agents/skills/godot-project-tooling/scripts/resolve_godot.ps1'
    result = subprocess.run(['powershell', '-NoProfile', '-File', str(resolver),
                             '-ProjectPath', str(ROOT)], capture_output=True, text=True, check=True)
    path = Path(json.loads(result.stdout)['path'])
    # Console exe can be a launcher; own the actual process for timeout and exit status.
    if path.stem.endswith('_console'):
        main = path.with_name(path.name.replace('_console.exe', '.exe'))
        if main.exists():
            path = main
    return str(path)


def percentile(values: list[float], fraction: float) -> float:
    values = sorted(values)
    return values[int((len(values) - 1) * fraction)] if values else 0.0


def summarize(output: Path) -> None:
    rows = []
    for path in sorted(output.glob('*/frames.csv')):
        with path.open(encoding='utf-8-sig', newline='') as file:
            frames = list(csv.DictReader(file))
        if frames:
            # Downsample by maxima so isolated long frames remain visible in the curve.
            bucket = max(1, len(frames) // 1200)
            points = [(float(frames[i]['elapsed_us']) / 1e6,
                       max(float(r['frame_us']) / 1000 for r in frames[i:i + bucket]))
                      for i in range(0, len(frames), bucket)]
            end = max(points[-1][0], .001)
            ceiling = max(50.0, max(y for _, y in points))
            polyline = ' '.join(f'{50 + x / end * 1100:.2f},{350 - min(y, ceiling) / ceiling * 300:.2f}' for x, y in points)
            svg = (f'<svg xmlns="http://www.w3.org/2000/svg" width="1200" height="400">'
                   f'<rect width="1200" height="400" fill="white"/>'
                   f'<text x="50" y="25">Frame time (bucket maxima); top={ceiling:.1f} ms; duration={end:.1f} s</text>'
                   f'<path d="M50 50V350H1150" stroke="black" fill="none"/>'
                   f'<polyline points="{polyline}" fill="none" stroke="#2864a0" stroke-width="1"/>'
                   f'<text x="50" y="380">Raw samples: frames.csv. Missing-terrain and phase readiness must be checked separately.</text></svg>')
            (path.parent / 'frame_time.svg').write_text(svg, encoding='utf-8')
        for phase in sorted({r['phase'] for r in frames}):
            subset = [r for r in frames if r['phase'] == phase]
            times = [float(r['frame_us']) / 1000 for r in subset]
            row = dict(run=path.parent.name, phase=phase, frames=len(times),
                       fps=1000 / statistics.mean(times) if times else 0,
                       p50_ms=percentile(times, .5), p95_ms=percentile(times, .95),
                       p99_ms=percentile(times, .99),
                       over_16_7=sum(v > 16.7 for v in times),
                       over_33_3=sum(v > 33.3 for v in times), over_50=sum(v > 50 for v in times),
                       missing_mesh_peak=max(float(r['missing_mesh']) for r in subset),
                       dirty_peak=max(float(r['dirty']) for r in subset))
            rows.append(row)
    if rows:
        with (output / 'summary.csv').open('w', encoding='utf-8', newline='') as file:
            writer = csv.DictWriter(file, fieldnames=list(rows[0]))
            writer.writeheader()
            writer.writerows(rows)
    task_groups: dict[tuple, list[float]] = {}
    for path in output.glob('*/tasks.jsonl'):
        for line in path.read_text(encoding='utf-8-sig').splitlines():
            record = json.loads(line)
            for key, value in record.items():
                if key.endswith('_us') and key not in ('queued_us', 'recorded_us', 'worker_started_us', 'worker_finished_us') and isinstance(value, (int, float)):
                    task_groups.setdefault((path.parent.name, record.get('phase'), record.get('kind'), key), []).append(value)
    metrics = [dict(run=k[0], phase=k[1], kind=k[2], metric=k[3], count=len(v),
                    mean=statistics.mean(v), p50=percentile(v, .5), p95=percentile(v, .95), p99=percentile(v, .99))
               for k, v in task_groups.items()]
    (output / 'task_summary.json').write_text(json.dumps(metrics, indent=2), encoding='utf-8')
    data_groups: dict[tuple, list[float]] = {}
    for path in output.glob('*/data.json'):
        document = json.loads(path.read_text(encoding='utf-8-sig'))
        for row in document.get('rows', []):
            if row.get('warmup', False):
                continue
            for key, value in row.items():
                if (key.endswith('_us') or key.endswith('_bytes')) and isinstance(value, (int, float)):
                    data_groups.setdefault((path.parent.name, row.get('kind'), key), []).append(value)
    data_metrics = [dict(run=k[0], kind=k[1], metric=k[2], count=len(v), mean=statistics.mean(v),
                         p50=percentile(v, .5), p95=percentile(v, .95), p99=percentile(v, .99))
                    for k, v in data_groups.items()]
    (output / 'data_summary.json').write_text(json.dumps(data_metrics, indent=2), encoding='utf-8')
    (output / 'report.md').write_text(
        '# World experiment results\n\nNo automatic winner is selected.\n\n'
        'Read manifest status and phase readiness before comparing FPS. Missing geometry, failed '
        'edits, timeouts, save backlog and discarded jobs remain in raw evidence.\n\n'
        'See summary.csv, task_summary.json, execution.json and each run manifest. '
        'Restart means a new process; OS disk cache is not controlled. '
        'Graphics use one opaque-water exposed-face renderer and real static collisions. '
        'GPU timing is unavailable; process memory samples are in process_memory.csv.\n', encoding='utf-8')


def memory_sample(pid: int) -> dict:
    if os.name != 'nt':
        return {}
    import ctypes
    from ctypes import wintypes
    class Counters(ctypes.Structure):
        _fields_ = [('cb', wintypes.DWORD), ('faults', wintypes.DWORD)] + [
            (name, ctypes.c_size_t) for name in ('peak_working', 'working', 'peak_paged', 'paged',
                                              'peak_nonpaged', 'nonpaged', 'pagefile', 'peak_pagefile', 'private')]
    kernel = ctypes.WinDLL('kernel32', use_last_error=True)
    psapi = ctypes.WinDLL('psapi', use_last_error=True)
    kernel.OpenProcess.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD]
    kernel.OpenProcess.restype = wintypes.HANDLE
    kernel.CloseHandle.argtypes = [wintypes.HANDLE]
    psapi.GetProcessMemoryInfo.argtypes = [wintypes.HANDLE, ctypes.POINTER(Counters), wintypes.DWORD]
    handle = kernel.OpenProcess(0x1000 | 0x10, False, pid)
    if not handle:
        return {}
    try:
        counters = Counters()
        counters.cb = ctypes.sizeof(counters)
        if psapi.GetProcessMemoryInfo(handle, ctypes.byref(counters), counters.cb):
            return dict(working=counters.working, private=counters.private, peak_working=counters.peak_working)
        return {}
    finally:
        kernel.CloseHandle(handle)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--run', action='store_true')
    parser.add_argument('--engine')
    parser.add_argument('--stage', choices=['all', 'correctness', 'data', 'files', 'graphics'], default='all')
    parser.add_argument('--repeats', type=int, default=2)
    parser.add_argument('--seconds', type=int, default=30)
    parser.add_argument('--layout', type=int, choices=[0, 1], default=1)
    parser.add_argument('--horizontal', type=int, default=64)
    parser.add_argument('--vertical', type=int, default=32)
    parser.add_argument('--workers', type=int, choices=range(1, 9), default=2)
    parser.add_argument('--budget-minutes', type=int, default=150)
    parser.add_argument('--candidates', type=Path, help='JSON list of [G,B,S,F] tuples, all zero-based')
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    candidates = json.loads(args.candidates.read_text()) if args.candidates else CANDIDATES
    if args.seconds < 2 or args.horizontal < 16 or args.vertical < 16 or args.horizontal % 16 or args.vertical % 16:
        parser.error('Duration must be >= 2; distances must be positive multiples of 16')
    if not 1 <= args.repeats <= 10 or not candidates:
        parser.error('Invalid repeats/candidate list')
    for item in candidates:
        if len(item) != 4 or any(not isinstance(v, int) for v in item) or not (0 <= item[0] < 3 and 0 <= item[1] < 3 and 0 <= item[2] < 5 and 0 <= item[3] < 2):
            parser.error('Invalid G/B/S/F candidate')
    jobs = plan(args.stage, args.repeats, candidates)
    if not args.run:
        print(json.dumps({'armed': False, 'jobs': jobs, 'note': 'No engine, import, or tests launched. Pass --run only when authorized.'}, indent=2))
        return 0
    output = (args.output or ROOT / 'tmp/world_lab' / time.strftime('%Y%m%d-%H%M%S')).resolve()
    if not output.is_relative_to(ROOT / 'tmp'):
        parser.error('Experiment output must remain inside this project tmp directory')
    output.mkdir(parents=True, exist_ok=False)
    (ROOT / 'tmp/.gdignore').touch(exist_ok=True)
    engine = engine_path(args.engine)
    version = subprocess.run([engine, '--version'], capture_output=True, text=True, check=True).stdout.strip()
    if not version.startswith('4.7.stable'):
        raise RuntimeError(f'Expected Godot 4.7 stable, got {version}')
    hashes = {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
              for folder in ('game/world', 'tests/world') for p in (ROOT / folder).rglob('*') if p.is_file()}
    hashes['tools/run_world_suite.py'] = hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
    (output / 'suite_manifest.json').write_text(json.dumps(dict(engine=engine, engine_version=version, platform=platform.platform(),
        hashes=hashes, jobs=jobs, args=vars(args)), default=str, indent=2), encoding='utf-8')
    deadline = time.monotonic() + min(180, max(1, args.budget_minutes)) * 60
    execution = []
    for job in jobs:
        remaining = deadline - time.monotonic()
        if remaining < 5:
            execution.append(dict(job=job, status='not_run_budget'))
            continue
        run = output / job['label']
        run.mkdir()
        command = [engine, '--path', str(ROOT)]
        if job['kind'] == 'data':
            command += ['--headless', '--script', 'res://tests/world/world_data_suite.gd']
        else:
            command += ['res://tests/world/world_benchmark.tscn']
        command += ['--', '--run', f'--output={run.as_posix()}', f'--run-id={job["label"]}', f'--seconds={args.seconds}']
        command += [f'--layout={args.layout}', f'--horizontal={args.horizontal}', f'--vertical={args.vertical}', f'--workers={args.workers}']
        command += [f'--{key}={job[key]}' for key in ('mode', 'generator', 'backend', 'codec', 'files') if key in job]
        if 'world' in job:
            command += [f'--world={(output / "worlds" / job["world"]).as_posix()}']
        started = time.monotonic()
        memory = []
        timeout = min(remaining, 600 if job['kind'] == 'data' else 600 + args.seconds * 5)
        with (run / 'engine.log').open('w', encoding='utf-8') as log:
            process = subprocess.Popen(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT)
            timed_out = False
            while process.poll() is None:
                if time.monotonic() - started >= timeout:
                    process.kill()
                    process.wait()
                    timed_out = True
                    break
                memory.append(dict(seconds=time.monotonic() - started, **memory_sample(process.pid)))
                time.sleep(.25)
        (run / 'process_memory.csv').write_text('seconds,working,private,peak_working\n' + '\n'.join(
            ','.join(str(row.get(k, '')) for k in ('seconds', 'working', 'private', 'peak_working')) for row in memory), encoding='utf-8')
        log_text = (run / 'engine.log').read_text(encoding='utf-8', errors='replace')
        bad_log = any(marker in log_text for marker in ('SCRIPT ERROR', 'ERROR:', 'Parse Error', 'Parser Error'))
        status = 'timeout' if timed_out else ('failed' if process.returncode != 0 or bad_log else 'completed')
        manifest = run / 'manifest.json'
        if not timed_out and not bad_log and manifest.exists():
            status = json.loads(manifest.read_text(encoding='utf-8-sig')).get('status', status)
        world_path = output / 'worlds' / job['world'] if 'world' in job else run / 'world'
        world_bytes = sum(p.stat().st_size for p in world_path.rglob('*') if p.is_file())
        execution.append(dict(job=job, status=status, exit_code=process.returncode, elapsed_s=time.monotonic() - started, world_bytes=world_bytes))
        (output / 'execution.json').write_text(json.dumps(execution, indent=2), encoding='utf-8')
        if job.get('mode') == 'correctness' and status != 'completed':
            for pending in jobs[len(execution):]:
                execution.append(dict(job=pending, status='not_run_correctness_failed'))
            break
    (output / 'execution.json').write_text(json.dumps(execution, indent=2), encoding='utf-8')
    sizes = {str(p.relative_to(output)): p.stat().st_size for p in output.rglob('*') if p.is_file()}
    (output / 'file_sizes.json').write_text(json.dumps(sizes, indent=2), encoding='utf-8')
    summarize(output)
    return 0 if all(j['status'] == 'completed' for j in execution) else 2


if __name__ == '__main__':
    raise SystemExit(main())



