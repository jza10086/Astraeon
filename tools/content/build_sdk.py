"""Generate a matching Godot content-authoring SDK from this checkout; no forked Resources."""
from pathlib import Path
import argparse, shutil, re, json, hashlib
ROOT=Path(__file__).resolve().parents[2]
def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',default='tmp/content/sdk')
    args=parser.parse_args()
    destination=(ROOT/args.output).resolve()
    if not destination.is_relative_to(ROOT/'tmp'):
        raise SystemExit('SDK generation output must be inside this project tmp/')
    sources=[
        'game/data/block/gdscript/block_definition.gd','game/data/block/gdscript/block_state_definition.gd',
        'game/data/fluid/gdscript/fluid_definition.gd','game/data/item/gdscript/item_definition.gd',
        'game/data/content/gdscript/content_manifest.gd','game/shading/blocks/gdscript/block_appearance.gd',
        'game/shading/blocks/gdscript/breaking_texture_group.gd',
        'game/data/content/gdscript/block_asset.gd','game/data/content/gdscript/item_asset.gd',
        'tools/content/project_resolver.gd',
        'game/shading/blocks/gdscript/block_surface.gd','game/shading/blocks/gdscript/block_light_appearance.gd',
        'game/shading/water/gdscript/water_appearance.gd','tools/content/compiler.gd','tools/content/cli.gd',
        'addons/astraeon_content/plugin.cfg','addons/astraeon_content/plugin.gd','addons/astraeon_content/export_guard.gd',
        'addons/zylann.voxel/voxel.gdextension','test/content/resources/example_manifest.tres',
        'native/voxel_tools/LICENSE.md','native/deps/godot-cpp/LICENSE.md',
    ]
    sources += [str(p.relative_to(ROOT)).replace('\\','/') for p in (ROOT/'test/content/resources/example').rglob('*') if p.is_file() and p.suffix not in ['.uid','.import']]
    descriptor=(ROOT/'addons/zylann.voxel/voxel.gdextension').read_text(encoding='utf-8-sig')
    binaries=re.findall(r'windows\.(?:editor|debug)\.x86_64 = "res://([^"]+)"',descriptor)
    sources += ['game/core/gdscript/project_paths.gd', 'game/data/content/gdscript/content_bundle.gd', 'game/shading/blocks/gdscript/compiled_block_builder.gd']
    for folder in ['addons/astraeon_content/gdscript', 'addons/astraeon_content/scenes', 'game/shading/shaders']:
        sources += [p.relative_to(ROOT).as_posix() for p in (ROOT/folder).rglob('*') if p.is_file() and p.suffix in ['.gd','.tscn','.gdshader','.gdshaderinc']]
    sources+=sorted(set(binaries))
    fingerprint={}
    for folder in ['tmp', 'runtime_data']:
        (destination/folder).mkdir(parents=True,exist_ok=True)
        (destination/folder/'.gdignore').write_text('',encoding='utf-8')
    for relative in sources:
        source=ROOT/relative
        target=destination/relative
        target.parent.mkdir(parents=True,exist_ok=True)
        shutil.copy2(source,target)
        fingerprint[relative]=hashlib.sha256(source.read_bytes()).hexdigest()
        if source.with_suffix(source.suffix+'.uid').exists():
            shutil.copy2(source.with_suffix(source.suffix+'.uid'),target.with_suffix(target.suffix+'.uid'))
    # This SDK authors data packs; it does not export the game executable.
    sdk_descriptor=destination/'addons/zylann.voxel/voxel.gdextension'
    sdk_descriptor.write_text(re.sub(r'^windows\.release\.x86_64.*\n?', '', descriptor, flags=re.MULTILINE),encoding='utf-8')
    fingerprint['addons/zylann.voxel/voxel.gdextension']=hashlib.sha256(sdk_descriptor.read_bytes()).hexdigest()
    (destination/'project.godot').write_text('''config_version=5
[application]
config/name="Astraeon Content SDK"
config/features=PackedStringArray("4.7", "Forward Plus")
[rendering]
renderer/rendering_method="forward_plus"
[editor_plugins]
enabled=PackedStringArray("res://addons/astraeon_content/plugin.cfg")
''',encoding='utf-8')
    (destination/'SDK_README.md').write_text('''# Astraeon content SDK
Use Godot 4.7 and the bundled matching extension. No C++ compiler is required for Mod authors.
The extension supports editor/debug authoring and pack compilation, not game release export.
Open test/content/resources/example_manifest.tres: indexes complete block assets in example/blocks/.
Each block file embeds its logic, appearance and item. Images are indexed in image_sources, relative to the manifest or absolute filesystem paths. Only compiled pixels are shipped.
Source images in example/images/ can be replaced or relocated by editing those indexes; no Godot texture import is required.
Open the 内容编辑器 main screen. Choose 方块 / 物品 / 流体, edit 材质 / 逻辑数据, save and export .aebpack. The fixed-light preview uses the same native compiler and shaders. Source pictures remain external indexes.
All source editing uses private copies with undo/redo. Close/switch prompts before discarding work; external edits require explicit overwrite or reload.
Headless: godot --headless --path . --script res://tools/content/cli.gd -- build res://test/content/resources/example_manifest.tres res://example.aebpack
Install the resulting package from the game's title-screen Content Packages menu. No executable scripts are embedded in it.
''',encoding='utf-8')
    (destination/'sdk_sources.json').write_text(json.dumps(fingerprint,indent=2),encoding='utf-8')
    print(json.dumps({'output':str(destination),'files':len(sources),'native_dlls':binaries}))
if __name__=='__main__':main()
