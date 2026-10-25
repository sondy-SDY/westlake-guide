# -*- coding: utf-8 -*-
"""把每页讲解稿切成字幕行。

先按标点切成"语义单元"，再把单元贪心装进 ≤16 字的行——这样每行都断在标点上，
不会出现"《白蛇 / 传》"或者"白堤 / 。春天"这种切断。

输出 reports/captions.json：{"max_chars":16,"pages":[{"page":1,"lines":[...]}]}
"""
from pathlib import Path
import json
import sys

R = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(R / 'westlake_guide_v4' / 'tools'))
import spots  # noqa: E402

MAX = 16
STOP = '，。、；：！？'

def units(text):
    out, cur = [], ''
    for ch in text:
        cur += ch
        if ch in STOP:
            out.append(cur)
            cur = ''
    if cur:
        out.append(cur)
    return out


def wrap(text):
    lines, cur = [], ''
    for u in units(text):
        if len(cur) + len(u) <= MAX:
            cur += u
            continue
        if cur:
            lines.append(cur)
            cur = ''
        while len(u) > MAX:
            lines.append(u[:MAX])
            u = u[MAX:]
        cur = u
    if cur:
        lines.append(cur)
    return lines


pages = [dict(page=sp['id'], lines=wrap(sp['script'])) for sp in spots.SPOTS]
mx = max(len(p['lines']) for p in pages)
assert mx <= 16, mx
json.dump(dict(max_chars=MAX, max_lines=mx, pages=pages),
          open(R / 'reports' / 'captions.json', 'w', encoding='utf-8'), ensure_ascii=False, indent=1)

print('pages %d  lines %d  max lines/page %d  unique chars %d'
      % (len(pages), sum(len(p['lines']) for p in pages), mx,
         len({c for p in pages for ln in p['lines'] for c in ln})))
for p in pages:
    print('  page %d: %d 行, 最长 %d 字' % (p['page'], len(p['lines']), max(len(x) for x in p['lines'])))
for ln in pages[1]['lines']:
    print('   |', ln)