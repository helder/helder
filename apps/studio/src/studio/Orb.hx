package studio;

import helder.gfx.Color;
import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;
import helder.ui.Clock;
import helder.ui.Node;
import helder.ui.controls.Eased;
import helder.ui.controls.Look;
import helder.ui.draw.PartShader;
import helder.ui.draw.PartShaderNode;

// The canvas' "something is coming": a living core of light on the ground,
// no frame around it. Inside, a plasma flowing (domain-warped waves) in
// hues spread around the agent's colour (the part's accent), a white-hot
// heart, a soft rim; around it a glow breathing into the dots and faint
// motes drifting in. While a turn runs (the part's checked amount, eased) a
// faster flow blends in and the glow swells; each tool call or patch of the
// agent's (activity) pulses it once (the part's pressed amount, eased in and
// out). One pass of one triangle into a texture the node's size, shown as
// one quad (helder.ui's part shader: PartShaderNode). Watch shows it while
// the canvas has nothing of the agent's.
class Orb {
	// (a pulse: how long it holds before it eases out)
	static inline var PULSE = 0.18;

	// a node drawing it, its colour colour(), quickened while busy(), pulsed when activity() changes
	public static function node(colour:Void->String, busy:Void->Bool, activity:Void->Int):Node {
		var eased = new Eased([0, 0.35, 1.2, 0, 0]);
		var look:Look<Dynamic> = Look.base.with({});
		var n = new PartShaderNode(OrbShader, eased, look);
		var holder = new Node("orb");
		holder.style.pointerEvents = None;
		holder.append(n);
		eased.node = n;
		var shown = false, last = "", seen = activity(), pulsed = -1.0;
		// (each frame while it is in a window: it flows, its colour, work and pulses followed)
		Clock.addFor(n, now -> {
			if (n.ui != null) shown = true else if (shown) return false;
			var c = colour();
			if (c != last) {
				last = c;
				var k = Color.parse(c);
				look.tokens.accent = {light: k, dark: k};
			}
			eased.set(Eased.CHECKED, busy());
			var a = activity();
			if (a != seen) {
				seen = a;
				pulsed = now;
				eased.set(Eased.PRESSED, true);
			} else if (pulsed >= 0 && now - pulsed > PULSE) {
				pulsed = -1;
				eased.set(Eased.PRESSED, false);
			}
			if (n.ui != null) n.ui.requestFrame();
			return true;
		});
		return holder;
	}
}

// (q: the box's point, the short side -1 to 1; the sphere bulges what is
// inside it; two warps of slow waves, a faster pair blended in by work;
// hues: the accent and its channels turned, by the flow; motes: cells of
// angle and radius moving inward, a dot in some; premultiplied, additive)
final OrbShader = shader({
	vertex: function(v:DrawVertex):DrawVaryings return drawVertex(v),
	fragment: function(i:DrawVaryings, p:{part:DrawParams}):Vec4 {
		var w = p.part.size.x;
		var h = p.part.size.y;
		var t = p.part.size.w;
		var m = min(w, h);
		var qx = (i.uv.x - 0.5) * w / m * 2;
		var qy = (i.uv.y - 0.5) * h / m * 2;
		var busy = p.part.states.z;
		var pulse = p.part.states.y;
		var breath = 0.5 - 0.5 * cos(t * 1.2566);
		var r = length(vec2(qx, qy));
		var rr = 0.27 + 0.012 * breath + 0.02 * pulse + 0.012 * busy;
		var z = sqrt(max(rr * rr - r * r, 0)) / rr;
		var bx = qx / rr / (0.55 + z);
		var by = qy / rr / (0.55 + z);
		var s = t * 0.16;
		var x1 = bx * 2.1 + sin(by * 2.6 + s * 1.3) * 0.8;
		var y1 = by * 2.1 + cos(bx * 2.2 - s * 1.1) * 0.8;
		var x2 = x1 + sin(y1 * 1.9 - s * 0.9) * 0.6;
		var y2 = y1 + cos(x1 * 2.1 + s * 0.7) * 0.6;
		var f1 = 0.5 + 0.5 * sin(x2 * 1.6 + cos(y2 * 1.4 + s));
		var sf = t * 0.6;
		var x3 = bx * 3.1 + sin(by * 3.3 + sf) * 0.7;
		var y3 = by * 3.1 + cos(bx * 2.9 - sf * 1.2) * 0.7;
		var f2 = 0.5 + 0.5 * sin(x3 * 1.8 + sin(y3 * 2.2 - sf));
		var f = mix(f1, f2, 0.12 + 0.4 * busy);
		var c = vec3(p.part.accent.x, p.part.accent.y, p.part.accent.z);
		var c2 = mix(c, vec3(c.z, c.x, c.y), 0.35);
		var c3 = mix(c, vec3(c.y, c.z, c.x), 0.3);
		var hue = mix(mix(c, c2, smoothstep(0.5, 1.0, f) * 0.7), c3, smoothstep(0.5, 1.0, 1 - f) * 0.6);
		var inside = 1 - smoothstep(rr - 0.035, rr + 0.006, r);
		var depth = 0.45 + 0.55 * z;
		var spark = pow(f, 6) * 0.45 * depth;
		var heart = exp(-r / rr * 2.2) * (0.45 + 0.35 * pulse + 0.15 * busy);
		var rim = smoothstep(rr * 0.7, rr, r) * (0.3 + 0.2 * breath + 0.3 * pulse);
		var white = mix(c, vec3(1, 1, 1), 0.65);
		var core = hue * (0.62 + 0.8 * f * depth + rim) + vec3(spark, spark, spark) + white * heart;
		var away = max(r - rr, 0);
		var fade = 1 - smoothstep(0.6, 0.97, r);
		var glow = (exp(-away * 3.8) * (0.22 + 0.1 * breath + 0.16 * busy + 0.3 * pulse) + exp(-away * 16) * 0.3) * (1 - inside) * fade;
		var u = atan2(qy, qx) * 1.9099;
		var v = r * 7 + t * 0.35;
		var cx = floor(u);
		var cy = floor(v);
		var a1 = fract(sin(cx * 12.99 + cy * 78.23) * 43758.5);
		var a2 = fract(sin(cx * 39.35 + cy * 11.13) * 24634.6);
		var dx = (fract(u) - 0.5 - (a1 - 0.5) * 0.6) * 0.52 * r;
		var dy = (fract(v) - 0.5 - (a2 - 0.5) * 0.6) * 0.143;
		var mote = (1 - smoothstep(0.002, 0.007, length(vec2(dx, dy)))) * step(0.6, a2) * smoothstep(rr + 0.05, rr + 0.25, r) * fade * (0.45 + 0.3 * busy);
		var rgb = core * inside + c * glow + white * mote;
		return vec4(rgb.x, rgb.y, rgb.z, clamp(inside + glow + mote, 0, 1));
	}
});
