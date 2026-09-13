"""Restore pinned native dependency files without launching Godot."""
import argparse
import hashlib
import io
import json
from pathlib import Path
import urllib.request
import zipfile

root = Path(__file__).resolve().parents[1]
base = root / "benchmarks" / "voxelgame"
lock = json.loads((base / "dependency-lock.json").read_text(encoding="utf8"))
entry = lock["downloads"]["voxel_tools"]
parser = argparse.ArgumentParser()
parser.add_argument("--archive", type=Path, help="Use an already downloaded archive")
args = parser.parse_args()
if args.archive:
    data = args.archive.read_bytes()
else:
    with urllib.request.urlopen(entry["url"], timeout=120) as response:
        data = response.read()
if hashlib.sha256(data).hexdigest() != entry["sha256"]:
    raise RuntimeError("Voxel Tools archive checksum mismatch")
project = (base / "project").resolve()
count = 0
with zipfile.ZipFile(io.BytesIO(data)) as archive:
    for item in archive.infolist():
        if item.is_dir() or not item.filename.startswith("addons/zylann.voxel/bin/"):
            continue
        path = (project / item.filename).resolve()
        if not path.is_relative_to(project):
            raise RuntimeError("Unsafe archive path")
        path.parent.mkdir(parents=True, exist_ok=True)
        content = archive.read(item)
        if path.exists() and path.read_bytes() != content:
            raise RuntimeError(f"Refusing to replace modified binary: {path}")
        path.write_bytes(content)
        count += 1
print(f"Restored {count} pinned binaries. No engine or benchmark launched.")
