"""One-hour 1080p lighting cost suite. No engine or telemetry starts without --run."""
from __future__ import annotations
import argparse
import csv
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import threading
import time
import sys
sys.dont_write_bytecode = True
from lighting_performance_plan import make_plan, ROOT, FORMAT
from lighting_performance_report import write_report

PROJECT=ROOT/'benchmarks/voxelgame/project'
CREATE_HIDDEN=getattr(subprocess,'CREATE_NO_WINDOW',0)
FIELDS=['name','driver_version','temperature.gpu','clocks.current.graphics','clocks.current.memory','power.draw','utilization.gpu','clocks_event_reasons.active']


def engine_path(explicit):
    if explicit:path=Path(explicit).resolve(strict=True)
    else:
        config=json.loads((ROOT/'.agents/skills/godot-project-tooling/godot-toolchains.json').read_text(encoding='utf-8-sig'))
        path=Path(config['versions']['4.7.stable']).resolve(strict=True)
    # Own the GUI executable directly; a console launcher may spawn an unowned child.
    if path.name.endswith('_console.exe'):
        direct=path.with_name(path.name.replace('_console.exe','.exe'))
        if not direct.exists():raise RuntimeError('Expected Godot GUI executable missing')
        path=direct
    version=subprocess.run([str(path),'--version'],capture_output=True,text=True,timeout=15,check=True,creationflags=CREATE_HIDDEN).stdout.strip()
    if not version.startswith('4.7.stable.'):raise RuntimeError(f'Expected Godot 4.7 stable, got {version!r}')
    return path,version


def git(*args):
    r=subprocess.run(['git','-c',f'core.excludesFile={ROOT / ".gitignore"}',*args],cwd=ROOT,capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=10)
    return r.stdout.strip() if r.returncode==0 else 'unavailable'


class Telemetry:
    def __init__(self,folder,gpu):self.folder=folder;self.gpu=gpu;self.proc=None;self.thread=None;self.status='not started'
    def start(self):
        binary=shutil.which('nvidia-smi')
        if not binary:self.status='nvidia-smi unavailable; thermal control unverified';return
        command=[binary,f'--id={self.gpu}','--query-gpu='+','.join(FIELDS),'--format=csv,noheader,nounits','--loop-ms=1000']
        self.proc=subprocess.Popen(command,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,encoding='utf-8',errors='replace',creationflags=CREATE_HIDDEN)
        def consume():
            with (self.folder/'telemetry.csv').open('w',encoding='utf-8',newline='') as f, (self.folder/'telemetry-status.log').open('w',encoding='utf-8') as log:
                writer=csv.writer(f);writer.writerow(['host_unix',*FIELDS])
                for line in self.proc.stdout:
                    row=next(csv.reader([line]))
                    if len(row)==len(FIELDS):writer.writerow([time.time(),*map(str.strip,row)]);f.flush();self.status='capturing'
                    else:log.write(line);log.flush();self.status='query failed or unsupported; see telemetry-status.log'
        self.thread=threading.Thread(target=consume,daemon=True);self.thread.start()
    def stop(self):
        if self.proc:
            if self.proc.poll() is None:self.proc.terminate()
            self.proc.wait(timeout=5)
            self.thread.join(timeout=5)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--run',action='store_true',help='Explicitly authorize a real rendering run')
    parser.add_argument('--godot',help='Godot 4.7 stable executable')
    parser.add_argument('--gpu',default='0',help='nvidia-smi GPU index or UUID; must match rendered adapter')
    parser.add_argument('--output',type=Path,help='New result directory under this checkout/tmp')
    parser.add_argument('--report-only',type=Path,help='Generate report from existing current-format results, without running Godot')
    args=parser.parse_args()
    if args.report_only:
        if args.run:parser.error('--report-only and --run are mutually exclusive')
        folder=args.report_only.resolve()
        if not folder.is_relative_to((ROOT/'tmp').resolve()):parser.error('Report directory must be under checkout/tmp')
        write_report(folder);print(folder/'report.md');return
    plan=make_plan()
    print(f"1080p | {len(plan['properties'])} exported settings | {len(plan['cases'])} paired comparisons")
    print(f"Nominal first pass {plan['nominal_primary_seconds']/60:.1f} min; primary cutoff 49 min; retry cutoff 54 min; sampling cutoff 58 min; process watchdog 59 min.")
    print('ABBA per comparison: 1.5 s stabilization + 3 s capture per segment. Main schemes and first probe of each field precede extra sweep points. Partial coverage reported explicitly.')
    if not args.run:
        print('PLAN ONLY: no files, engine, telemetry or benchmark started. Use --run only after authorization.')
        return
    folder=(args.output or ROOT/'tmp'/('lighting-cost-'+time.strftime('%Y%m%d-%H%M%S'))).resolve()
    if not folder.is_relative_to((ROOT/'tmp').resolve()):parser.error('Output must be inside checkout/tmp')
    if folder.exists():parser.error('Output must be a new directory; never mix runs')
    path,version=engine_path(args.godot)
    folder.mkdir(parents=True)
    (folder/'manifest.json').write_text(json.dumps(plan,ensure_ascii=False,indent=2),encoding='utf-8')
    metadata=dict(format=FORMAT,host=platform.platform(),engine=str(path),version=version,git=git('rev-parse','HEAD'),dirty=git('status','--short'),gpu_telemetry_id=args.gpu,
                  notes='Plug in AC, fixed fan/power mode; close nested editor and other GPU workloads. No automatic OS/clock/power changes.')
    (folder/'host.json').write_text(json.dumps(metadata,ensure_ascii=False,indent=2),encoding='utf-8')
    telemetry=Telemetry(folder,args.gpu)
    command=[str(path),'--path',str(PROJECT),'--resolution','1920x1080','--rendering-method','forward_plus','--rendering-driver','d3d12',
             '--script','res://astraeon_lighting/performance_suite.gd','--log-file',str(folder/'godot.log'),'--',
             '--run-cost-suite','--manifest='+str(folder/'manifest.json'),'--output='+str(folder)]
    began=time.monotonic();proc=None;interrupted=False
    try:
        telemetry.start()
        with (folder/'process.log').open('w',encoding='utf-8') as log:
            proc=subprocess.Popen(command,stdout=log,stderr=subprocess.STDOUT,cwd=ROOT,creationflags=CREATE_HIDDEN)
            try:metadata['exit_code']=proc.wait(timeout=3540)
            except subprocess.TimeoutExpired:
                metadata['watchdog']='59 minute process deadline';proc.kill();proc.wait();metadata['exit_code']=124
            except KeyboardInterrupt:
                interrupted=True;proc.terminate();proc.wait(timeout=10);metadata['exit_code']=130
    finally:
        if proc and proc.poll() is None:proc.kill();proc.wait()
        telemetry.stop()
        metadata['elapsed_seconds']=time.monotonic()-began
        metadata['telemetry']=telemetry.status
        errors=[]
        for name in ('process.log','godot.log'):
            if (folder/name).exists():
                errors.extend(line for line in (folder/name).read_text(encoding='utf-8',errors='replace').splitlines() if any(token in line for token in ('SCRIPT ERROR','SHADER ERROR','ERROR:')))
        metadata['errors']=errors
        (folder/'host.json').write_text(json.dumps(metadata,ensure_ascii=False,indent=2),encoding='utf-8')
        # Recover completed segments even if the driver was interrupted or crashed.
        write_report(folder)
    print(folder/'report.md')
    if metadata.get('exit_code',1)!=0 or metadata['errors'] or interrupted:raise SystemExit(1)

if __name__=='__main__':main()
