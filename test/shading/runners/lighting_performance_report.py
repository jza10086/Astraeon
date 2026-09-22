"""Generate current-format Markdown from completed segments; never starts an engine."""
from __future__ import annotations
import csv
import json
import math
import statistics as st
from pathlib import Path
from lighting_performance_plan import FORMAT


def percentile(xs, q):
    ys=sorted(xs)
    return ys[int((len(ys)-1)*q)] if ys else None


def med(xs):
    ys=[x for x in xs if x is not None and math.isfinite(x)]
    return st.median(ys) if ys else None


def fmt(x): return "不支持" if x is None else f"{x:.3f}"
def level(x):
    if x is None:return "不支持"
    if x < 0:return "改善"
    return next(label for cap,label in [(0.1,"极低"),(0.5,"低"),(1.0,"中"),(2.5,"高"),(math.inf,"极高")] if x<cap)
def safe(s):return str(s).replace("|","／").replace("\n"," ")


def summarize(segment, folder):
    with (folder/segment['file']).open(encoding='utf-8',newline='') as f:rows=list(csv.DictReader(f))
    def values(key):return [float(r[key]) for r in rows if math.isfinite(float(r[key]))]
    frame=values('frame_ms')
    if not frame:return None
    main=values('gpu_main_ms')
    # Main 0 means unavailable, while reflection 0 on an unscheduled frame means no capture.
    gpu_ok=sum(x>0 for x in main)/len(main)>0.95
    reflected=[r for r in rows if float(r['reflection_scheduled'])>0]
    gpu_ok=gpu_ok and all(float(r['gpu_reflection_ms'])>0 for r in reflected)
    gpu=[float(r['gpu_main_ms'])+float(r['gpu_reflection_ms']) for r in rows] if gpu_ok else []
    result=dict(segment)
    result.update(fps=len(frame)*1000/sum(frame),frame=med(frame),p95=percentile(frame,.95),p99=percentile(frame,.99),
                  over120=sum(x>1000/120 for x in frame)/len(frame)*100,
                  over90=sum(x>1000/90 for x in frame)/len(frame)*100,
                  over60=sum(x>1000/60 for x in frame)/len(frame)*100,
                  update=med(values('update_cpu_ms')),render_cpu=med(values('render_cpu_ms')),
                  gpu=st.mean(gpu) if gpu else None,gpu_main=med(main) if gpu_ok else None,
                  draws=med(values('draw_calls')),primitives=med(values('primitives')),
                  video_mem=med(values('video_mem_bytes')),reflection_hz=len(reflected)/(sum(frame)/1000))
    return result


def telemetry(folder):
    file=folder/'telemetry.csv'
    if not file.exists():return []
    with file.open(encoding='utf-8',newline='') as f:return list(csv.DictReader(f))


def telemetry_window(segment, samples):
    selected=[s for s in samples if segment['start_unix']<=float(s['host_unix'])<=segment['end_unix']]
    def number(key):
        values=[]
        for row in selected:
            try:values.append(float(row[key]))
            except (ValueError,KeyError):pass
        return med(values)
    return dict(temp=number('temperature.gpu'),clock=number('clocks.current.graphics'),power=number('power.draw'))


def write_report(folder: Path):
    manifest=json.loads((folder/'manifest.json').read_text(encoding='utf-8'))
    if manifest.get('format')!=FORMAT:raise ValueError('Unsupported report format')
    events=[]
    if (folder/'events.jsonl').exists():
        for line in (folder/'events.jsonl').read_text(encoding='utf-8').splitlines():
            try:events.append(json.loads(line))
            except json.JSONDecodeError:continue # interrupted final write, never invent a record
    samples=telemetry(folder)
    segments=[]
    for event in events:
        if event.get('event')=='segment' and event.get('complete') and (folder/event['file']).exists():
            result=summarize(event,folder)
            if result:result['telemetry']=telemetry_window(result,samples);segments.append(result)
    out=['# 1080p 光影设置性能报告','',
         '成本单位为 ms；FPS 为整个采样区间的帧数／时长。最大 FPS 不评级。',
         'GPU 为 Godot 主视口＋按捕捉帧计入的反射视口时间估计，不是 PresentMon GPU Busy。限频反射存在异步计时归属误差，单列捕捉频率。',
         'CPU 更新是样板更新函数的墙钟耗时，渲染 CPU 单列；不是整机 CPU 利用率。温度／时钟／功耗不可用时不能宣称已排除热干扰。',
         '每轮 ABBA 或 BAAB 产生两组差值；区间为配对差值的最小～最大值，不是 95% 置信区间。连续帧不是独立重复。',
         '完整配置见 manifest.json，逐帧数据见各 CSV。只有两对时结论为初筛；重复方向一致也不等于因果已完全确认。','']
    meta=next((e for e in events if e.get('event')=='start'),{})
    out+=['## 环境与完成状态','',f"- GPU：{safe(meta.get('gpu','未运行'))}",f"- 引擎：{safe(meta.get('engine',{}).get('string','未运行'))}"]
    launch=folder/'host.json'
    if launch.exists():
        host=json.loads(launch.read_text(encoding='utf-8'))
        out+=['- 主机、Git、驱动和启动结果：host.json',f"- 退出码：{host.get('exit_code','未取得')}；错误日志行数：{len(host.get('errors',[]))}",f"- 遥测状态：{safe(host.get('telemetry','未取得'))}"]
    names={row.get('name','') for row in samples}
    if names and meta.get('gpu') not in names:
        out+=['- 警告：遥测 GPU 名称与渲染 GPU 不一致，硬件遥测不可用于本轮归因。']
        samples=[]
        for segment in segments: segment['telemetry']=dict(temp=None,clock=None,power=None)
    finishes=[e for e in events if e.get('event')=='finish']
    out+=[f"- 驱动正常结束记录：{'有' if finishes else '无；未运行、手动停止或异常退出'}",f"- 完整采样段：{len(segments)}",f"- GPU 遥测样本：{len(samples)}",'']
    out+=['## 设置增量','',
          '| 设置名称 | A → B | 场景／灯数 | 基准 FPS | 测试 FPS | ΔFPS／% | Δ整帧 ms [范围] | ΔGPU估计 ms | Δ更新CPU ms | Δ渲染CPU ms | ΔP99 ms | 帧成本／GPU成本 | 判断 | 人工预判 |',
          '|---|---|---|---:|---:|---|---|---:|---:|---:|---:|---|---|---|']
    completed=set();details=[]
    for case in manifest['cases']:
        ss=[s for s in segments if s['case']==case['id']]
        pairs=[]
        for rnd in sorted({s['round'] for s in ss}):
            aa=[s for s in ss if s['round']==rnd and s['state']=='A'];bb=[s for s in ss if s['round']==rnd and s['state']=='B']
            if len(aa)==2 and len(bb)==2:pairs.extend(zip(aa,bb))
        if not pairs:continue
        completed.add(case['id'])
        def delta(key):return [b[key]-a[key] for a,b in pairs if a[key] is not None and b[key] is not None]
        diffs=delta('frame');d=med(diffs);g=med(delta('gpu'));a_fps=med([a['fps'] for a,b in pairs]);b_fps=med([b['fps'] for a,b in pairs])
        noise=max(.03,(max(diffs)-min(diffs))/2)
        drift=max((e['baseline_drift'] for e in events if e.get('event')=='pair' and e.get('case')==case['id']),default=0)
        missing_thermal=any(s['telemetry'][field] is None for pair in pairs for s in pair for field in ('clock','temp','power'))
        clocks=[s['telemetry']['clock'] for pair in pairs for s in pair if s['telemetry']['clock'] is not None]
        # Frequency spread is a warning, not a mathematical correction factor.
        clock_drift=bool(clocks and max(clocks)/max(min(clocks),1)>1.05)
        verdict='方向一致；初筛' if len(pairs)==2 else '复测方向一致'
        grade=level(d)
        if min(diffs)<=0<=max(diffs) or abs(d)<=noise:verdict='未检出稳定差异';grade='待定'
        if drift>.05:verdict+='；基线漂移>5%';grade='待定'
        if clock_drift:verdict+='；频率差>5%';grade='待定'
        if missing_thermal:verdict+='；遥测缺失'
        if med(delta('p99'))>1:verdict+='；尾帧风险'
        gpu_diffs=delta('gpu');gpu_grade=level(g)
        if not gpu_diffs:gpu_grade='不支持'
        elif min(gpu_diffs)<=0<=max(gpu_diffs) or abs(g)<=max(.03,(max(gpu_diffs)-min(gpu_diffs))/2) or drift>.05 or clock_drift:gpu_grade='待定'
        title=manifest['properties'][case['key']]
        def value(v):return title['titles'][v] if title['titles'] and isinstance(v,int) else str(v)
        lamps=f"{case['a']}→{case['b']}" if case['kind']=='cardinality' else str(case['lamps'])
        out.append(f"| {safe(case['name'])} `{case['id']}` | {safe(value(case['a']))} → {safe(value(case['b']))} | {case['scene']}／{lamps} | {a_fps:.1f} | {b_fps:.1f} | {b_fps-a_fps:+.1f}／{(b_fps/a_fps-1)*100:+.1f}% | {d:+.3f} [{min(diffs):+.3f}, {max(diffs):+.3f}] | {fmt(g)} | {fmt(med(delta('update')))} | {fmt(med(delta('render_cpu')))} | {fmt(med(delta('p99')))} | {grade}／{gpu_grade} | {verdict} | {safe(case['prior'])} |")
        details.append(dict(case=case['id'],delta_frame_ms=d,delta_gpu_estimate_ms=g,grade=grade,gpu_grade=gpu_grade,verdict=verdict))
    out+=['','评级：极低 <0.10ms；低 <0.50ms；中 <1.00ms；高 <2.50ms；极高 ≥2.50ms。负值记为改善。噪声或明显漂移时不强行评级。','',
          '## 更新、编辑与组合','', '| 用例 | 类型／状态 | FPS | P95／P99 ms | >8.33ms帧% | >11.11ms帧% | >16.67ms帧% | 编辑提交／完成 ms | 反射捕捉 Hz | GPU温度／频率／功耗 |','|---|---|---:|---|---:|---:|---:|---|---:|---|']
    for s in segments:
        if s['case'].startswith('combo') or s.get('edit_apply_ms',0)>0:
            t=s['telemetry'];out.append(f"| {s['case']} | {s['state']} | {s['fps']:.1f} | {s['p95']:.3f}／{s['p99']:.3f} | {s['over120']:.1f} | {s['over90']:.1f} | {s['over60']:.1f} | {s.get('edit_apply_ms',0):.3f}／{s.get('edit_complete_ms',-1):.3f} | {s['reflection_hz']:.1f} | {fmt(t['temp'])}℃／{fmt(t['clock'])}MHz／{fmt(t['power'])}W |")
    out+=['','编辑完成为 -1 表示采样段内未完成，不能记为零开销。设置应用耗时见 events.jsonl 的 switch 记录；不含随后驱动编译和异步上传，不称为完整切换卡顿。',
          '60 秒组合仅做持续表现抽查，不足以宣称整机已达到热平衡。', '', '## 参数覆盖','', '| 设置 | 已完成对照／规划对照 | 状态 |','|---|---:|---|']
    for key,ids in manifest['coverage'].items():
        count=sum(i in completed for i in ids)
        status=manifest['policies'].get(key,'本轮未选择' if not ids else ('完成' if count==len(ids) else '部分完成／待测'))
        out.append(f"| {safe(manifest['properties'][key]['label'])} `{key}` | {count}／{len(ids)} | {status} |")
    out+=['','写实体积云：已删除，仅保留人工历史预判“中”，没有当前测量结果。','',f"用例完成 {len(completed)}／{len(manifest['cases'])}；未采集内容不会用历史数值补齐。"]
    (folder/'report.md').write_text('\n'.join(out)+'\n',encoding='utf-8')
    (folder/'summary.json').write_text(json.dumps(details,ensure_ascii=False,indent=2),encoding='utf-8')
    # Segment-level summary retains counters and thermal measurements without rereading raw frames.
    (folder/'segments.json').write_text(json.dumps(segments,ensure_ascii=False,indent=2),encoding='utf-8')
