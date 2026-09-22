"""Current-contract lighting matrix. Pure planning: never starts Godot."""
from __future__ import annotations
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
LAB = ROOT / "game/shading/gdscript"
FORMAT = "astraeon-shading-cost-2"
POLICIES = {"show_fps": "固定关闭，避免 HUD 更新干扰", "max_fps": "不限帧，另有 120 FPS 组合验证", "vsync_enabled": "固定关闭，避免刷新率封顶"}
PRIORS = {"ao_enabled":"极低", "fog_enabled":"极低", "direct_enabled":"中", "shadows_enabled":"中", "hard_shadows":"几乎无区别", "shadow_quality":"区别不大", "clouds_enabled":"极低", "water_quality":"统一极低／深度低", "aa_mode":"FXAA 极低／TAA 高", "water_reflection_mode":"SSR 低／平面高", "shadow_resolution":"1024/2048相近；4096低；8192高"}


def properties() -> dict:
    text = (LAB / "shading_profile.gd").read_text(encoding="utf-8")
    panel = (LAB / "settings_panel.gd").read_text(encoding="utf-8")
    label_block = panel.split("var labels: Dictionary[StringName, String] = {", 1)[1].split("var tips:", 1)[0]
    labels = dict(re.findall(r'&"(\w+)": "([^"\n]+)"', label_block))
    extra = (LAB / "shading_controls.gd").read_text(encoding="utf-8-sig")
    labels.update(json.loads(extra.split("const LABELS: Dictionary[String, String] = ",1)[1].split("\nconst GROUPS:",1)[0]))
    result = {}
    for hint, key, typ, raw in re.findall(r'^(@export[^\n]*?) var (\w+): (\w+) = ([^\n]+)', text, re.M):
        if typ == "Color":
            value = [float(x) for x in raw.removeprefix("Color(").removesuffix(")").split(",")]
            value += [1.0] * (4-len(value))
        elif typ == "bool": value = raw == "true"
        else: value = float(raw) if typ == "float" else int(raw)
        titles = re.findall(r'"([^"]+)"', hint) if "@export_enum" in hint else []
        result[key] = dict(type=typ, default=value, titles=titles, label=labels.get(key,key), hint=hint)
    if not result: raise ValueError("No current profile exports found")
    return result


def make_plan() -> dict:
    props = properties()
    extra = (LAB / "shading_controls.gd").read_text(encoding="utf-8-sig")
    deferred = json.loads(extra.split("const LABELS: Dictionary[String, String] = ",1)[1].split("\nconst GROUPS:",1)[0])
    for key in deferred:
        POLICIES[key] = "新增模块未纳入旧性能工作负载；本轮仅功能验证，不评级"
    base = {k:v["default"] for k,v in props.items()}
    base.update(show_fps=False, max_fps=0, vsync_enabled=False, cycle_enabled=False,
                hour=12.0, ambient_minimum=0.015, shadow_bias=0.06, shadow_normal_bias=2.0,
                clouds_enabled=False, wind_enabled=False, translucency_enabled=False,
                avatar_visible=False, avatar_animate=False, aa_mode=0, shadows_enabled=False,
                water_enabled=False, water_reflection_mode=0, bloom_enabled=False,
                gloss_enabled=False, wet_enabled=False, rain_enabled=False, light_budget=64, light_shadow_budget=32)
    cases = []
    def add(key, a, b, context=None, scene="outdoor", lamps=0, kind="steady", priority=1, note=""):
        cfg = dict(base); cfg.update(context or {}); cfg[key] = a
        cases.append(dict(id=f"c{len(cases):03d}", key=key, name=props[key]["label"],
                          a=a,b=b,settings=cfg,scene=scene,lamps=lamps,kind=kind,priority=priority,
                          prior=PRIORS.get(key,"未提供"),note=note))
    # Core modes first, including static/dynamic shadow receivers and two fixed water views.
    for key in ["ao_enabled","fog_enabled","direct_enabled","shadows_enabled","clouds_enabled","bloom_enabled","wind_enabled","translucency_enabled"]:
        scene = "plants" if key in ("wind_enabled","translucency_enabled") else "outdoor"
        add(key,False,True, {"direct_enabled":True,"block_cloud_shadows":False},scene,16 if key=="bloom_enabled" else 0,priority=0)
    for mode in [1,2]: add("aa_mode",0,mode,scene="moving",priority=0)
    for scene in ["water_wide","water_close"]:
        ctx=dict(water_enabled=True, waves_enabled=False, water_reflection=False, avatar_visible=True,avatar_animate=True)
        add("water_quality",0,1,ctx,scene,priority=0)
        for mode in [1,2]: add("water_reflection_mode",0,mode,ctx,scene,priority=0)
    add("block_cloud_shadows",False,True,dict(clouds_enabled=True),priority=0)
    for count in [1,8,16,32]:
        for mode in [1,2,3,4]: add("local_lighting_mode",0,mode,scene="lamps",lamps=count,priority=0)
    for value in [0,2,3]: add("shadow_resolution",1,value,dict(shadows_enabled=True,hour=17.6),priority=0)
    add("hard_shadows",False,True,dict(shadows_enabled=True,hour=17.6),priority=0)
    add("hard_shadows",False,True,dict(shadows_enabled=True,avatar_visible=True,avatar_animate=True),"moving",16,priority=0)
    # Parameter contexts ensure a parameter's parent effect is actually active.
    def context(key):
        cfg={};scene="outdoor";lamps=0
        if key.startswith("water_") or key.startswith("wave") or key.startswith("underwater_"):
            cfg.update(water_enabled=True,water_quality=1,waves_enabled=True,water_reflection=True);scene="water_close"
        if key.startswith("water_ssr_"): cfg["water_reflection_mode"]=1
        if key.startswith("planar_"):
            cfg.update(water_enabled=True,water_reflection_mode=2,avatar_visible=True,avatar_animate=True,clouds_enabled=True,fog_enabled=True);scene="water_close"
            if key=="planar_visible_only":scene="water_away"
        if key.startswith("underwater_"):cfg["underwater_enabled"]=True;scene="underwater"
        if key=="water_low_opacity":cfg["water_quality"]=0
        if key.startswith("cloud_") or key=="block_cloud_shadows":cfg.update(clouds_enabled=True,block_cloud_shadows=True)
        if key.startswith("fog_"):cfg["fog_enabled"]=True
        if key.startswith("ao_"):cfg["ao_enabled"]=True
        if key.startswith("shadow_") or key=="hard_shadows":cfg.update(shadows_enabled=True,hard_shadows=False,hour=17.6)
        if key.startswith("ambient_"):scene="cave"
        if key=="ambient_minimum_color":cfg["ambient_minimum"]=0.05
        if key.startswith("local_") or key.startswith("indirect_") or key in ("block_color","block_energy","block_curve") or key.startswith("voxel_light"):
            cfg.update(local_lighting_mode=4 if "budget" in key else 1,indirect_enabled=True);scene="lamps";lamps=16
        if key in ("local_point_budget","local_shadow_budget"):
            lamps=32
            if key=="local_shadow_budget":cfg["local_point_budget"]=32
        if key.startswith("indirect_"):cfg["local_lighting_mode"]=2
        if key.startswith("local_light_"):cfg["local_lighting_mode"]=2
        if key.startswith("lamp_"):cfg["local_lighting_mode"]=0;scene="lamps";lamps=16
        if key.startswith("bloom_"):cfg["bloom_enabled"]=True;scene="lamps";lamps=16
        if key.startswith("wind_") or key.startswith("translucency_"):cfg.update(wind_enabled=True,translucency_enabled=True);scene="plants"
        if key.startswith("avatar_"):cfg.update(avatar_visible=True,avatar_animate=True,water_enabled=True,water_reflection_mode=2);scene="water_close"
        if key in ("cycle_enabled","day_seconds"):cfg.update(cycle_enabled=True,hour=17.6)
        return cfg,scene,lamps
    sweeps={"shadow_quality":[0,2,3,4],"shadow_distance":[32,192,256],"shadow_blur":[0,2,4],
            "water_ssr_steps":[8,16,64,128],"water_ssr_refinements":[0,3,8],
            "planar_resolution_scale":[0.25,0.75,1.0],"planar_update_fps":[15,30,60],
            "planar_blur_pixels":[0,3],"local_point_budget":[0,4,16,32],"local_shadow_budget":[0,2,8,16],
            "local_light_energy":[0,12],"local_light_range":[4,24],"cloud_coverage":[0.2,0.8],"ambient_smoothing":[0,0.5],
            "ambient_minimum":[0,0.05],"shadow_bias":[0,0.1],"shadow_normal_bias":[1.0,1.7,3.0],
            "lamp_emission_strength":[0,0.5,4,8],"water_enabled":[False],"hour":[0,17.6]}
    core = {c['key'] for c in cases}
    for key,prop in props.items():
        if key in POLICIES or key in ("work_cells","work_usec","test_light_count"):continue
        if key in core and key not in sweeps:continue
        cfg,scene,lamps=context(key);a=cfg.get(key,base[key])
        if key in sweeps:values=sweeps[key]
        elif prop["type"]=="bool":values=[not a]
        elif prop["type"]=="Color":values=[[0.15,0.35,0.65,1.0]]
        elif prop["titles"]:values=[i for i in range(len(prop['titles'])) if i!=a]
        else:
            limits=re.search(r'@export_range\(([^)]+)',prop['hint'])
            lo,hi=[float(x) for x in limits.group(1).split(',')[:2]]
            b=lo if abs(a-lo)>abs(a-hi) else hi
            values=[int(b) if prop['type']=='int' else b]
        for value in values:
            if value!=a:add(key,a,value,cfg,scene,lamps,priority=1)
    # Cardinality is a workload parameter, not an effect toggle.
    for count in [1,8,16,32]:add("test_light_count",0,count,dict(local_lighting_mode=0),"lamps",kind="cardinality",note="0 个灯块到 N 个，仅自发光；0 为无灯布局而非设置范围")
    for key,values in {"work_cells":[1024,16384],"work_usec":[500,6000]}.items():
        for value in values:
            for kind in ["edit_place","edit_remove"]:add(key,base[key],value,kind=kind,priority=1)
    # Follow-up diagnostics don't displace primary coverage.
    add("lamp_emission_strength",0,4,dict(bloom_enabled=True),"lamps",16,priority=2,note="Bloom interaction")
    add("shadows_enabled",False,True,dict(hour=0.0),priority=2,note="Moon")
    seen=set()
    for case in cases:
        slot=(case['key'],case['kind'])
        if case['priority']!=0:
            case['priority']=2 if slot in seen else 1
        seen.add(slot)
    cases.sort(key=lambda c:c['priority'])
    coverage={k:[c['id'] for c in cases if c['key']==k] for k in props}
    assert all(coverage[k] or k in POLICIES for k in props), "Uncovered exported field"
    return dict(format=FORMAT,resolution=[1920,1080],budget_seconds=3600,
                initial_warm_seconds=180.0,settle_seconds=1.5,sample_seconds=3.0,
                primary_deadline_seconds=2940,retry_deadline_seconds=3240,
                stop_sampling_seconds=3480,hard_stop_seconds=3540,
                seed=918,properties=props,base=base,cases=cases,coverage=coverage,policies=POLICIES,
                nominal_primary_seconds=180+18*len(cases),
                sustained_seconds=60, historical_priors={"写实体积云":"人工预判中；实现已删除，不测试"})

if __name__=="__main__":
    plan=make_plan()
    print(json.dumps(dict(cases=len(plan['cases']),fields=len(plan['properties']),nominal_seconds=plan['nominal_primary_seconds']),ensure_ascii=False))
