from pathlib import Path
import struct
from PIL import Image
R=Path(__file__).resolve().parents[1]
O=R/'build/test';O.mkdir(parents=True,exist_ok=True)
def p16(b,o,v):struct.pack_into('<H',b,o,v)
def p32(b,o,v):struct.pack_into('<I',b,o,v)
# Small synthetic FAT32 volume with deliberately fragmented file and root chains.
sectors={}
v=bytearray(512);p16(v,11,512);v[13]=1;p16(v,14,1);v[16]=1;p32(v,36,1);p32(v,44,2);v[510:]=b'\x55\xaa';sectors[0]=v
fat=bytearray(512)
for c,n in [(2,7),(7,0xfffffff),(3,9),(9,5),(5,0xfffffff)]:p32(fat,c*4,n)
sectors[1]=fat
directory=bytearray([0xe5]*512);sectors[2]=directory
directory2=bytearray(512);directory2[:11]=b'TEST    PCM';directory2[11]=32;p16(directory2,26,3);p32(directory2,28,1300);sectors[7]=directory2
payload=bytes((i*37+11)&255 for i in range(1300))
for k,c in enumerate([3,9,5]):sectors[c]=payload[k*512:(k+1)*512].ljust(512,b'\x00')
keys=sorted(sectors)
(O/'lbas.hex').write_text('\n'.join(f'{v:08x}' for v in keys)+'\n')
(O/'sectors.hex').write_text('\n'.join(f'{v:02x}' for k in keys for v in sectors[k])+'\n')
for p in sorted((R/'card').glob('*.BMP')):
    im=Image.open(p).convert('RGB')
    pixels=list(im.getdata()); words=[]
    for i in range(0,len(pixels),2):
        pair=[((r>>3)<<11)|((g>>2)<<5)|(b>>3) for r,g,b in pixels[i:i+2]]
        words.append(pair[0]|pair[1]<<16)
    (O/(p.stem+'.hex')).write_text('\n'.join(f'{w:08x}' for w in words)+'\n')
im=Image.open(R/'card/PIC01.BMP').convert('RGB')
raw=bytearray((R/'card/PIC01.BMP').read_bytes()); rows=[raw[54+i*1920:54+(i+1)*1920] for i in range(480)]
struct.pack_into('<i',raw,22,-480);raw[54:]=b''.join(reversed(rows));(O/'TOPDOWN.BMP').write_bytes(raw)
raw[28]=16;(O/'BAD.BMP').write_bytes(raw)
print('Generated fragmented FAT32, all BMP golden words, top-down and malformed fixtures')
