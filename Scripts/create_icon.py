#!/usr/bin/env python3
"""Original geometric Tempo icon, drawn from paths without stock assets."""
from pathlib import Path
import json, math, struct, zlib
root=Path(__file__).resolve().parents[1]/'Tempo/Resources/Assets.xcassets'
icon=root/'AppIcon.appiconset';icon.mkdir(parents=True,exist_ok=True)
size=1024
points=[(220,540),(355,540),(420,395),(505,655),(585,315),(660,540),(810,540)]
def distance(x,y,a,b):
    dx=b[0]-a[0];dy=b[1]-a[1];t=max(0,min(1,((x-a[0])*dx+(y-a[1])*dy)/(dx*dx+dy*dy)))
    return math.hypot(x-a[0]-t*dx,y-a[1]-t*dy)
raw=bytearray()
for y in range(size):
    raw.append(0)
    for x in range(size):
        alpha=max(0,min(1,21-min(distance(x,y,a,b) for a,b in zip(points,points[1:]))))
        bg=(16+int(y/128),30+int(y/100),39+int(y/90))
        line=(96,223,203)
        raw.extend(int(bg[i]*(1-alpha)+line[i]*alpha) for i in range(3))
def chunk(t,b):return struct.pack('>I',len(b))+t+b+struct.pack('>I',zlib.crc32(t+b)&0xffffffff)
png=b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',size,size,8,2,0,0,0))+chunk(b'IDAT',zlib.compress(raw))+chunk(b'IEND',b'')
(icon/'Tempo.png').write_bytes(png)
(root/'Contents.json').write_text(json.dumps({'info':{'author':'xcode','version':1}},indent=2))
(icon/'Contents.json').write_text(json.dumps({'images':[{'filename':'Tempo.png','idiom':'universal','platform':'ios','size':'1024x1024'}],'info':{'author':'xcode','version':1}},indent=2))
