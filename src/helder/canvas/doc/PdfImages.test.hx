package helder.canvas.doc;

import haxe.io.Bytes;
import helder.image.Image;
import helder.image.JpegEncoder;
import helder.image.PngEncoder;
import helder.pdf.Pdf;
import helder.test.Test;

// PdfWriter's images: one XObject however often an image is drawn; a JPEG
// (Bitmap.source) embedded byte for byte as /DCTDecode, its EXIF orientation
// the image's matrix; a PNG's IDAT as it is. Each read back by helder.pdf
// as the pixels written again would have drawn it.
function tests() {
	describe("PdfWriter's images", () -> {
		test("an image drawn three times: one XObject", () -> {
			var b = Bitmap.fromStraight(16, 12, pattern(16, 12));
			var pdf = write(b, 3).toString();
			equals(count(pdf, "/Subtype /Image"), 1);
		});
		test("a JPEG: its bytes in the PDF as they are, drawn as its pixels are", () -> {
			var jpeg = JpegEncoder.encode(pattern(24, 16), 24, 16);
			var pdf = write(decoded(jpeg), 1);
			equals(indexOf(pdf, jpeg) >= 0, true);
			equals(pdf.toString().indexOf("/DCTDecode") >= 0, true);
			assert(same(pdf, write(Bitmap.fromImage(Image.decode(jpeg)), 1)), "drawn otherwise than its pixels");
		});
		test("a JPEG's EXIF orientations: placed by the matrix", () -> {
			var jpeg = JpegEncoder.encode(pattern(24, 16), 24, 16);
			for (o in 2...9) {
				var turned = exif(jpeg, o);
				var b = decoded(turned);
				assert(same(write(b, 1), write(Bitmap.fromImage(Image.decode(turned)), 1)), 'orientation $o drawn otherwise');
			}
		});
		test("a PNG's IDAT as it is", () -> {
			var png = PngEncoder.encode(pattern(20, 10), 20, 10, true);
			var pdf = write(decoded(png), 1);
			equals(pdf.toString().indexOf("/Predictor 15") >= 0, true);
			assert(same(pdf, write(Bitmap.fromImage(Image.decode(png)), 1)), "drawn otherwise than its pixels");
		});
	});
}

// (a page of 100 by 60 with the bitmap drawn n times at twice its size: whole
// pixels, nearest sampling with no sample on an edge however it is turned)
private function write(b:Bitmap, n:Int):Bytes {
	var doc = new Document(), p = doc.newPage(100, 60);
	for (k in 0...n) p.drawImage(b, 0, 0, b.width, b.height, k * 30, 4, b.width * 2, b.height * 2, new Paint(), false);
	return PdfWriter.write(doc);
}

private function decoded(file:Bytes):Bitmap {
	var b = Bitmap.fromImage(Image.decode(file));
	b.source = file;
	return b;
}

// (both PDFs read back at 4x: no pixel apart by more than JPEG's rounding)
private function same(a:Bytes, b:Bytes):Bool {
	var x = Pdf.render(Pdf.open(a), 0, 4).straight(), y = Pdf.render(Pdf.open(b), 0, 4).straight();
	if (x.length != y.length) return false;
	for (i in 0...x.length) if (Math.abs(x.get(i) - y.get(i)) > 2) return false;
	return true;
}

// (a picture to tell its corners apart: red to the right, green down, a blue corner)
private function pattern(w:Int, h:Int):Bytes {
	var b = Bytes.alloc(w * h * 4);
	for (y in 0...h) for (x in 0...w) {
		var i = (y * w + x) * 4;
		b.set(i, Std.int(x * 255 / (w - 1)));
		b.set(i + 1, Std.int(y * 255 / (h - 1)));
		b.set(i + 2, x < w / 3 && y < h / 3 ? 255 : 0);
		b.set(i + 3, 255);
	}
	return b;
}

// (the JPEG with an APP1 of EXIF's orientation o after its SOI)
private function exif(jpeg:Bytes, o:Int):Bytes {
	var tiff = [0x4D, 0x4D, 0, 0x2A, 0, 0, 0, 8, 0, 1, 0x01, 0x12, 0, 3, 0, 0, 0, 1, 0, o, 0, 0, 0, 0, 0, 0];
	var data = [0x45, 0x78, 0x69, 0x66, 0, 0].concat(tiff), len = data.length + 2;
	var out = new haxe.io.BytesBuffer();
	out.addBytes(jpeg, 0, 2);
	for (v in [0xFF, 0xE1, len >> 8, len & 255].concat(data)) out.addByte(v);
	out.addBytes(jpeg, 2, jpeg.length - 2);
	return out.getBytes();
}

private function count(s:String, what:String):Int
	return s.split(what).length - 1;

private function indexOf(hay:Bytes, needle:Bytes):Int {
	for (i in 0...hay.length - needle.length + 1) {
		var k = 0;
		while (k < needle.length && hay.get(i + k) == needle.get(k)) k++;
		if (k == needle.length) return i;
	}
	return -1;
}
