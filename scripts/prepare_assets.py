# -*- coding: utf-8 -*-
"""把素材整理成 TP 卡上的 FAT 8.3 文件（PIC00..05.BMP / AUD00..05.PCM）。

卡片由 scripts/make_cards_v4.py 从 westlake_guide_v4 卡片重排版式生成；
这里只做几何断言 + 音频拷贝 + 清单（sha256 供 deploy_card.ps1 校验）。
"""
from pathlib import Path
import hashlib
import json
import shutil
import struct

from PIL import Image

R = Path(__file__).resolve().parents[1]
PACK = next(p for p in (R.parent / 'westlake_guide_v4', R / 'westlake_guide_v4') if p.exists())
CARD = R / 'card'
OUT = R / 'card'

AUDIO = ['00_welcome', '01_duanqiao', '02_baidi', '03_sudi', '04_huagang', '05_leifengta', 'emg_typhoon']
# 第 6 页紧急播报、第 7..9 页广告，直接取素材包
EXTRA_CARDS = {6: 'emg_typhoon', 7: 'ad_tea', 8: 'ad_boat', 9: 'ad_gift'}


def to_raw(png_like, dst):
    """BMP -> 裸 RGB565（每像素 2 字节小端，行自底向上，和 FPGA 里 pack 的顺序一致）。"""
    im = Image.open(png_like).convert('RGB')
    px = im.load()
    buf = bytearray(640 * 480 * 2)
    i = 0
    for y in range(479, -1, -1):
        for x in range(640):
            r, g, b = px[x, y]
            v = ((r >> 3) << 11) | ((g >> 2) << 5) | (b >> 3)
            buf[i] = v & 0xFF
            buf[i + 1] = v >> 8
            i += 2
    dst.write_bytes(bytes(buf))
    return dst.stat().st_size


def bmp_header(p):
    raw = p.open('rb').read(54)
    return dict(magic=raw[:2], offset=struct.unpack_from('<I', raw, 10)[0],
                dib=struct.unpack_from('<I', raw, 14)[0],
                w=struct.unpack_from('<i', raw, 18)[0], h=struct.unpack_from('<i', raw, 22)[0],
                bpp=struct.unpack_from('<H', raw, 28)[0],
                comp=struct.unpack_from('<I', raw, 30)[0])


def main():
    OUT.mkdir(exist_ok=True)
    manifest = []
    for page in range(12):
        if page in EXTRA_CARDS:
            src = CARD / ('PIC%02d.BMP' % page)
            shutil.copyfile(PACK / 'card' / (EXTRA_CARDS[page] + '.bmp'), src)
        else:
            src = CARD / ('PIC%02d.BMP' % page)
        if not src.exists():
            raise SystemExit('missing %s -- run scripts/make_cards_v4.py (0..5) / scripts/gen_dev_card.py (10) first' % src)
        h = bmp_header(src)
        assert h['magic'] == b'BM' and h['offset'] == 54 and h['dib'] == 40, src
        assert (abs(h['w']), abs(h['h']), h['bpp'], h['comp']) == (640, 480, 24, 0), (src, h)
        assert src.stat().st_size == 921654, (src, src.stat().st_size)
        # 卡上只放裸 RGB565：921,654 -> 614,400 字节，启动快三分之一
        dst = CARD / ('PIC%02d.DAT' % page)
        n = to_raw(src, dst)
        assert n == 640 * 480 * 2, n
        manifest.append(dict(page=page, kind='card', source=src.name, name=dst.name,
                             bytes=n, sha256=hashlib.sha256(dst.read_bytes()).hexdigest()))

    for page, name in enumerate(AUDIO):
        src = PACK / 'audio' / (name + '.pcm')
        dst = OUT / ('AUD%02d.PCM' % page)
        shutil.copyfile(src, dst)
        assert dst.stat().st_size % 2 == 0 and dst.stat().st_size > 96000, dst
        manifest.append(dict(page=page, kind='audio', source=src.name, name=dst.name,
                             bytes=dst.stat().st_size, audio_seconds=round(dst.stat().st_size / 96000, 3),
                             sha256=hashlib.sha256(dst.read_bytes()).hexdigest()))

    # 旧的 1024x600 界面页不再使用
    for stale in sorted(OUT.glob('UI*.BMP')):
        stale.unlink()

    (R / 'reports' / 'assets.json').write_text(json.dumps(
        dict(pack='westlake_guide_v4', screen=[640, 480], strip=[442, 474],
             files=manifest), ensure_ascii=False, indent=2), encoding='utf-8')
    print('Prepared %d files; %s bytes' % (len(manifest), format(sum(x['bytes'] for x in manifest), ',')))


if __name__ == '__main__':
    main()
