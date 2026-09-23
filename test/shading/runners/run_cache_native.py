"""Build and run the independent section-light correctness tests (no Godot)."""
from pathlib import Path
import os
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[3]
packages = ROOT / 'tmp/voxel-circular-build/python'
if not (packages / 'SCons').is_dir():
    packages = ROOT / 'tmp/native-build/python'
if not (packages / 'SCons').is_dir():
    raise SystemExit('Run tools/build_native_voxel.py first to provision pinned SCons.')
subprocess.run([sys.executable, '-m', 'SCons', '-C', str(ROOT / 'test/shading/native')],
               env=dict(os.environ, PYTHONPATH=str(packages)), check=True)
subprocess.run([str(ROOT / 'tmp/cache-native-tests/section_cache_test.exe')], check=True)
