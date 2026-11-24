import helder.ui.*;

// Glass over the backgrounds Liquid Glass is compared on (GlassWindow: the
// system's, GlassTest: drawn): stripes, a gradient, text, a photo; on each
// a regular capsule with a label, clear glass with rounded corners, and a
// tinted regular circle; with group, two glass merging in a <glass-group>.
// Its text in helder's own Inter (embedded): the same glyphs on every
// machine, whatever fonts it has. 400 x 300 points.
class GlassScene {
	public static inline var W = 400;
	public static inline var H = 300;
	public static final backgrounds = ["stripes", "gradient", "text", "photo"];

	// the scene of background bg into root (glass: with its glass, labels:
	// their labels, group: a group of two); its glass, not the group's
	public static function build(root:Node, bg:String, glass = true, labels = true, group = false):Array<Glass> {
		// (added whatever the system has: an added face is found before a system's
		// Inter (fonts-inter's), its every weight (a variable one); added once)
		helder.text.SystemFonts.get().add(helder.asset.Asset.embed("helder/text/fonts/Inter.ttf"));
		root.style.set({width: W, height: H, background: 0xFFFFFFFF, fontFamily: "Inter"});
		var back = new Node();
		back.style.set({position: Absolute, left: 0, top: 0, width: W, height: H, overflow: Hidden});
		switch bg {
			case "stripes":
				back.style.direction = Row;
				for (i in 0...25) {
					var s = new Node();
					s.style.set({width: 16, height: H, background: [0xFF111111, 0xFFFFFFFF, 0xFFE8463A, 0xFFFFFFFF, 0xFF2F7FE8][i % 5]});
					back.append(s);
				}
			case "gradient":
				back.style.backgroundImage = Gradient.parse("linear-gradient(135deg, #ff5e62 0%, #ffb347 35%, #5ee7a0 65%, #3b6cf6 100%)");
			case "text":
				back.style.set({padding: 8, rowGap: 2});
				for (i in 0...14) {
					var t = new TextNode("Liquid Glass lenses what is behind it: line " + (i + 1));
					t.style.set({fontSize: 14, color: i % 3 == 0 ? 0xFF1F5FCF : 0xFF111111});
					back.append(t);
				}
			case _:
				var img = new ImageNode(helder.image.Image.decode(sys.io.File.getBytes("tests/ui/glass-photo.jpg")));
				img.fit = Cover;
				img.style.set({width: W, height: H});
				back.append(img);
		}
		root.append(back);
		if (!glass) return [];
		var capsule = new Glass();
		capsule.style.set({position: Absolute, left: 100, top: 40, width: 200, height: 56, alignItems: Align.Center, justify: Justify.Center});
		var label = new TextNode("Glass");
		label.style.set({fontSize: 18, fontWeight: 600, color: 0xFF111111});
		if (labels) capsule.append(label);
		var clear = new Glass();
		clear.variant = "clear";
		clear.style.set({position: Absolute, left: 40, top: 140, width: 140, height: 120, radius: 24});
		var tinted = new Glass();
		tinted.tint = Color.rgba(0x2F7FE8, 0.5);
		tinted.style.set({position: Absolute, left: 250, top: 160, width: 80, height: 80});
		for (g in [capsule, clear, tinted])
			root.append(g);
		if (group) {
			var gg = new GlassGroup();
			gg.spacing = 12;
			gg.style.set({position: Absolute, left: 210, top: 252, direction: Row, columnGap: 6});
			for (_ in 0...2) {
				var c = new Glass();
				c.style.set({width: 36, height: 36});
				gg.append(c);
			}
			root.append(gg);
		}
		return [capsule, clear, tinted];
	}

	// the glass as the reference tool takes it (tests/ui/glass-reference.swift): x,y,w,h,radius,style,tint
	public static function spec(g:Glass):String {
		var t = g.tint;
		return [g.absX, g.absY, g.width, g.height, g.radius(), g.clear ? 1 : 0].join(",") + ","
			+ (t == null ? "-" : "#" + StringTools.hex(t & 0xFFFFFF, 6) + StringTools.hex(t.a, 2));
	}

	// a glass's box in pixels at scale k: x0, y0, x1, y1
	public static function box(g:Node, k:Float):Array<Int>
		return [g.absX, g.absY, g.absX + g.width, g.absY + g.height].map(v -> Math.round(v * k));
}
