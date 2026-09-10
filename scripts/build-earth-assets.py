#!/usr/bin/env python3
"""Rebuild bundled land textures from pinned Natural Earth data."""
import json,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
data=json.loads((ROOT/'vendor/ne_110m_land.geojson').read_text())
rings=[]
for feature in data['features']:
    geometry=feature['geometry']
    polygons=[geometry['coordinates']] if geometry['type']=='Polygon' else geometry['coordinates']
    rings.extend(polygon[0] for polygon in polygons)
paths=[]
for ring in rings:
    points=[((lon+180)/360*1024,(90-lat)/180*512) for lon,lat,*_ in ring]
    paths.append('M'+' L'.join(f'{x:.2f},{y:.2f}' for x,y in points)+' Z')
svg='<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="512"><rect width="1024" height="512" fill="black"/><path fill="white" d="'+' '.join(paths)+'"/></svg>'
(ROOT/'assets/land-mask.svg').write_text(svg)
subprocess.run(['rsvg-convert','-o',str(ROOT/'assets/land-mask.png'),str(ROOT/'assets/land-mask.svg')],check=True)
raw=subprocess.check_output(['magick',str(ROOT/'assets/land-mask.png'),'-resize','256x128!','-depth','8','gray:-'])
mask=''.join('1' if v>127 else '0' for v in raw)
(ROOT/'assets/Land.js').write_text('// Natural Earth 110m land; public domain. See vendor/sources.json.\nvar maskWidth = 256\nvar maskHeight = 128\nvar mask = "'+mask+'"\n')

print('Built land mask and fallback geography.')
