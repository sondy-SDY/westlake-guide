# -*- coding: utf-8 -*-
"""Generate the developer-mode settings card (PIC10.BMP) + a preview PNG.

The FPGA overlays only two things on this card (see guide_video_640.v):
  - a red bar at x 28..34 on the selected row;
  - a red 2 px box around the selected option at x = 212+60*col, y = 92+42*row.
Keep those grid constants in sync with the RTL.
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

R = Path(__file__).resolve().parents[1]
W, H = 640, 480
PAPER = (246, 243, 234)
INK = (43, 56, 54)
RED = (181, 67, 47)
MUTED = (122, 138, 130)
LINE = (206, 216, 208)

F_TITLE = ImageFont.truetype('C:/Windows/Fonts/msyh.ttc', 30)
F_SUB = ImageFont.truetype('C:/Windows/Fonts/msyh.ttc', 15)
F_LABEL = ImageFont.truetype('C:/Windows/Fonts/msyh.ttc', 20)
F_OPT = ImageFont.truetype('C:/Windows/Fonts/msyh.ttc', 18)
F_FOOT = ImageFont.truetype('C:/Windows/Fonts/msyh.ttc', 15)

ROWS = [
    ('亮度模式',    ['自动', '手动']),
    ('手动亮度',    ['35%', '50%', '75%', '90%', '100%']),
    ('对比度',      ['75%', '100%', '125%', '150%']),
    ('人体感应延迟', ['5s', '10s', '20s', '30s', '60s', '90s', '120s']),
    ('音量',        ['低', '中', '满']),
    ('广告停留',    ['8s', '12s', '20s']),
    ('轮播周期',    ['10s', '20s', '30s', '60s']),
    ('音频可视化',  ['关', '开']),
]
ACTION = '恢复默认值'
Y0, PITCH = 76, 36
X0, XPITCH = 212, 60


def render(highlight):
    img = Image.new('RGB', (W, H), PAPER)
    d = ImageDraw.Draw(img)
    d.rectangle([32, 22, 40, 56], fill=RED)
    d.text((52, 20), '开发者模式', font=F_TITLE, fill=INK)
    s = 'SW1 拨下退出'
    d.text((608 - d.textlength(s, font=F_SUB), 32), s, font=F_SUB, fill=MUTED)
    d.line([32, 64, 608, 64], fill=LINE, width=1)

    for i, (label, opts) in enumerate(ROWS):
        y = Y0 + i * PITCH
        d.text((52, y - 1), label, font=F_LABEL, fill=INK)
        for j, o in enumerate(opts):
            d.text((X0 + j * XPITCH + 4, y - 1), o, font=F_OPT, fill=INK)
    ya = Y0 + len(ROWS) * PITCH
    d.text((52, ya - 1), ACTION, font=F_LABEL, fill=INK)
    d.text((X0 + 4, ya - 1), 'K4 执行', font=F_OPT, fill=MUTED)

    d.line([32, 400, 608, 400], fill=LINE, width=1)
    d.text((40, 410), 'K2 上移    K3 下移    K4 修改    SW1 退出', font=F_FOOT, fill=MUTED)
    d.text((40, 432), '设置掉电不保存，重启回默认', font=F_FOOT, fill=MUTED)

    if highlight is not None:
        r, c = highlight
        y = Y0 + r * PITCH
        d.rectangle([28, y - 2, 34, y + 26], fill=RED)
        x = X0 + c * XPITCH
        d.rectangle([x - 4, y - 4, x + 52, y + 24], outline=RED, width=2)
    return img


clean = render(None)
clean.save(R / 'card/PIC10.BMP')
preview = render((2, 2))
preview.save(R / 'reports/dev_mode_page.png')
print(R / 'card/PIC10.BMP', clean.size, (R / 'card/PIC10.BMP').stat().st_size)
