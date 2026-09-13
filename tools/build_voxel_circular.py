"""Build the pinned Astraeon circular-streaming extension locally; no Godot is launched."""
import argparse
import hashlib
import io
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[1]
VOXEL = "75d3c6d996ed2331c80edcd8c3ebc947afc0f041"
CPP = "b4ce22a76b56bb5f734a5161d6105eb4b8d1021d"
WORK = ROOT / "tmp/voxel-circular-build"


def apply_patch_text(original, diff, reverse=False):
    """Apply a unified diff with exact context checks, without depending on a Git checkout."""
    lines = original.splitlines(keepends=True)
    result = []
    cursor = 0
    patch = diff.splitlines(keepends=True)
    i = 0
    while i < len(patch):
        match = re.match(r"@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@", patch[i])
        if not match:
            i += 1
            continue
        start = max(0, int(match.group(2 if reverse else 1)) - 1)
        result.extend(lines[cursor:start])
        cursor = start
        i += 1
        while i < len(patch) and not patch[i].startswith(("@@", "--- ")):
            tag, body = patch[i][:1], patch[i][1:]
            if reverse:
                tag = {"+": "-", "-": "+"}.get(tag, tag)
            if tag in (" ", "-"):
                if cursor >= len(lines) or lines[cursor] != body:
                    raise RuntimeError(f"Patch context mismatch at source line {cursor + 1}")
                cursor += 1
            if tag in (" ", "+"):
                result.append(body)
            i += 1
    result.extend(lines[cursor:])
    return "".join(result)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--install", action="store_true")
    parser.add_argument("--jobs", type=int, default=12)
    args = parser.parse_args()
    WORK.mkdir(parents=True, exist_ok=True)
    sources = {}
    for repo, commit in (("Zylann/godot_voxel", VOXEL), ("godotengine/godot-cpp", CPP)):
        name = repo.split("/")[1]
        archive = WORK / f"{name}-{commit}.zip"
        if not archive.exists():
            with urllib.request.urlopen(f"https://codeload.github.com/{repo}/zip/{commit}", timeout=120) as response:
                archive.write_bytes(response.read())
        sources[name] = hashlib.sha256(archive.read_bytes()).hexdigest()
        # Always restore the pinned source before applying the patch; generated objects remain cached.
        with zipfile.ZipFile(archive) as zipped:
            for item in zipped.infolist():
                destination = (WORK / item.filename).resolve()
                if not destination.is_relative_to(WORK.resolve()):
                    raise RuntimeError("Unsafe archive path")
            zipped.extractall(WORK)
    src = WORK / f"godot_voxel-{VOXEL}"
    patch = (ROOT / "tools/voxel_patches/horizontal_circle.patch").read_text(encoding="utf8")
    for section in re.split(r"(?m)(?=^--- a/)", patch):
        if not section.strip():
            continue
        name = section.splitlines()[0].removeprefix("--- a/")
        target = (src / name).resolve()
        if not target.is_relative_to(src.resolve()):
            raise RuntimeError("Unsafe patch path")
        target.write_text(apply_patch_text(target.read_text(encoding="utf8"), section), encoding="utf8")
    version = src / "voxel_version.py"
    version.write_text(version.read_text(encoding="utf8").replace("git_hash = get_git_commit_hash()", f'git_hash = "{VOXEL}+astraeon-circle-v1"'), encoding="utf8")
    packages = WORK / "python"
    if not (packages / "SCons").exists():
        subprocess.run([sys.executable, "-m", "pip", "install", "--target", str(packages), "scons==4.10.1"], check=True)
    env = dict(os.environ, PYTHONPATH=str(packages), GODOT_CPP_PATH=str(WORK / f"godot-cpp-{CPP}"))
    command = [sys.executable, "-m", "SCons", "platform=windows", "target=editor", "arch=x86_64", "dev_build=no", "use_static_cpp=yes", "voxel_tests=no", f"-j{args.jobs}"]
    with (WORK / "build.log").open("w", encoding="utf8") as log:
        subprocess.run(command, cwd=src, env=env, stdout=log, stderr=subprocess.STDOUT, check=True)
    binary = src / "project/addons/zylann.voxel/bin/libvoxel.windows.editor.x86_64.dll"
    manifest = dict(source=VOXEL, godot_cpp=CPP, source_archives=sources, patch_sha256=hashlib.sha256(patch.encode()).hexdigest(), binary_sha256=hashlib.sha256(binary.read_bytes()).hexdigest(), command=command)
    (WORK / "build_manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf8")
    if args.install:
        target = ROOT / "benchmarks/voxelgame/project/addons/zylann.voxel/bin" / binary.name
        target.parent.mkdir(parents=True, exist_ok=True)
        if target.exists():
            backup = WORK / (hashlib.sha256(target.read_bytes()).hexdigest() + ".dll")
            if not backup.exists():
                shutil.copy2(target, backup)
        shutil.copy2(binary, target)
    print(json.dumps(manifest, indent=2))


if __name__ == "__main__":
    main()
