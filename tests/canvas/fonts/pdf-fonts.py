# The PDF writer's test fonts (src/helder/canvas/doc/PdfWriter.test.hx), from DejaVu Sans 2.37:
#
#   python tests/canvas/fonts/pdf-fonts.py <DejaVuSans.ttf>
#
# DejaVuSans-pdf.ttf: Latin with its combining marks and ligatures, Hebrew with its points,
# Arabic with its harakat, the layout features kept, no hinting (pyftsubset). DejaVuSans-pdf.otf
# and DejaVuSans-pdf-cid.otf: ASCII, é and the fi and fl ligatures as CFF outlines (the quadratics
# made cubic), each glyph's charstring moved into a subroutine (a local one for even glyphs, a
# global one for odd): name-keyed (GSUB, GPOS and GDEF kept) and CID-keyed (one font DICT, the
# glyphs' CIDs 1000 and up, no layout tables).
import sys
from fontTools import subset
from fontTools.fontBuilder import FontBuilder
from fontTools.pens.t2CharStringPen import T2CharStringPen
from fontTools.ttLib import TTFont
from fontTools.cffLib import FDArrayIndex, FDSelect, FontDict, PrivateDict, CharStrings
from fontTools.misc.psCharStrings import T2CharString

src, here = sys.argv[1], "tests/canvas/fonts/"
unicodes = "U+0020-007E,U+00C0-00FF,U+0300-036F,U+0591-05F4,U+0600-0652,U+FB01-FB04"
opts = subset.Options()
opts.layout_features = ["*"]
opts.hinting = False
opts.name_IDs = ["*"]
opts.notdef_outline = True
font = TTFont(src)
s = subset.Subsetter(opts)
s.populate(unicodes=subset.parse_unicodes(unicodes))
s.subset(font)
font.save(here + "DejaVuSans-pdf.ttf")


def bias(n):
    return 107 if n < 1240 else 1131 if n < 33900 else 32768


def cff(cid):
    # (a small Latin subset: what the CFF tests draw)
    tt = TTFont(src)
    sl = subset.Subsetter(opts)
    sl.populate(unicodes=subset.parse_unicodes("U+0020-007E,U+00E9,U+FB01,U+FB02"))
    sl.subset(tt)
    order = tt.getGlyphOrder()
    gs = tt.getGlyphSet()
    # (a CID-keyed font's glyphs named by their CIDs from the start: its tables by those names)
    names = {n: ("cid%05d" % (1000 + i) if i else ".notdef") if cid else n for i, n in enumerate(order)}
    fb = FontBuilder(tt["head"].unitsPerEm, isTTF=False)
    fb.setupGlyphOrder([names[n] for n in order])
    fb.setupCharacterMap({u: names[n] for u, n in tt.getBestCmap().items()})
    strings = {}
    for name in order:
        pen = T2CharStringPen(tt["hmtx"][name][0], gs)
        gs[name].draw(pen)
        strings[names[name]] = pen.getCharString()
    ps = "DejaVuSansPdf" + ("Cid" if cid else "")
    fb.setupCFF(ps, {"FullName": ps}, strings, {})
    fb.setupHorizontalMetrics({names[n]: tt["hmtx"][n] for n in order})
    fb.setupHorizontalHeader(ascent=tt["hhea"].ascent, descent=tt["hhea"].descent)
    fb.setupNameTable({"familyName": ps, "styleName": "Book"})
    fb.setupOS2(sTypoAscender=tt["OS/2"].sTypoAscender, sTypoDescender=tt["OS/2"].sTypoDescender, usWinAscent=tt["OS/2"].usWinAscent,
                usWinDescent=tt["OS/2"].usWinDescent)
    fb.setupPost()
    if not cid:
        for t in ["GSUB", "GPOS", "GDEF"]:
            fb.font[t] = tt[t]
    top = fb.font["CFF "].cff.topDictIndex[0]
    cs = top.CharStrings
    private = top.Private
    gsubrs = fb.font["CFF "].cff.GlobalSubrs
    local = []
    # (each glyph's program a subroutine's, the charstring calling it)
    for i, n in enumerate(order):
        c = cs[names[n]]
        c.decompile()
        body = c.program[:-1] + ["return"]
        if i % 2 == 0:
            local.append(body)
            call = [len(local) - 1, "callsubr"]
        else:
            gsubrs.append(T2CharString(program=body, private=private, globalSubrs=gsubrs))
            call = [len(gsubrs) - 1, "callgsubr"]
        c.program = call + ["endchar"]
    from fontTools.cffLib import SubrsIndex
    subrs = SubrsIndex()
    for b in local:
        subrs.append(T2CharString(program=b, private=private, globalSubrs=gsubrs))
    private.Subrs = subrs
    nl, ng = bias(len(local)), bias(len(gsubrs))
    for n in order:
        c = cs[names[n]]
        c.program[0] -= nl if c.program[1] == "callsubr" else ng
    if cid:
        top.ROS = ("Adobe", "Identity", 0)
        top.CIDCount = 1000 + len(order)
        fd = FontDict()
        fd.Private = private
        fds = FDArrayIndex()
        fds.append(fd)
        top.FDArray = fds
        top.FDSelect = FDSelect()
        top.FDSelect.gidArray = [0] * len(order)
        top.FDSelect.format = 3
        del top.Private
        top.rawDict.pop("Private", None)
    fb.save(here + ("DejaVuSans-pdf-cid.otf" if cid else "DejaVuSans-pdf.otf"))


cff(False)
cff(True)
