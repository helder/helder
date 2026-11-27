# The WOFF and WOFF2 fixtures (Woff.test.hx), from fonts in the repository,
# by fontTools (its own WOFF2 encoder; opensans-latin.woff2 is Google
# Fonts', made by Google's): run from the repository's root in an
# environment with fonttools and brotli,
#
#   python3 -m venv /tmp/fonts && /tmp/fonts/bin/pip install fonttools brotli
#   /tmp/fonts/bin/python tests/text/woff/make.py
#
# fontTools writes no WOFF2 collection: pair.woff2 is two of its WOFF2 files'
# directories and streams joined, with a collection directory, compressed
# again.
import os
import struct
import tempfile
import brotli
from fontTools.ttLib import TTFont, woff2

D = 'tests/text/woff/'
INTER = 'src/helder/text/fonts/Inter.ttf'
DEJAVU = 'tests/canvas/fonts/DejaVuSans-pdf.otf'
AHEM = 'tests/flow/fixtures/Ahem.ttf'
BOLD = 'tests/text/coretext/Inter-Bold-subset.ttf'
DEJAVU_TTF = 'tests/canvas/fonts/DejaVuSans-pdf.ttf'


def save(src, out, flavor):
    f = TTFont(src)
    f.flavor = flavor
    f.save(D + out)


save(INTER, 'inter.woff', 'woff')
save(INTER, 'inter.woff2', 'woff2')
woff2.compress(INTER, D + 'inter-hmtx.woff2', transform_tables={'glyf', 'loca', 'hmtx'})
save(DEJAVU, 'dejavu-cff.woff', 'woff')
save(DEJAVU, 'dejavu-cff.woff2', 'woff2')
save(AHEM, 'ahem.woff2', 'woff2')
# (Google Fonts' file, its fontTools sfnt beside it: the reference)
f = TTFont(D + 'opensans-latin.woff2')
f.flavor = None
f.save(D + 'opensans-latin.ttf')


def base128(b, i):
    v = 0
    while True:
        c = b[i]
        i += 1
        v = v << 7 | (c & 0x7f)
        if not c & 0x80:
            return v, i


def enc128(v):
    out = [v & 0x7f]
    v >>= 7
    while v:
        out.insert(0, 0x80 | (v & 0x7f))
        v >>= 7
    return bytes(out)


def u255(v):
    return bytes([v]) if v < 253 else b'\xfd' + struct.pack('>H', v)


# (a WOFF2 file's entries, raw, and its stream decompressed)
def parts(path):
    b = open(path, 'rb').read()
    flavor, n, compressed = struct.unpack('>4xI4xH6xI', b[:24])
    i, entries = 48, []
    for _ in range(n):
        start = i
        flags = b[i]
        i += 1
        if flags & 63 == 63:
            i += 4
        tag = woff2.woff2KnownTags[flags & 63] if flags & 63 != 63 else b[start + 1:start + 5].decode()
        _, i = base128(b, i)
        transformed = (flags >> 6 == 0) if tag in ('glyf', 'loca') else flags >> 6 != 0
        if transformed:
            _, i = base128(b, i)
        entries.append(b[start:i])
    return flavor, entries, brotli.decompress(b[i:i + compressed])


fonts = []
for src in (BOLD, DEJAVU_TTF):
    t = TTFont(src)
    t.flavor = 'woff2'
    part = os.path.join(tempfile.mkdtemp(), 'part.woff2')
    t.save(part)
    fonts.append(parts(part))
directory, stream, collection, first = b'', b'', b'', 0
for flavor, entries, data in fonts:
    directory += b''.join(entries)
    stream += data
    collection += u255(len(entries)) + struct.pack('>I', flavor) + b''.join(u255(first + k) for k in range(len(entries)))
    first += len(entries)
packed = brotli.compress(stream, mode=brotli.MODE_FONT)
body = directory + struct.pack('>I', 0x00010000) + u255(len(fonts)) + collection
size = 48 + len(body) + len(packed)
header = struct.pack('>4sIIHHIIHHIIIII', b'wOF2', 0x74746366, size, first, 0, 0, len(packed), 1, 0, 0, 0, 0, 0, 0)
open(D + 'pair.woff2', 'wb').write(header + body + packed)
print('written')
