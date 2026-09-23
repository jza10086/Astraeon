"""Build editable, pinned native sources without overwriting them."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
WORK = ROOT / "tmp/native-build"


def stage(source, destination):
    digest = hashlib.sha256()
    staged = []
    inventory = destination / ".astraeon_staged_sources.json"
    for path in sorted(source.rglob("*")):
        if not path.is_file() or any(part in {".git", "__pycache__", "bin", "gen"} for part in path.relative_to(source).parts):
            continue
        staged.append(path.relative_to(source).as_posix())
        digest.update(path.relative_to(source).as_posix().encode())
        digest.update(path.read_bytes())
        target = destination / path.relative_to(source)
        if not target.exists() or path.read_bytes() != target.read_bytes():
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, target)
    if inventory.exists():
        for old_name in set(json.loads(inventory.read_text())) - set(staged):
            old_path = (destination / old_name).resolve()
            if not old_path.is_relative_to(destination.resolve()) or not old_path.is_relative_to(WORK.resolve()):
                raise RuntimeError("Unsafe staged source path")
            if old_path.is_file():
                old_path.unlink()
    destination.mkdir(parents=True, exist_ok=True)
    inventory.write_text(json.dumps(staged), encoding="utf8")
    return digest.hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--target", choices=["editor", "template_release"], default="editor")
    parser.add_argument("--jobs", type=int, default=12)
    parser.add_argument("--install", action="store_true")
    args = parser.parse_args()
    WORK.mkdir(parents=True, exist_ok=True)
    (ROOT / "tmp/.gdignore").touch()
    source_hash = stage(ROOT / "native/voxel_tools", WORK / "voxel_tools")
    module_hashes = {}
    project_sources = []
    for native_dir in sorted((ROOT / "game").glob("*/native")):
        module = native_dir.parent.name
        module_hashes[module] = stage(native_dir, WORK / "voxel_tools/astraeon" / module)
        project_sources += ["astraeon/" + module + "/" + path.relative_to(native_dir).as_posix() for path in sorted(native_dir.rglob("*.cpp"))]
    # Test reference solvers are editor-only, never part of the release backend.
    if args.target == "editor":
        reference = ROOT / "test/shading/native/reference"
        module_hashes["test_shading_reference"] = stage(reference, WORK / "voxel_tools/astraeon_tests/shading/reference")
        project_sources += ["astraeon_tests/shading/reference/" + path.name for path in sorted(reference.glob("*.cpp"))]
    (WORK / "voxel_tools/astraeon_sources.json").write_text(json.dumps(project_sources), encoding="utf8")
    cpp_hash = stage(ROOT / "native/deps/godot-cpp", WORK / "godot-cpp")
    packages = ROOT / "tmp/voxel-circular-build/python"
    if not (packages / "SCons").exists():
        packages = WORK / "python"
        subprocess.run([sys.executable, "-m", "pip", "install", "--target", str(packages), "scons==4.10.1"], check=True)
    env = dict(os.environ, PYTHONPATH=str(packages), GODOT_CPP_PATH=str(WORK / "godot-cpp"))
    command = [sys.executable, "-m", "SCons", "platform=windows", "target=" + args.target, "arch=x86_64", "dev_build=no", "use_static_cpp=yes", "voxel_tests=no", "-j" + str(args.jobs)]
    log_path = WORK / (args.target + ".log")
    with log_path.open("w", encoding="utf8") as log:
        subprocess.run(command, cwd=WORK / "voxel_tools", env=env, stdout=log, stderr=subprocess.STDOUT, check=True)
    binary = WORK / "voxel_tools/project/addons/zylann.voxel/bin" / ("libvoxel.windows." + args.target + ".x86_64.dll")
    manifest = {"project_module_sha256": module_hashes, "source_sha256": source_hash, "godot_cpp_sha256": cpp_hash, "command": command, "sha256": hashlib.sha256(binary.read_bytes()).hexdigest(), "dependencies": json.loads((ROOT / "native/dependency_lock.json").read_text(encoding="utf-8-sig"))}
    (WORK / (args.target + "_manifest.json")).write_text(json.dumps(manifest, indent=2), encoding="utf8")
    if args.install:
        addon = ROOT / "addons/zylann.voxel"
        name = binary.stem + "." + manifest["sha256"][:12] + ".dll"
        destination = addon / "bin" / name
        destination.parent.mkdir(parents=True, exist_ok=True)
        if not destination.exists():
            shutil.copy2(binary, destination)
        descriptor = addon / "voxel.gdextension"
        text = descriptor.read_text(encoding="utf8")
        import re
        if args.target == "editor":
            text = re.sub(r'(windows\.(?:editor|debug)\.x86_64 = ")[^"]+', lambda m: m[1] + "res://addons/zylann.voxel/bin/" + name, text)
        elif args.target == "template_release":
            text = re.sub(r'(windows\.release\.x86_64 = ")[^"]+', lambda m: m[1] + "res://addons/zylann.voxel/bin/" + name, text)
        descriptor.write_text(text, encoding="utf8")
    print(json.dumps(manifest, indent=2))


if __name__ == "__main__":
    main()
