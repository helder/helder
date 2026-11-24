package helder.ui;

// Glass drawn where it is not the system's (Glass, GlassGroup): a light
// fill and rim over a soft shadow, until the backdrop's shader draws it.
class GlassDraw {
	public static function draw(canvas:Canvas, g:Glass, x:Float, y:Float, w:Float, h:Float) {
		if (w <= 0 || h <= 0) return;
		var r = g.radius(), dark = g.ui != null && g.ui.dark;
		var fill:Color = g.clear ? (dark ? 0x1A000000 : 0x14FFFFFF) : (dark ? 0x59202020 : 0x73F8F8F8);
		var t = g.tint;
		if (t != null) fill = Color.mix(fill, Color.rgba(t & 0xFFFFFF, Math.max(fill.a, t.a) / 255), t.a / 255);
		if (g.interactive && g.pressed) fill = Color.mix(fill, 0x66FFFFFF, 0.3);
		canvas.shadow(x, y + 2, w, h, r, 0x1A000000, 10);
		canvas.rect(x, y, w, h, r, fill, 1, dark ? 0x33FFFFFF : 0x80FFFFFF);
	}

	public static function group(canvas:Canvas, group:GlassGroup)
		for (g in group.glass())
			if (g.visible()) draw(canvas, g, g.absX, g.absY, g.width, g.height);
}
