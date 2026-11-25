package lanes;

import lanes.Tools.*;

class Image {
	public static final LANES:Array<Lane> = [
		{name: "image", about: "helder.image's decoders against Chromium's and libwebp's pixels", run: image},
		{name: "image-fuzz", about: "helder.image's decoders under a time-boxed fuzzer", run: imageFuzz},
		{name: "pdf", about: "helder.pdf's pages and text against pdf.js", run: pdfLane},
		{name: "pdf-fuzz", about: "helder.pdf under a time-boxed fuzzer", run: pdfFuzz}
	];

	static function image() {
		var cp = cps(["src", "tests/image"]);
		interp(cp, "ImageCheck");
		exe("bin/image/ImageCheck", cp.concat(["-main", "ImageCheck"]));
		run(exePath("bin/image/ImageCheck", HOST), []);
		run(NODE, ["tests/image/unsafe.mjs"]);
	}

	// (FUZZ_SECONDS: the budget, 30 s by default; FUZZ_SEED: where it starts)
	static function imageFuzz() {
		exe("bin/image/Fuzz", cps(["src", "tests/image"]).concat(["-main", "Fuzz"]));
		run(exePath("bin/image/Fuzz", HOST), [Sys.getEnv("FUZZ_SECONDS") ?? "30", Sys.getEnv("FUZZ_SEED") ?? "1"]);
	}

	static function pdfLane() {
		exe("bin/pdf/PdfRender", cps(["src", "tests/pdf"]).concat(["-main", "PdfRender"]).concat(targetArgs(HOST)));
		run(exePath("bin/pdf/PdfRender", HOST), []);
		run(NODE, ["tests/pdf/check.mjs", "bin/pdf/ours", "tests/pdf/ref", "bin/pdf/report"]);
	}

	static function pdfFuzz() {
		exe("bin/pdf/Fuzz", cps(["src", "tests/pdf"]).concat(["-main", "Fuzz"]).concat(targetArgs(HOST)));
		run(exePath("bin/pdf/Fuzz", HOST), [Sys.getEnv("FUZZ_SECONDS") ?? "30", Sys.getEnv("FUZZ_SEED") ?? "1"]);
	}
}
