package pdf;

import haxe.io.Bytes;
import helder.pdf.Pdf;
import helder.pdf.PdfError;
import helder.pdf.PdfLimits;
import helder.test.Gen;
import helder.test.Test;

// helder.pdf against the corpus mutated (Gen.mutated: its numbers made
// huge, runs cut out and repeated, the file cut short): each mutant opened,
// its first page's text read and the page drawn at a quarter, under small
// limits, ends in pixels or a PdfError; natively within 10 s a case and
// 384 MB more memory. The fuzz lane soaks it (HELDER_PROPERTY_SOAK).
function tests() {
	var seeds = new Map<String, Bytes>();
	for (f in sys.FileSystem.readDirectory("tests/pdf/corpus"))
		if (StringTools.endsWith(f, ".pdf")) seeds.set(f, sys.io.File.getBytes('tests/pdf/corpus/$f'));
	var limits = new PdfLimits();
	limits.maxDecoded = 64 << 20;
	limits.maxStream = 16 << 20;
	limits.maxOperators = 200000;
	limits.maxImagePixels = 4000000;

	test("a mutated PDF: drawn, or a PdfError", () -> property(mutated(seeds), b -> {
		try {
			var doc = Pdf.open(b, "", limits);
			if (doc.pages.length > 0) {
				Pdf.text(doc.pages[0]);
				Pdf.render(doc, 0, 0.25);
			}
		} catch (e:PdfError) {}
	}, {cases: 60, seconds: 3, limit: 10, memory: 384}));
}
