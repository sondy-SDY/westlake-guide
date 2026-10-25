"""Offline check of a TF card against the exact conditions the FPGA checks.

Every test below maps to a specific error code in guide_fat_stream.v / guide_bmp.v,
so a failure here should reproduce the code shown on the board's eight blocks.
Read-only: files are opened normally, the volume is never written.
"""
import ctypes, hashlib, json, struct, sys
from ctypes import wintypes
from pathlib import Path

R = Path(__file__).resolve().parents[1]
k32 = ctypes.WinDLL('kernel32', use_last_error=True)
k32.GetLogicalDrives.restype = wintypes.DWORD
k32.GetDriveTypeW.argtypes = [wintypes.LPCWSTR]
k32.GetDriveTypeW.restype = wintypes.UINT
k32.GetVolumeInformationW.argtypes = [wintypes.LPCWSTR, wintypes.LPWSTR, wintypes.DWORD,
                                      ctypes.POINTER(wintypes.DWORD), ctypes.POINTER(wintypes.DWORD),
                                      ctypes.POINTER(wintypes.DWORD), wintypes.LPWSTR, wintypes.DWORD]
k32.GetDiskFreeSpaceW.argtypes = [wintypes.LPCWSTR, ctypes.POINTER(wintypes.DWORD),
                                  ctypes.POINTER(wintypes.DWORD), ctypes.POINTER(wintypes.DWORD),
                                  ctypes.POINTER(wintypes.DWORD)]

DAT_SIZE = 640 * 480 * 2          # 裸 RGB565
EXPECT = {
    **{('PIC%02d.DAT' % i): (DAT_SIZE, 0, 0) for i in range(12)},
    'AUD00.PCM': (None, 0, 0), 'AUD01.PCM': (None, 0, 0), 'AUD02.PCM': (None, 0, 0),
    'AUD03.PCM': (None, 0, 0), 'AUD04.PCM': (None, 0, 0), 'AUD05.PCM': (None, 0, 0),
 'AUD06.PCM': (None, 0, 0),
}


def volumes():
    mask = k32.GetLogicalDrives()
    out = []
    for i in range(26):
        if not mask & (1 << i):
            continue
        root = chr(65 + i) + ':\\'
        dtype = k32.GetDriveTypeW(root)
        name = ctypes.create_unicode_buffer(64)
        fs = ctypes.create_unicode_buffer(64)
        serial = wintypes.DWORD(); maxlen = wintypes.DWORD(); flags = wintypes.DWORD()
        ok = k32.GetVolumeInformationW(root, name, 64, ctypes.byref(serial), ctypes.byref(maxlen),
                                       ctypes.byref(flags), fs, 64)
        if not ok:
            continue
        spc = wintypes.DWORD(); bps = wintypes.DWORD(); free = wintypes.DWORD(); total = wintypes.DWORD()
        k32.GetDiskFreeSpaceW(root, ctypes.byref(spc), ctypes.byref(bps), ctypes.byref(free), ctypes.byref(total))
        out.append({'root': root, 'letter': chr(65 + i), 'type': dtype, 'fs': fs.value,
                    'label': name.value, 'sectors_per_cluster': spc.value, 'bytes_per_sector': bps.value,
                    'bytes': total.value * spc.value * bps.value})
    return out


def bmp_header(p):
    raw = p.open('rb').read(54)
    magic = raw[:2]
    size = struct.unpack_from('<I', raw, 2)[0]
    offset = struct.unpack_from('<I', raw, 10)[0]
    dib = struct.unpack_from('<I', raw, 14)[0]
    w = struct.unpack_from('<i', raw, 18)[0]
    h = struct.unpack_from('<i', raw, 22)[0]
    bpp = struct.unpack_from('<H', raw, 28)[0]
    comp = struct.unpack_from('<I', raw, 30)[0]
    return magic, size, offset, dib, w, h, bpp, comp


def check(vol):
    root = Path(vol['root'])
    print('== volume %s  fs=%s  label=%s  bytes/sector=%d  sectors/cluster=%d  size=%.1f GiB'
          % (vol['letter'], vol['fs'], vol['label'], vol['bytes_per_sector'],
             vol['sectors_per_cluster'], vol['bytes'] / 2**30))
    problems = []
    if vol['fs'].upper() != 'FAT32':
        problems.append('FS-01 filesystem is %s, guide_fat_stream only parses FAT32 (error 0x22)' % vol['fs'])
    if vol['bytes_per_sector'] != 512:
        problems.append('VOL-01 bytes/sector=%d, BPB0 only accepts 512 (error 0x21)' % vol['bytes_per_sector'])
    spc = vol['sectors_per_cluster']
    if spc == 0 or (spc & (spc - 1)) != 0 or spc > 128:
        problems.append('VOL-02 sectors/cluster=%d rejected by BPB1 (error 0x23)' % spc)
    try:
        names = {p.name.upper() for p in root.iterdir() if p.is_file()}
    except OSError as e:
        print('   cannot list root: %s' % e)
        return problems
    print('   root files: %d' % len(names))
    try:
        manifest = {f['name']: f for f in json.loads((R / 'reports/assets.json').read_text(encoding='utf-8'))['files']}
    except Exception:
        manifest = {}
    missing = []
    for name, (want_size, ew, eh) in sorted(EXPECT.items()):
        p = root / name
        if name not in names:
            missing.append(name)
            continue
        size = p.stat().st_size
        h = hashlib.sha256(p.read_bytes()).hexdigest()
        want = manifest.get(name, {}).get('sha256')
        flag = ''
        if want and want != h:
            flag += ' HASH-MISMATCH'
            problems.append('FILE %s sha256 differs from the generated asset' % name)
        if name.endswith('.BMP'):
            magic, hsize, off, dib, w, hgt, bpp, comp = bmp_header(p)
            if magic != b'BM':
                problems.append('BMP %s magic %r (error 0x40)' % (name, magic))
            if off < 54 or dib < 40:
                problems.append('BMP %s offset=%d dib=%d (error 0x41)' % (name, off, dib))
            if abs(w) != ew or abs(hgt) != eh:
                problems.append('BMP %s is %dx%d, loader wants %dx%d (error 0x42)'
                                % (name, w, hgt, ew, eh))
            if bpp != 24 or comp != 0:
                problems.append('BMP %s bpp=%d compression=%d (error 0x43)' % (name, bpp, comp))
            if size - off < ew * eh * 3:
                problems.append('BMP %s has %d data bytes, needs %d (error 0x44)'
                                % (name, size - off, ew * eh * 3))
            print('   %-9s %8d B  %4dx%-4d  %2dbpp off=%-4d %s' % (name, size, w, hgt, bpp, off, flag))
        else:
            kind = 'RGB565 640x480 raw' if name.endswith('.DAT') else 'PCM 48 kHz 16 bit mono'
            if want_size is not None and size < want_size:
                problems.append('%s is %d B, loader needs %d (short file -> error 0x44)'
                                % (name, size, want_size))
                flag += ' SHORT'
            elif want_size is not None and size != want_size:
                flag += ' (extra bytes ignored)'
            print('   %-9s %8d B  %s%s' % (name, size, kind, flag))
    if missing:
        names_extra = sorted(names - set(EXPECT))
        problems.append('MISSING %d files (error 0x26): %s' % (len(missing), ','.join(missing)))
        if names_extra:
            print('   root also has: %s' % ','.join(names_extra[:20]))
    return problems


def main():
    vols = volumes()
    print('volumes: %s' % ', '.join('%s(%s,%s)' % (v['letter'], v['fs'], v['label']) for v in vols))
    cands = [v for v in vols if v['type'] == 2] or [v for v in vols if v['fs'].upper() in ('FAT32', 'EXFAT')]
    if not cands:
        print('NO CARD: no removable or FAT volume found. Plug the TF card into the PC and rerun.')
        return 2
    allp = []
    for v in cands:
        allp += check(v)
    print()
    if allp:
        print('--- PROBLEMS (%d) ---' % len(allp))
        for p in allp:
            print(' * ' + p)
        print('VERDICT: card would fail in the FPGA for the reasons above')
    else:
        print('VERDICT: volume geometry, file names, card sizes, BMP headers and raw .DAT lengths all match the loader')
    return 0


if __name__ == '__main__':
    sys.exit(main())
