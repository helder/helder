package helder.ui.draw;

import helder.math.*;
import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;
import helder.ui.draw.UiShapes.*;

// The renderer's one shader, an instanced "uber-quad" (after Rune's,
// anomalyco/rune, MIT): a frame's quads are instances of one quad (its
// corner: the vertex buffer's four), each instance a kind of quad (mode)
// and all it needs, so that a frame is one draw. Every quad is a
// rectangle with rounded corners (each its own radius: radii) given by its
// half size and corners grown by a margin (rect, extent: its anti-aliased
// pixel, a shadow's blur), each fragment's position relative to its centre
// (local: an unturned quad's from its pixel's centre and the quad's centre,
// origin's whole part and fraction; a turned one's solved from its corners
// at its pixel's centre: never interpolated, so that a quad drawn into a
// layer's tile or a window's kept frame gives the pixels it gives in the
// frame, on GL too, which draws a texture the other way up), so that its edge is anti-aliased by the signed distance to it
// and a border drawn inside it, each side its own width (widths), the
// inner edge a rectangle with rounded corners too (mode 0); or a glyph, the
// atlas's coverage of the colour, read filtered (params.z: where a
// transform turns it) or at its texels' centres (widths.xy: the atlas's
// size), the platform's glyphs blended as it blends them (helder.text's
// GlyphBlend: Windows' contrast and gamma) (mode 1); or an image, its texels (premultiplied) times the
// colour's alpha, its corners rounded as a rectangle's, read clamped to its
// texels' centres (widths: an atlas page's part that is the image's) (mode
// 2); or a shadow, the rectangle blurred by a Gaussian (its standard
// deviation: blur), as Skia blurs CSS's box shadows, not under the box that
// casts it (the rectangle moved back by widths' x, y and shrunk by z: CSS
// clips an outer shadow to outside the border box) (mode 3); or an inset
// shadow, the rectangle's padding box darkened from outside a rectangle
// offset and shrunk by widths' x, y and z (mode 4). Its corners are given
// in clip space and the target's pixels (three of them: a parallelogram,
// the rectangle turned by a transform), as the CPU placed them. Every fragment is also clipped by a
// rectangle with rounded corners (clip, in target pixels, and its corners'
// radii), from its pixel's centre (pixel), anti-aliased over a pixel: clips
// need no scissor, nest on the CPU and never split the draw; and nothing
// outside region (a window's kept frame's rectangle drawn: Renderer.keep). Colours are
// premultiplied (Blend.Premultiplied). Corners are top left, top right,
// bottom right, bottom left; sides top, right, bottom, left. A
// rectangle's border is dashed or dotted by params.z (1, 2: BorderStyle's),
// each side's dashes or dots fitted to it from its own width (dashes()).
@:structInit @:publicFields class UiVertex {
	var corner:Vec2; // the quad's corner: 0 or 1 across and down (the vertex buffer's)
	// (the instance's, one buffer of them: Renderer's)
	var a:Vec4; // its top left corner (grown by the margin): in clip space, then in target pixels
	var b:Vec4; // its top right corner
	var c:Vec4; // its bottom left corner (the bottom right: b + c - a)
	var uv:Vec4; // the texture's coordinates at the top left and bottom right (modes 1 and 2)
	var extent:Vec4; // the rectangle's half size, then the corners' place from its centre (the half size plus the margin)
	var color:Vec4; // the fill (premultiplied)
	var border:Vec4; // the border's colour (premultiplied)
	var radii:Vec4; // the corners' radii
	var widths:Vec4; // the border's sides
	var params:Vec4; // x: mode, y: blur, z: the texture (mode 1: filtered, mode 2: its slot; mode 0: the border's style), w: a glyph's blend (1 + its contrast; its gamma's ratios: border)
	var clip:Vec4; // the clip: x0, y0, x1, y1 in target pixels
	var clipRadii:Vec4; // its corners' radii
	var origin:Vec4; // an unturned quad's centre in target pixels: its whole part, its fraction (x: -1e9 where turned)
	var region:Vec4; // what it may change, in target pixels: x0, y0, x1, y1 (a kept frame's rectangle: Renderer.keep)
}

@:structInit @:publicFields class UiVaryings {
	var pos:Vec4;
	var local:Vec2;
	var frame:Vec4;
	var half:Vec2;
	var ext:Vec2;
	var uvs:Vec4;
	var origin:Vec4;
	var color:Vec4;
	var border:Vec4;
	var radii:Vec4;
	var widths:Vec4;
	var params:Vec4;
	var pixel:Vec2;
	var clip:Vec4;
	var clipRadii:Vec4;
	var region:Vec4;
}

final UiShader = shader({
	vertex: function(v:UiVertex):UiVaryings {
		// (the bottom right corner from the others: exactly theirs where the quad is not turned)
		var c = v.corner, e = v.extent, a = v.a, b = v.b, l = v.c;
		var d = vec4(b.x + (l.x - a.x), l.y + (b.y - a.y), b.z + (l.z - a.z), l.w + (b.w - a.w));
		var q = c.x > 0.5 ? (c.y > 0.5 ? d : b) : (c.y > 0.5 ? l : a);
		return {
			pos: position(vec4(q.x, q.y, 0, 1)),
			// (a turned quad's corners in target pixels, the same at each vertex)
			local: l.zw,
			frame: vec4(a.z, a.w, b.z, b.w),
			half: e.xy,
			ext: e.zw,
			uvs: v.uv,
			origin: v.origin,
			color: v.color,
			border: v.border,
			radii: v.radii,
			widths: v.widths,
			params: v.params,
			pixel: q.zw,
			clip: v.clip,
			clipRadii: v.clipRadii,
			region: v.region
		};
	},
	fragment: function(i:UiVaryings, p:{atlas:Texture2D, image:Texture2D}):Vec4 {
		// (the textures read only by the modes that draw them, filtered: a
		// glyph at its texels' centres where not, an image clamped to its texels)
		// (from the pixel's centre, not its interpolated position, which the
		// rasterizer places a little apart in a target of another size: an
		// unturned quad's fragment the same in a layer's tile as in the frame;
		// its position from its centre's whole part first, then the fraction)
		var pixel = floor(i.pixel) + vec2(0.5, 0.5);
		var local = i.origin.x > -1e8 ? pixel - i.origin.xy - i.origin.zw : turned(pixel, i.frame.xy, i.frame.zw, i.local, i.ext);
		var uv = i.uvs.xy + (i.uvs.zw - i.uvs.xy) * ((local + i.ext) / (i.ext * 2));
		var ch = (i.clip.zw - i.clip.xy) * 0.5;
		var r = i.region;
		var clipped = clamp(0.5 - box(pixel - i.clip.xy - ch, ch, i.clipRadii), 0, 1) * (pixel.x > r.x && pixel.y > r.y && pixel.x < r.z && pixel.y < r.w ? 1.0 : 0.0);
		var mode = i.params.x;
		if (mode > 3.5) {
			// (the padding box less the blurred inner rectangle)
			var o = i.widths;
			var inner = max(i.half - vec2(o.z, o.z), vec2(0, 0));
			var ir = max(i.radii - vec4(o.z, o.z, o.z, o.z), vec4(0, 0, 0, 0));
			var q = local - o.xy;
			var lit = i.params.y > 0.01 ? blurred(q, inner, ir, i.params.y) : clamp(0.5 - box(q, inner, ir), 0, 1);
			return i.color * (1 - lit) * clamp(0.5 - box(local, i.half, i.radii), 0, 1) * clipped;
		}
		if (mode > 2.5) {
			var a = i.params.y > 0.01 ? blurred(local, i.half, i.radii, i.params.y) : clamp(0.5 - box(local, i.half, i.radii), 0, 1);
			var o = i.widths;
			var caster = max(i.half - vec2(o.z, o.z), vec2(0, 0));
			var cr = max(i.radii - vec4(o.z, o.z, o.z, o.z), vec4(0, 0, 0, 0));
			var under = o.w > 0 ? clamp(0.5 - box(local + o.xy, caster, cr), 0, 1) : 0.0;
			return i.color * a * (1 - under) * clipped;
		}
		if (mode > 1.5) {
			var st = clamp(uv, i.widths.xy, i.widths.zw);
			return sample(p.image, st) * i.color.w * clamp(0.5 - box(local, i.half, i.radii), 0, 1) * clipped;
		}
		if (mode > 0.5) {
			var size = i.widths.xy;
			var st = i.params.z > 0.5 ? uv : (floor(uv * size) + vec2(0.5, 0.5)) / size;
			var a = sample(p.atlas, st).x;
			if (i.params.w > 0.5) {
				// (the platform's blend, Shaping.GlyphBlend: its contrast, less for light text, then its gamma's correction for the colour)
				var fg = i.color.xyz / max(i.color.w, 0.0001);
				var k = (i.params.w - 1) * clamp(3 - 4 * dot(fg, vec3(0.30, 0.59, 0.11)), 0, 1);
				var f = dot(fg, vec3(0.25, 0.5, 0.25));
				var g = i.border;
				a = a * (k + 1) / (a * k + 1);
				a = a + a * (1 - a) * ((g.x * f + g.y) * a + (g.z * f + g.w));
			}
			return i.color * a * clipped;
		}
		var d = box(local, i.half, i.radii);
		var edge = clamp(0.5 - d, 0, 1);
		// (the inner edge, as CSS has it: the rectangle less each side's width,
		// each corner a quarter ellipse, its radius less the side's width across
		// and the top's or bottom's down)
		var w = i.widths, r = i.radii;
		var inHalf = max(i.half - vec2((w.w + w.y) * 0.5, (w.x + w.z) * 0.5), vec2(0, 0));
		var inP = local - vec2((w.w - w.y) * 0.5, (w.x - w.z) * 0.5);
		var rc = inP.x > 0 ? (inP.y > 0 ? r.z : r.y) : (inP.y > 0 ? r.w : r.x);
		var rad = vec2(max(rc - (inP.x > 0 ? w.y : w.w), 0), max(rc - (inP.y > 0 ? w.z : w.x), 0));
		var inBorder = w.x + w.y + w.z + w.w > 0 ? clamp(0.5 + ellipseBox(inP, inHalf, rad), 0, 1) : 0.0;
		if (i.params.z > 0.5 && inBorder > 0) inBorder = inBorder * dashes(local, i.half, w, r, i.params.z);
		return mix(i.color, i.border, inBorder) * edge * clipped;
	}
});
