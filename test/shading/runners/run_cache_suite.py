"""1080p old/new cache ABBA comparison. --run is required to launch Godot."""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import statistics
import subprocess
import time
from run_lighting_suite import ROOT, CREATE_HIDDEN, Telemetry, engine_path, git


def fingerprint(root: Path):
    paths = [root/'project.godot', root/'addons/zylann.voxel/voxel.gdextension']
    paths += sorted((root/'game').rglob('*.gd')) + sorted((root/'game').rglob('*.gdshader*'))
    paths += sorted((root/'game').rglob('*.tres'))
    for suffix in ('*.tscn','*.glsl','*.png','*.glb','*.gltf','*.jpg','*.svg'):
        paths += sorted((root/'game').rglob(suffix))
    return {str(p.relative_to(root)):hashlib.sha256(p.read_bytes()).hexdigest() for p in paths if p.is_file()}


def quality_settings(result):
    # Script instance IDs change in every Godot process; they are not a quality knob.
    return {k:v for k,v in result['quality'].items() if k!='script'}


def report(folder: Path):
    runs = []
    for result in sorted(folder.glob("*/results.json")):
        value = json.loads(result.read_text(encoding="utf-8"))
        value["run"] = result.parent.name
        # Include interest changes/metric collection, not only texture submission.
        # These values are derived from raw rows; leave measured JSON evidence intact.
        if not value["legacy"]:
            phases={s["phase"]:{"slow":0,"peak":0.0} for s in value["summaries"]}
            for row in json.loads((result.parent/"frames.json").read_text(encoding="utf-8")):
                cost=max(float(row.get("cache_tick_usec",0)),float(row["cache"].get("upload_usec",0)))/1000.0
                phases[row["phase"]]["peak"]=max(phases[row["phase"]]["peak"],cost)
                phases[row["phase"]]["slow"]+=cost>16.7
            for summary in value["summaries"]:
                summary["light_slow_frames"]=phases[summary["phase"]]["slow"]
                summary["cache_tick_peak_ms"]=phases[summary["phase"]]["peak"]
        runs.append(value)
    lines = ["# 地图与光照缓存对照", "", "1080p、Forward+ / D3D12、相同光影配置；AB / BA 两轮。帧间隔为墙钟时间，GPU 时间为引擎视口计时。", "",
             "首次生成、首次管线编译与缓存命中必须分开解读；编译慢帧保留在原始数据和最大帧耗时中。收敛时间已扣除固定 1.5 秒稳定确认窗口。", "",
             "| 运行 | 视距 | 路径 | FPS | 1% Low | 中位 ms | P99 ms | 最大 ms | >16.7ms | 光照主线程 >16.7ms | 收敛 ms | 光照批次年龄 ms | 队列 | CPU 缓存 MiB | GPU 光照 MiB |", "|---|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|"]
    for run in runs:
        for s in run["summaries"]:
            c = s["cache_settled"]
            cpu = sum(c.get(key, 0) for key in ("voxel_bytes", "light_bytes", "derived_bytes", "temporary_bytes", "weather_cpu_bytes")) / 1048576
            lines.append(f"| {run['run']} | {run['distance']} | {s['phase']} | {s['fps']:.1f} | {s['low']:.1f} | {s['median_ms']:.3f} | {s['p99_ms']:.2f} | {s['max_ms']:.2f} | {s['slow_frames']} | {s['light_slow_frames']} | {max(0,s['convergence_ms']-1500)} | {format(c.get('light_latency_usec',0)/1000,'.1f') if not run['legacy'] else '—'} | {c.get('queue','—')} | {format(cpu,'.2f') if not run['legacy'] else '—'} | {format(c.get('gpu_bytes',0)/1048576,'.0f') if not run['legacy'] else '—'} |")
    lines += ["", "## 缓存与更新覆盖", "", "旧版没有这些计数的项目用 — 表示，不将缺失值解释成零。命中率分别按地图进入请求和光照版本检查统计，两者不是同一分母。", "", "| 运行 | 路径 | 测量中发布页数 | 地图命中率 | 光照版本命中率 | 新网格任务 | 网格复用 | 过期结果 | 上传 MiB | 发布时批次年龄 P99 ms | 编译帧数 |", "|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|"]
    for run in runs:
        if run['legacy']: continue
        for s in run['summaries']:
            a,b,c=s['cache_before'],s['cache_after'],s['cache_settled']
            def fraction(hit,miss):
                return f"{100*c.get(hit,0)/max(1,c.get(hit,0)+c.get(miss,0)):.1f}%"
            terrain=s['terrain']
            published=b['page_uploads']-a['page_uploads']
            latency=f"{s['light_latency_p99_ms']:.1f}" if published else '—（期间无发布）'
            lines.append(f"| {run['run']} | {s['phase']} | {published} | {fraction('map_hits','map_misses')} | {fraction('light_hits','section_reads')} | {terrain.get('derived_misses','—')} | {terrain.get('derived_hits','—')} | {c.get('stale_results','—')} | {(c.get('uploaded_bytes',0)-a.get('uploaded_bytes',0))/1048576:.2f} | {latency} | {s.get('compilation_frames','—')} |")
    lines += ["", "## 验收门槛", "", "| 视距 | 静止中位帧耗时回退 | ≤10% | 旧/新光照慢帧 | 减少≥90% |", "|---|---:|---|---|---|"]
    for distance in (64, 256):
        groups = {old: [s for r in runs if r["distance"] == distance and r["legacy"] == old for s in r["summaries"]] for old in (True, False)}
        complete = all(sum(r['distance']==distance and r['legacy']==old for r in runs)==2 for old in (True,False))
        if not complete or not all(groups.values()):
            lines.append(f"| {distance} | 缺少完整对照 | 未验收 | — | 未验收 |")
            continue
        old_static = [s["median_ms"] for s in groups[True] if s["phase"] == "static"]
        new_static = [s["median_ms"] for s in groups[False] if s["phase"] == "static"]
        regression = statistics.median(new_static)/statistics.median(old_static)-1 if old_static and new_static else None
        phases = {"orbit_boundary", "move_8", "move_22", "move_40", "return_22", "continuous_40"}
        old_slow, new_slow = (sum(s["light_slow_frames"] for s in groups[o] if s["phase"] in phases) for o in (True, False))
        verdict = "通过" if old_slow and new_slow <= old_slow*.1 else "未证明"
        lines.append(f"| {distance} | {regression*100:.1f}% | {'通过' if regression<=.1 else '未通过'} | {old_slow}/{new_slow} | {verdict} |")
    lines += ["", "新版光照主线程慢帧包含整个缓存协调入口（人物需求改变、提交、统计），旧版使用快照加发布入口。该表不能单独证明全部验收：需结合原始帧、管线编译计数、窗口焦点、telemetry.csv、正确性测试及日志错误检查。批次年龄从当前未收敛批次的首次失效计时，连续移动时会包含较早请求，不能当作单个近处编辑的精确可见延迟；静止期间不会清零。实际编辑还需 GPU 读回验证。", ""]
    (folder/"report.md").write_text("\n".join(lines), encoding="utf-8")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run", action="store_true")
    parser.add_argument("--godot")
    parser.add_argument("--baseline", type=Path, default=ROOT/"tmp/cache-baseline")
    parser.add_argument("--output", type=Path)
    parser.add_argument("--resume", action="store_true", help="Resume a matching interrupted matrix in --output")
    parser.add_argument("--seconds", type=float, default=8)
    parser.add_argument("--distances", nargs="+", type=int, default=[64, 256], choices=[64, 256])
    parser.add_argument("--report-only", type=Path)
    args = parser.parse_args()
    if args.report_only:
        report(args.report_only.resolve());return
    schedule = [(distance, round_index, old) for distance in args.distances for round_index in range(2) for old in ([True, False] if round_index == 0 else [False, True])]
    print(f"{len(schedule)} runs; 10 paths × {args.seconds}s, plus initial loading and convergence; 1080p")
    if not args.run:
        print("Plan only; no engine started.");return
    baseline = args.baseline.resolve()
    if not baseline.is_relative_to((ROOT/"tmp").resolve()) or not (baseline/"project.godot").is_file():
        parser.error("Provide the isolated, imported pre-cache baseline checkout under tmp")
    folder = (args.output or ROOT/"tmp"/time.strftime("cache-suite-%Y%m%d-%H%M%S")).resolve()
    if not folder.is_relative_to((ROOT/"tmp").resolve()) or (folder.exists() and not args.resume):
        parser.error("Output must be a new directory under tmp")
    executable, version = engine_path(args.godot)
    folder.mkdir(parents=True,exist_ok=args.resume)
    shutil.copy2(ROOT/"test/shading/gdscript/cache_benchmark.gd", baseline/"test/shading/gdscript/cache_benchmark.gd")
    manifest = {"format":1,"engine":version,"head":git("rev-parse","HEAD"),"dirty":git("status","--short"),"schedule":schedule,"seconds":args.seconds,"fingerprints":{"old":fingerprint(baseline),"new":fingerprint(ROOT)},"runs":[]}
    if args.resume:
        previous=json.loads((folder/'manifest.json').read_text(encoding='utf-8'))
        if previous['schedule'] != json.loads(json.dumps(schedule)) or previous['seconds']!=args.seconds or previous['fingerprints']!=manifest['fingerprints']:
            parser.error('Resume rejected: source, duration or schedule changed')
        manifest=previous
    (folder/"manifest.json").write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding="utf-8")
    telemetry_folder=folder/(time.strftime("resume-telemetry-%Y%m%d-%H%M%S") if args.resume else ".")
    telemetry_folder.mkdir(exist_ok=True)
    telemetry = Telemetry(telemetry_folder,"0")
    telemetry.start()
    try:
        for distance, round_index, old in schedule:
            name = f"d{distance}-r{round_index+1}-{'old' if old else 'new'}"
            target = folder/name
            if args.resume and (target/'results.json').is_file():
                result=json.loads((target/'results.json').read_text(encoding='utf-8'))
                log=(target/'process.log').read_text(encoding='utf-8',errors='replace')
                if result['failures'] or any(s['unfocused'] for s in result['summaries']) or any(x in log for x in ('SCRIPT ERROR','SHADER ERROR','ERROR:')):
                    raise RuntimeError(name+': existing result is invalid; use a new output directory')
                print('REUSE',name,flush=True)
                continue
            target.mkdir()
            command = [str(executable),"--path",str(baseline if old else ROOT),"--resolution","1920x1080","--position","0,0","--rendering-method","forward_plus","--rendering-driver","d3d12","--script","res://test/shading/gdscript/cache_benchmark.gd","--log-file",str(target/"godot.log"),"--",f"--output={target.as_posix()}",f"--distance={distance}",f"--seconds={args.seconds}"]
            if old:command.append("--legacy")
            if round_index:command.append("--reverse")
            print("START",name,flush=True)
            began=time.monotonic()
            began_unix=time.time()
            with (target/"process.log").open("w",encoding="utf-8") as log:
                process=subprocess.Popen(command,cwd=ROOT,stdout=log,stderr=subprocess.STDOUT,creationflags=CREATE_HIDDEN)
                try:
                    deadline=time.monotonic()+600
                    with (target/"process.log").open(encoding="utf-8",errors="replace") as monitor:
                        while process.poll() is None:
                            text=monitor.read()
                            if any(token in text for token in ("SCRIPT ERROR","SHADER ERROR","ERROR:")):
                                process.terminate();process.wait(timeout=15)
                                raise RuntimeError(name+": runtime error; see log")
                            if time.monotonic()>deadline:
                                process.terminate();process.wait(timeout=15)
                                raise RuntimeError(name+": process deadline")
                            time.sleep(.5)
                finally:
                    if process.poll() is None:process.terminate();process.wait(timeout=15)
            entry={"name":name,"seconds":time.monotonic()-began,"exit":process.returncode,"start_unix":began_unix,"end_unix":time.time()}
            manifest["runs"].append(entry)
            (folder/"manifest.json").write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding="utf-8")
            logs=(target/"process.log").read_text(encoding="utf-8",errors="replace")
            if process.returncode or any(token in logs for token in ("SCRIPT ERROR","SHADER ERROR","ERROR:")):
                raise RuntimeError(name+": failed; see logs")
            result=json.loads((target/"results.json").read_text(encoding="utf-8"))
            if result["failures"] or any(s["unfocused"] for s in result["summaries"]):
                raise RuntimeError(name+": incomplete or unfocused run")
            if result['viewport'] != '(1920, 1080)' or result['max_fps'] != 0 or result['vsync'] != 0:
                raise RuntimeError(name+': render resolution or frame limiter changed')
            earlier = next((p for p in folder.glob('*/results.json') if p.parent != target), None)
            if earlier and quality_settings(json.loads(earlier.read_text(encoding='utf-8'))) != quality_settings(result):
                raise RuntimeError(name+': quality differs between runs')
            report(folder)
            print("DONE",name,round(entry["seconds"],1),flush=True)
    finally:
        telemetry.stop();report(folder)
    print(folder/"report.md",flush=True)


if __name__ == "__main__":
    main()
