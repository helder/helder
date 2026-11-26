package lanes;

import lanes.Tools.*;

class Image {
	public static final LANES:Array<Lane> = [
		{name: "image", about: "helder.image's decoders against Chromium's and libwebp's pixels", run: image},
		{name: "pdf", about: "helder.pdf's pages and text against pdf.js", run: pdfLane}
	];

	static function image() {
		var cp = cps(["src", "tests/image"]);
		interp(cp, "ImageCheck");
		exe("bin/image/ImageCheck", cp.concat(["-main", "ImageCheck"]));
		run(exePath("bin/image/ImageCheck", HOST), []);
		run(NODE, ["tests/image/unsafe.mjs"]);
	}

	static function pdfLane() {
		exe("bin/pdf/PdfRender", cps(["src", "tests/pdf"]).concat(["-main", "PdfRender"]).concat(targetArgs(HOST)));
		run(exePath("bin/pdf/PdfRender", HOST), []);
		run(NODE, ["tests/pdf/check.mjs", "bin/pdf/ours", "tests/pdf/ref", "bin/pdf/report"]);
		// (helder.canvas's PdfWriter: its files read back by helder.pdf, then by pdf.js and qpdf where they are)
		exe("bin/pdf/WriteCheck", cps(["src", "tests/pdf"]).concat(["-main", "WriteCheck"]).concat(targetArgs(HOST)));
		run(exePath("bin/pdf/WriteCheck", HOST), []);
		run(NODE, ["tests/pdf/written.mjs", "bin/pdf/written"]);
	}
}
