package helder.pdf;

import haxe.io.Bytes;
import haxe.io.BytesBuffer;
import helder.pdf.Colors;
import helder.test.Test;

// A PDF's CMYK JPEGs: their samples through the image's colour space and
// Decode array, as pdf.js and Core Graphics read them, not inverted as
// Photoshop's own JPEG files are (a magazine's cover photograph came out a
// negative). A page built here of three 8 x 8 JPEGs, each a flat block of
// full cyan: YCCK (Adobe's transform 2, as Photoshop writes it), plain
// CMYK (transform 0), and inverted samples with a Decode array of 1 0
function tests() {
	describe("PdfImage", () -> {
		#if (target.name == "hxmc" && hxmc.target != "wasm32-wasi")
		test("CMYK JPEGs: YCCK, plain CMYK, an inverting Decode: DeviceCMYK's cyan each", () -> {
			// (cyan as RGB, Y Cb Cr: the YCCK image's first three components, ink 255 - each)
			var ycck = jpeg([179, 171, 0, 0], 2), plain = jpeg([255, 0, 0, 0], 0), inverted = jpeg([0, 255, 255, 255], 0);
			var doc = Pdf.open(page([ycck, plain, inverted], [null, null, "[1 0 1 0 1 0 1 0]"]));
			var b = Pdf.render(doc, 0, 1), cyan = ColorSpace.cmyk(1, 0, 0, 0);
			function at(x:Int):String {
				var o = (4 * b.width + x) * 4;
				return StringTools.hex(b.pixels.get(o), 2) + StringTools.hex(b.pixels.get(o + 1), 2) + StringTools.hex(b.pixels.get(o + 2), 2);
			}
			var want = StringTools.hex(cyan & 0xFFFFFF, 6);
			equals([at(4), at(12), at(20)], [want, want, want]);
		});
		#end
	});
}

// (an 8 x 8 baseline JPEG of four components, each one flat block of its
// sample: its DC alone, quantized by 1, the standard Huffman tables; an
// Adobe APP14 marker with transform)
private function jpeg(samples:Array<Int>, transform:Int):Bytes {
	var o = new BytesBuffer();
	function bytes(a:Array<Int>)
		for (v in a)
			o.addByte(v);
	function segment(marker:Int, body:Array<Int>)
		bytes([0xFF, marker, (body.length + 2) >> 8, (body.length + 2) & 255].concat(body));
	var dcCounts:Array<Int> = @:privateAccess helder.image.JpegEncoder.DC_LUM_COUNTS, dcValues:Array<Int> = @:privateAccess helder.image.JpegEncoder.DC_LUM_VALUES;
	var acCounts:Array<Int> = @:privateAccess helder.image.JpegEncoder.AC_LUM_COUNTS, acValues:Array<Int> = @:privateAccess helder.image.JpegEncoder.AC_LUM_VALUES;
	bytes([0xFF, 0xD8]);
	segment(0xEE, [0x41, 0x64, 0x6F, 0x62, 0x65].concat([0, 100, 0, 0, 0, 0, transform]));
	segment(0xDB, [0].concat([for (_ in 0...64) 1]));
	segment(0xC0, [8, 0, 8, 0, 8, 4].concat([for (c in 0...4) for (v in [c + 1, 0x11, 0]) v]));
	segment(0xC4, [0x00].concat(dcCounts).concat(dcValues));
	segment(0xC4, [0x10].concat(acCounts).concat(acValues));
	segment(0xDA, [4].concat([for (c in 0...4) for (v in [c + 1, 0x00]) v]).concat([0, 63, 0]));
	// (the canonical codes of the DC table's categories; the AC table's end of block: 1010)
	var codes = new Map<Int, {code:Int, len:Int}>(), code = 0, k = 0;
	for (len in 1...17) {
		for (_ in 0...dcCounts[len - 1])
			codes.set(dcValues[k++], {code: code++, len: len});
		code <<= 1;
	}
	var acc = 0, nbits = 0;
	function put(v:Int, len:Int) {
		for (i in 0...len) {
			acc = (acc << 1) | ((v >> (len - 1 - i)) & 1);
			if (++nbits == 8) {
				o.addByte(acc);
				if (acc == 0xFF) o.addByte(0);
				acc = nbits = 0;
			}
		}
	}
	for (s in samples) {
		// (a flat block's DC coefficient: eight times its level-shifted sample)
		var d = (s - 128) * 8, mag = d < 0 ? -d : d, cat = 0;
		while (mag >> cat > 0)
			cat++;
		var c = codes.get(cat);
		put(c.code, c.len);
		if (cat > 0) put(d < 0 ? d + (1 << cat) - 1 : d, cat);
		put(0xA, 4);
	}
	if (nbits > 0) put((1 << (8 - nbits)) - 1, 8 - nbits);
	bytes([0xFF, 0xD9]);
	return o.getBytes();
}

// (a 24 x 8 point page, the images side by side, each a DeviceCMYK DCTDecode image of 8 x 8, its Decode array when given)
private function page(images:Array<Bytes>, decodes:Array<Null<String>>):Bytes {
	var o = new BytesBuffer(), offsets = [];
	function obj(n:Int, head:String, ?stream:Bytes) {
		offsets[n] = o.length;
		o.addString('$n 0 obj\n$head');
		if (stream != null) {
			o.addString('\nstream\n');
			o.addBytes(stream, 0, stream.length);
			o.addString('\nendstream');
		}
		o.addString('\nendobj\n');
	}
	o.addString("%PDF-1.4\n");
	var names = [for (i in 0...images.length) '/Im$i ${i + 4} 0 R'].join(" ");
	var content = [for (i in 0...images.length) 'q 8 0 0 8 ${i * 8} 0 cm /Im$i Do Q'].join("\n");
	obj(1, "<< /Type /Catalog /Pages 2 0 R >>");
	obj(2, "<< /Type /Pages /Kids [3 0 R] /Count 1 >>");
	obj(3, '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 ${images.length * 8} 8] /Resources << /XObject << $names >> >> /Contents ${images.length + 4} 0 R >>');
	for (i in 0...images.length) {
		var decode = decodes[i] == null ? "" : ' /Decode ${decodes[i]}';
		obj(i + 4, '<< /Type /XObject /Subtype /Image /Width 8 /Height 8 /ColorSpace /DeviceCMYK /BitsPerComponent 8$decode /Filter /DCTDecode /Length ${images[i].length} >>',
			images[i]);
	}
	obj(images.length + 4, '<< /Length ${content.length} >>', Bytes.ofString(content));
	var xref = o.length, n = images.length + 5;
	o.addString('xref\n0 $n\n0000000000 65535 f \n');
	for (i in 1...n)
		o.addString(StringTools.lpad(Std.string(offsets[i]), "0", 10) + " 00000 n \n");
	o.addString('trailer\n<< /Size $n /Root 1 0 R >>\nstartxref\n$xref\n%%EOF\n');
	return o.getBytes();
}
