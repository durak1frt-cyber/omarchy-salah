#!/usr/bin/env python3
"""Compile the Qt 6 shader bundle. qsb is a build dependency, never a runtime dependency."""
import argparse
from pathlib import Path
import shutil
import subprocess

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--qsb', default=shutil.which('qsb') or '/usr/lib/qt6/bin/qsb')
args = parser.parse_args()
shader = root / 'assets/shaders/earth.frag'
subprocess.run([args.qsb, '--glsl', '100 es,120,150', '--hlsl', '50', '--msl', '12',
                '-o', str(shader) + '.qsb', str(shader)], check=True)
print('Built', str(shader) + '.qsb')
