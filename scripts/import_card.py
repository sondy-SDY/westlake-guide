# -*- coding: utf-8 -*-
"""把任意分辨率的图导成 640x480 卡片（24bit BMP）。

用法：python scripts/import_card.py 源图 输出.bmp [contain|cover|stretch]
  contain: 等比缩放放进 640x480，四周用图角颜色补齐（默认，设计稿是 1024x600 时用）
  cover  : 等比放大铺满，居中裁切
  stretch: 直接拉成 640x480（比例会变）
"""
import sys
from pathlib import Path
from PIL import Image

W, H = 640, 480

def convert(src, dst, mode='contain'):
    im = Image.open(src).convert('RGB')
    if mode == 'stretch':
        out = im.resize((W, H), Image.LANCZOS)
    elif mode == 'cover':
        s = max(W / im.width, H / im.height)
        nw, nh = round(im.width * s), round(im.height * s)
        big = im.resize((nw, nh), Image.LANCZOS)
        left = (nw - W) // 2
        top = (nh - H) // 2
        out = big.crop((left, top, left + W, top + H))
    else:
        s = min(W / im.width, H / im.height)
        nw, nh = round(im.width * s), round(im.height * s)
        small = im.resize((nw, nh), Image.LANCZOS)
        bg = im.getpixel((2, 2))
        out = Image.new('RGB', (W, H), bg)
        out.paste(small, ((W - nw) // 2, (H - nh) // 2))
    out.save(dst)
    print('%s -> %s  %sx%s -> 640x480 (%s)' % (src, dst, im.width, im.height, mode))

if __name__ == '__main__':
    if len(sys.argv) < 3:
        raise SystemExit(__doc__)
    convert(sys.argv[1], sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else 'contain')
