"""Sequential local benchmark suite; hard 30-minute wall budget includes import and smoke.
No third-party Python dependencies. Requires explicit --run. Raw data stays in tmp/.
"""
import argparse
import csv
import hashlib
import json
import math
import re
import statistics
import subprocess
import time
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / 'benchmarks/voxelgame/project'

def save(path, data):
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding='utf-8')

def percentile(values, p):
    return sorted(values)[max(0, math.ceil(len(values) * p) - 1)] if values else 0

def metrics(rows):
    ms = [r[1] for r in rows]
    return dict(frames=len(ms), mean_fps=1000 / statistics.fmean(ms) if ms else 0,
                p95_ms=percentile(ms, .95), p99_ms=percentile(ms, .99), max_ms=max(ms, default=0),
                over_33=sum(v > 33.333 for v in ms), over_50=sum(v > 50 for v in ms))

def analyse(folder, job):
    meta = json.loads((folder / 'metadata.json').read_text(encoding='utf-8-sig'))
    summary = json.loads((folder / 'summary.json').read_text(encoding='utf-8-sig'))
    edits = json.loads((folder / 'edits.json').read_text(encoding='utf-8-sig'))
    counters = json.loads((folder / 'counters.json').read_text(encoding='utf-8-sig'))
    with (folder / 'frames.csv').open(encoding='utf-8-sig', newline='') as f:
        rows = [(float(r['elapsed_s']), float(r['frame_ms'])) for r in csv.DictReader(f)]
    result = metrics(rows)
    valid = bool(rows) and all(ms > 0 for _, ms in rows) and all(rows[i][0] > rows[i-1][0] for i in range(1, len(rows)))
    valid &= meta['render_size'] == '(1920, 1080)' and meta['height'] == 512 and meta['distance'] == 256
    valid &= meta.get('horizontal_shape') == 'circle' and meta.get('vertical_distance') == 256
    valid &= 'astraeon-circle-v1' in meta.get('voxel_git_hash', '')
    valid &= summary['status'] == 'completed'
    if job['case'] == 'streaming':
        valid &= abs(summary['distance_m'] / rows[-1][0] - job['speed']) < .01
    if job['case'] in ('editing', 'smoke'):
        valid &= len(edits) == (2 if job['case'] == 'smoke' else 30)
        valid &= all(e['changed'] == e['verified'] == 128 and e['completion_ms'] >= 0 for e in edits)
    result.update(valid=bool(valid), output=str(folder), warmup_s=meta.get('warmup_actual_s'),
                  near_missing=summary['near_missing_samples'], collision_missing=summary['collision_missing_samples'],
                  static_memory_peak_mib=max((c['static_memory_bytes'] / 1048576 for c in counters), default=0),
                  video_memory_peak_mib=max((c['video_memory_bytes'] / 1048576 for c in counters), default=0))
    windows = []
    for second in range(int(rows[-1][0]) if rows else 0):
        # Full one-second windows, interpolate the fraction of each frame overlapping the window.
        count = 0.0
        for end, ms in rows:
            start = end - ms / 1000
            overlap = max(0, min(end, second + 1) - max(start, second))
            count += overlap / (ms / 1000)
        windows.append(count)
    result['one_second_fps'] = windows
    result['seconds_ge_85_ratio'] = sum(v >= 85 for v in windows) / len(windows) if windows else 0
    checks = {}
    if job['case'] in ('stationary', 'initial_load'):
        checks = dict(mean_120=result['mean_fps'] >= 120, p95_8_33=result['p95_ms'] <= 8.333,
                      p99_11_11=result['p99_ms'] <= 11.111)
    elif job['case'] == 'streaming':
        if job['speed'] == 40:
            checks = dict(mean_90=result['mean_fps'] >= 90, seconds_85=result['seconds_ge_85_ratio'] >= .95,
                          p99_22_22=result['p99_ms'] <= 22.222, no_50=result['over_50'] == 0)
        else:
            checks = dict(mean_120=result['mean_fps'] >= 120, p99_16_67=result['p99_ms'] <= 16.667, no_33=result['over_33'] == 0)
        checks.update(near_loaded=result['near_missing'] == 0, collision_present=result['collision_missing'] == 0)
        task_counts = [sum(c['engine']['tasks'].values()) for c in counters]
        result['queue_first_10_mean'] = statistics.fmean(task_counts[:10]) if task_counts else 0
        result['queue_last_10_mean'] = statistics.fmean(task_counts[-10:]) if task_counts else 0
        checks['queue_not_growing'] = result['queue_last_10_mean'] <= max(32, result['queue_first_10_mean'] * 1.25)
    else:
        event_results = []
        for event in edits:
            m = metrics([r for r in rows if event['t_s'] < r[0] <= event['t_s'] + 2.0])
            m.update(event)
            m['pass'] = m['mean_fps'] >= 120 and m['p99_ms'] <= 16.667 and m['over_33'] == 0
            event_results.append(m)
        result['events'] = event_results
        latencies = [e['completion_ms'] for e in edits]
        result['edit_latency_p95_ms'] = percentile(latencies, .95)
        result['edit_latency_max_ms'] = max(latencies, default=0)
        checks = dict(all_edit_windows=bool(event_results) and all(e['pass'] for e in event_results),
                      latency_p95_100=result['edit_latency_p95_ms'] <= 100, latency_max_200=result['edit_latency_max_ms'] <= 200)
    result['checks'] = checks
    result['performance_pass'] = all(checks.values())
    if job.get('cap', 0):
        result['performance_pass'] = None  # capped review is descriptive, not the uncapped acceptance gate
    save(folder / 'analysis.json', result)
    return result

def report(out, state):
    lines = ['# 本机体素基准结果', '', f"状态：{state['status']}。累计运行 {state.get('elapsed_s', 0)/60:.1f} 分钟。", '',
             '水平圆形256体素（16区块）半径；独立垂直半径256；Y=-128～383，共512层；固定1920×1080渲染目标；原生图形进程串行运行。', '',
             '| 项目 | 轮次 | 平均FPS | P95 ms | P99 ms | 最长帧 ms | 有效 | 达标 |',
             '|---|---:|---:|---:|---:|---:|---|---|']
    for run in state['runs']:
        a = run.get('analysis')
        if a:
            lines.append(f"| {run['name']} | {run['repeat']} | {a['mean_fps']:.1f} | {a['p95_ms']:.2f} | {a['p99_ms']:.2f} | {a['max_ms']:.2f} | {a['valid']} | {a['performance_pass']} |")
        else:
            lines.append(f"| {run['name']} | {run['repeat']} | — | — | — | — | False | 未完成：{run['status']} |")
    lines += ['', '## 范围与限制', '',
              '- 每轮单独判定；运行完成和性能达标分开记录。失败或异常退出不计为通过。',
              '- 使用受控高度图和上游树木生成，无洞穴、玩家逻辑、生物、流体tick、网络及存档。',
              '- 固定1080p SubViewport缩放显示在系统窗口中，包含合成开销；截图读回在采样外。',
              '- 512层是世界边界；水平圆形半径与独立垂直范围裁剪到边界，不保证每个水平位置加载完整512层。',
              '- 24体素离地飞行路径避免穿入地形和树冠，按路径弧长维持3D合速度，不是物理角色地面验收。',
              '- 编辑完成延迟为队列排空、两个进程帧和物理tick以及表面射线校验的保守上界，并非直接GPU网格更新时间。',
              '- 近处网格与地面碰撞每秒检查；不覆盖每一帧和整个远景，人工可见缺口验收仍单列。',
              '- 内存是Godot分配器和渲染估算，不是系统RSS。',
              '- 场景进程为当前Godot编辑器/调试构建；没有与Minecraft比较。', '',
              f"原始记录：{out}", f"停止原因：{state.get('reason', '无')}"]
    (out / 'report.md').write_text('\n'.join(lines) + '\n', encoding='utf-8')

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--run', action='store_true')
    parser.add_argument('--deadline-epoch', type=float, help='Preserve an earlier absolute deadline after a bounded repair')
    parser.add_argument('--driver', choices=['d3d12', 'vulkan'], default='d3d12')
    parser.add_argument('--smoke-only', action='store_true')
    args = parser.parse_args()
    if not args.run:
        parser.error('Explicit --run required; this starts graphical workloads')
    config = json.loads((ROOT / '.agents/skills/godot-project-tooling/godot-toolchains.json').read_text(encoding='utf-8-sig'))
    engine = config['versions'][config['default']]
    out = ROOT / 'tmp/voxel-bench-results' / ('suite-' + datetime.now().strftime('%Y%m%d-%H%M%S'))
    out.mkdir(parents=True)
    started = time.monotonic()
    deadline = started + min(1800, args.deadline_epoch - time.time()) if args.deadline_epoch else started + 1800
    state = dict(status='running', started=datetime.now().isoformat(), budget_seconds=1800, runs=[], engine=engine,
                 hashes={str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in [Path(__file__), PROJECT / 'astraeon_benchmark/benchmark.gd', PROJECT / 'astraeon_benchmark/benchmark_generator.gd', ROOT / 'tools/voxel_patches/horizontal_circle.patch', PROJECT / 'addons/zylann.voxel/bin/libvoxel.windows.editor.x86_64.dll']})
    print(f'SUITE_OUTPUT {out}', flush=True)
    def checkpoint():
        state['elapsed_s'] = time.monotonic() - started
        save(out / 'suite.json', state)
        report(out, state)
    def execute(command, log, timeout):
        if deadline - time.monotonic() <= 30:
            raise RuntimeError('budget_exhausted_before_process_start')
        with log.open('w', encoding='utf-8') as f:
            process = subprocess.Popen(command, stdout=f, stderr=subprocess.STDOUT, cwd=ROOT)
            try:
                code = process.wait(timeout=max(.1, min(timeout, deadline - time.monotonic() - 30)))
            except subprocess.TimeoutExpired:
                subprocess.run(['taskkill', '/PID', str(process.pid), '/T', '/F'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=5)
                process.wait(timeout=5)
                raise RuntimeError('process_timeout_or_budget_exhausted')
        text = log.read_text(encoding='utf-8', errors='replace')
        if code != 0 or re.search(r'SCRIPT ERROR|ERROR:|Parser Error|Parse Error', text):
            raise RuntimeError(f'engine_failed exit={code}; log={log.name}; tail={text[-1000:]}')
        return text
    jobs = [dict(name='validity_smoke', case='smoke', profile='plain', seconds=12, speed=22, repeat=0)]
    for rep in range(1, 4):
        for profile in ('plain', 'forest', 'mountain'):
            jobs.append(dict(name='static_' + profile, case='stationary', profile=profile, seconds=45, speed=22, repeat=rep))
    for rep in range(1, 4):
        jobs.append(dict(name='edit_128_all_layouts', case='editing', profile='plain', seconds=90, speed=22, repeat=rep))
    for rep in range(1, 4):
        for speed in (22, 40):
            jobs.append(dict(name=f'move_{speed}', case='streaming', profile='mixed', seconds=60, speed=speed, repeat=rep))
    jobs += [dict(name='capped_edit_review', case='editing', profile='plain', seconds=90, speed=22, repeat=1, cap=120),
             dict(name='capped_move_review', case='streaming', profile='mixed', seconds=30, speed=22, repeat=1, cap=120)]
    if args.smoke_only:
        jobs = jobs[:1]
    state['driver'] = args.driver
    state['deadline_epoch'] = time.time() + deadline - time.monotonic()
    state['planned_jobs'] = jobs
    checkpoint()
    try:
        version = execute([engine, '--version'], out / 'version.log', 10).strip()
        if not version.startswith('4.7.stable.'):
            raise RuntimeError('Unexpected engine version: ' + version)
        print('VALIDATION import (budget clock started)', flush=True)
        execute([engine, '--headless', '--path', str(PROJECT), '--import'], out / 'import.log', 90)
        for index, job in enumerate(jobs):
            required = job['seconds'] + 45
            if deadline - time.monotonic() < required + 30:
                state['status'] = 'budget_stopped'
                state['reason'] = 'Insufficient remaining budget for next full run; no shortened samples.'
                break
            print(f"RUN {index+1}/{len(jobs)} {job['name']} repeat={job['repeat']} elapsed={time.monotonic()-started:.0f}s", flush=True)
            record = dict(job, status='running')
            state['runs'].append(record)
            checkpoint()
            job_out = out / f'{index:02d}_{job["name"]}_r{job["repeat"]}'
            job_out.mkdir()
            command = [engine, '--path', str(PROJECT), '--resolution', '1280x720', '--windowed', '--rendering-driver', args.driver,
                       'res://astraeon_benchmark/benchmark.tscn', '--', '--run-benchmark', f'--case={job["case"]}',
                       '--distance=256', '--vertical-distance=256', f'--profile={job["profile"]}', f'--seconds={job["seconds"]}', '--warmup=3',
                       f'--speed={job["speed"]}', '--seed=20260913', f'--cap={job.get("cap",0)}', f'--output={job_out}']
            record['command'] = command
            try:
                execute(command, job_out / 'engine.log', required)
                folders = list(job_out.glob('*/summary.json'))
                if len(folders) != 1: raise RuntimeError('Missing or ambiguous summary')
                record['analysis'] = analyse(folders[0].parent, job)
                record['status'] = 'completed'
                if not record['analysis']['valid']: raise RuntimeError('Result validity check failed')
                a = record['analysis']
                print(f"RESULT {job['name']} r{job['repeat']}: FPS={a['mean_fps']:.1f} p99={a['p99_ms']:.2f}ms pass={a['performance_pass']}", flush=True)
            except Exception:
                record['status'] = 'failed'
                raise
            checkpoint()
        else:
            state['status'] = 'completed'
    except Exception as exc:
        state['status'] = 'blocked'
        state['reason'] = str(exc)
        print('STOP ' + str(exc), flush=True)
    finally:
        checkpoint()
        print(f"SUITE_FINISHED status={state['status']} elapsed={state['elapsed_s']:.1f}s report={out / 'report.md'}", flush=True)
    return 0 if state['status'] == 'completed' else 1

if __name__ == '__main__':
    raise SystemExit(main())
