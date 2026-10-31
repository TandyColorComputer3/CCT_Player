#!/usr/bin/env python3
"""Generate the original synthetic30 tone and its bounded IRQ test records."""
from pathlib import Path
import runpy
import struct

HERE=Path(__file__).parent

def generate():
    make=runpy.run_path(str(HERE/'make-synthetic-psg-vgm.py'))['make_vgm']
    base=make();commands=base[128:base.index(b'\x66',128)]*30+b'\x66'
    image=bytearray(base[:128])+commands
    struct.pack_into('<I',image,4,len(image)-4)
    struct.pack_into('<I',image,0x18,30*44100)
    path=Path('build/irq-synthetic30.vgm');path.write_bytes(image)
    read=runpy.run_path(str(HERE/'analyze-psg-timing.py'))['read_track']
    _,track=read(path,0)
    entries=[((w['sample']+734)//735,w['register'],w['value']) for w in track['writes']]
    entries.append(((track['samples']+734)//735,255,0))
    assert len(entries)<=256 and entries[-1][0]<32768
    Path('build/irq-events.inc').write_text('; Generated original test tones.\n'+''.join(f'        fdb {tick},${reg:02x}{value:02x}\n' for tick,reg,value in entries))

def edge_cases():
    # Original short-wait/envelope stream: 50 Hz updates and a 20-write burst.
    header=bytearray(128);header[:4]=b'Vgm ';struct.pack_into('<I',header,8,0x151)
    struct.pack_into('<I',header,0x34,0x4c);struct.pack_into('<I',header,0x74,2000000);header[0x78]=16
    commands=bytearray();events=[];sample=0
    def write(r,v):
        commands.extend((0xa0,r,v));events.append(((sample+734)//735,r,v))
    for r,v in [(7,62),(8,16),(0,200),(1,0),(11,255),(12,0)]:write(r,v)
    for i in range(100):
        commands.extend((0x61,0x72,0x03));sample+=882
        write(13,10 if i%2 else 14)
    for i in range(20):
        commands.append(0x70);sample+=1;write(13,10)
    commands.extend((0x61,0x44,0xac));sample+=44100
    write(8,0);commands.append(0x66)
    struct.pack_into('<I',header,0x18,sample);image=header+commands
    struct.pack_into('<I',image,4,len(image)-4)
    Path('build/irq-burst.vgm').write_bytes(image)
    events.append(((sample+734)//735,255,0))
    def save(name,rows):Path('build/irq-'+name+'.inc').write_text(''.join(f'        fdb {t},${r:02x}{v:02x}\n' for t,r,v in rows))
    save('burst',events);save('under',[(0,7,62),(0,8,15),(0,0,200),(0,1,0)])
    save('over',[(0,8,0)]*257)

if __name__=='__main__':
    generate();edge_cases()
