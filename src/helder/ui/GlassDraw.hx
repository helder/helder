package helder.ui;

import helder.gfx.Color;

// Glass drawn where it is not the system's (Glass, GlassGroup): by its
// shader where the canvas has a GPU (helder.ui.draw.GlassPass), else a
// light fill and rim over a soft shadow (a PDF, a canvas with no GPU, Eval)
class GlassDraw {
	public static function draw(canvas:Canvas, g:Glass) {
		if (g.width <= 0 || g.height <= 0) return;
		#if (target.name == "hxmc")
		var press = g.interactive && g.pressed ? 1.0 : 0.0, u = g.ui;
		if (g.pass == null) g.pass = new helder.ui.draw.GlassPass();
		var p:helder.ui.draw.GlassPass = g.pass;
		if (p.draw(canvas, [g.absX, g.absY, g.width, g.height, g.radius()], g.clear, g.tint, u != null && u.dark, 0, press, u == null ? 0 : u.pointerX,
			u == null ? 0 : u.pointerY, g.active ?? (u == null || u.active))) return;
		#end
		plain(canvas, g);
	}

	public static function group(canvas:Canvas, group:GlassGroup) {
		var glass = [for (g in group.glass()) if (g.visible() && g.width > 0 && g.height > 0) g];
		if (glass.length == 0) return;
		#if (target.name == "hxmc")
		var shapes = [], press = 0.0, u = group.ui, first = glass[0];
		for (g in glass) {
			for (v in [g.absX, g.absY, g.width, g.height, g.radius()])
				shapes.push(v);
			if (g.interactive && g.pressed) press = 1;
		}
		if (group.pass == null) group.pass = new helder.ui.draw.GlassPass();
		var p:helder.ui.draw.GlassPass = group.pass;
		if (p.draw(canvas, shapes, first.clear, first.tint, u != null && u.dark, group.spacing, press, u == null ? 0 : u.pointerX,
			u == null ? 0 : u.pointerY, first.active ?? (u == null || u.active))) return;
		#end
		for (g in glass)
			plain(canvas, g);
	}

	static function plain(canvas:Canvas, g:Glass) {
		var x = g.absX, y = g.absY, w = g.width, h = g.height, r = g.radius(), dark = g.ui != null && g.ui.dark;
		var fill:Color = g.clear ? (dark ? 0x1A000000 : 0x14FFFFFF) : (dark ? 0x59202020 : 0x73F8F8F8);
		var t = g.tint;
		if (t != null) fill = Color.mix(fill, Color.rgba(t & 0xFFFFFF, Math.max(fill.a, t.a) / 255), t.a / 255);
		canvas.shadow(x, y + 2, w, h, r, 0x1A000000, 10);
		canvas.rect(x, y, w, h, r, fill, 1, dark ? 0x33FFFFFF : 0x80FFFFFF);
	}
}
