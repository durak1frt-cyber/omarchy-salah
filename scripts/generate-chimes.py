#!/usr/bin/env python3
"""Generate Salah's original, quiet two-note reminder sounds (CC0)."""
from pathlib import Path
import math
import struct
import wave

destination = Path(__file__).resolve().parents[1]/'assets'
destination.mkdir(exist_ok=True)
rate=24000
for name,notes in [('approaching',(523.25,659.25)),('arrival',(659.25,783.99))]:
    samples=[]
    for i in range(int(rate*1.7)):
        t=i/rate
        value=0.0
        for frequency,start in zip(notes,(0,0.42)):
            elapsed=t-start
            if elapsed>=0:
                envelope=min(1,elapsed/0.035)*math.exp(-elapsed*4.2)
                value+=0.18*envelope*(math.sin(2*math.pi*frequency*elapsed)+0.16*math.sin(2*math.pi*frequency*2*elapsed))
        value*=min(1,(1.7-t)/0.1)
        samples.append(struct.pack('<h',round(max(-1,min(1,value))*32767)))
    with wave.open(str(destination/(name+'.wav')),'wb') as audio:
        audio.setnchannels(1); audio.setsampwidth(2); audio.setframerate(rate)
        audio.writeframes(b''.join(samples))
