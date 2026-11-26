The canvas lane's fonts, the same files for helder and Chromium (pyftsubset, no hinting):

- `DejaVuSans-canvas.ttf`, `DejaVuSans-Bold-canvas.ttf`: DejaVu Sans 2.37 (Bitstream Vera's
  license, the DejaVu changes in the public domain: https://dejavu-fonts.github.io/License.html),
  subset to Latin, Greek, Cyrillic, Hebrew and Arabic (the bold to ASCII), their layout features kept.
- `DejaVuSans-pdf.ttf`, `DejaVuSans-pdf.otf`, `DejaVuSans-pdf-cid.otf`: DejaVu Sans 2.37 again, for
  the PDF writer's tests (src/helder/canvas/doc/PdfWriter.test.hx, tests/pdf/WriteCheck.hx), made by
  `python tests/canvas/fonts/pdf-fonts.py <DejaVuSans.ttf>`: Latin with its combining marks and
  ligatures, Hebrew with its points and Arabic with its harakat (TrueType, layout features kept), and
  ASCII as CFF, its charstrings in subroutines, name-keyed and CID-keyed.
- `IPAGothic-canvas.ttf`: IPAGothic 003.03 (the IPA Font License Agreement v1.0), subset to the
  Japanese of the text-scripts scene.
