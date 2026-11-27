package helder.canvas.doc;

import haxe.io.Bytes;
import haxe.io.BytesBuffer;

// What PdfWriter can embed of an image's file as it is, read from its
// header: a JPEG's (baseline or progressive, 8 bits: its size, components,
// Adobe's inverted CMYK, its EXIF orientation), a PNG's IDAT stream (8-bit
// grey or RGB, not interlaced, no tRNS: PDF's /Predictor 15 is PNG's own
// filtering). Anything else is null: the pixels are written instead.
class PdfImages {
	public static function jpeg(b:Bytes):Null<{width:Int, height:Int, components:Int, inverted:Bool, orientation:Int}> {
		if (b.length < 4 || b.get(0) != 0xFF || b.get(1) != 0xD8) return null;
		var i = 2, adobe = false, size:Null<{width:Int, height:Int, components:Int}> = null;
		while (i + 4 <= b.length) {
			if (b.get(i) != 0xFF) return null;
			var m = b.get(i + 1);
			// (fill bytes, and markers without a length)
			if (m == 0xFF) {
				i++;
				continue;
			}
			if (m == 0xD8 || m >= 0xD0 && m <= 0xD7 || m == 0x01) {
				i += 2;
				continue;
			}
			var len = b.get(i + 2) << 8 | b.get(i + 3), at = i + 4;
			if (len < 2 || i + 2 + len > b.length) return null;
			if (m == 0xEE && len >= 14 && b.getString(at, 5) == "Adobe") adobe = true;
			if (m >= 0xC0 && m <= 0xCF && m != 0xC4 && m != 0xC8 && m != 0xCC) {
				if (len < 8 || b.get(at) != 8) return null;
				size = {height: b.get(at + 1) << 8 | b.get(at + 2), width: b.get(at + 3) << 8 | b.get(at + 4), components: b.get(at + 5)};
			}
			if (m == 0xDA) break;
			i += 2 + len;
		}
		if (size == null || size.width == 0 || size.height == 0 || size.components != 1 && size.components != 3 && size.components != 4) return null;
		return {
			width: size.width,
			height: size.height,
			components: size.components,
			inverted: adobe && size.components == 4,
			orientation: helder.image.Exif.orientation(b)
		};
	}

	public static function png(b:Bytes):Null<{width:Int, height:Int, colors:Int, data:Bytes}> {
		var signature = [137, 80, 78, 71, 13, 10, 26, 10];
		if (b.length < 33) return null;
		for (k in 0...8) if (b.get(k) != signature[k]) return null;
		var i = 8, width = 0, height = 0, colors = 0, data = new BytesBuffer();
		while (i + 12 <= b.length) {
			var len = b.get(i) << 24 | b.get(i + 1) << 16 | b.get(i + 2) << 8 | b.get(i + 3), type = b.getString(i + 4, 4);
			var at = i + 8;
			if (len < 0 || at + len + 4 > b.length) return null;
			switch type {
				case "IHDR":
					if (len < 13) return null;
					width = b.get(at) << 24 | b.get(at + 1) << 16 | b.get(at + 2) << 8 | b.get(at + 3);
					height = b.get(at + 4) << 24 | b.get(at + 5) << 16 | b.get(at + 6) << 8 | b.get(at + 7);
					var depth = b.get(at + 8), kind = b.get(at + 9), interlace = b.get(at + 12);
					if (depth != 8 || interlace != 0 || kind != 0 && kind != 2) return null;
					colors = kind == 0 ? 1 : 3;
				case "tRNS": return null;
				case "IDAT": data.addBytes(b, at, len);
				case "IEND": break;
				case _:
			}
			i = at + len + 4;
		}
		var out = data.getBytes();
		return width <= 0 || height <= 0 || colors == 0 || out.length == 0 ? null : {width: width, height: height, colors: colors, data: out};
	}

	// (where an image of an EXIF orientation's unit square goes in the oriented
	// one, y up as PDF's image space: x = ax u + bx v + cx, y = ay u + by v + cy,
	// y down from the top as the drawing is)
	public static function oriented(o:Int):Array<Float>
		return switch o {
			case 2: [-1, 0, 1, 0, -1, 1];
			case 3: [-1, 0, 1, 0, 1, 0];
			case 4: [1, 0, 0, 0, 1, 0];
			case 5: [0, -1, 1, 1, 0, 0];
			case 6: [0, 1, 0, 1, 0, 0];
			case 7: [0, 1, 0, -1, 0, 1];
			case 8: [0, -1, 1, -1, 0, 1];
			case _: [1, 0, 0, 0, -1, 1];
		};
}
