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

// The canvas' "something is coming": a soft sphere of light, its surface
// slowly moving, breathing (a 5 s breath), in the agent's colour (the
// part's accent), brighter while a turn runs (the part's checked amount,
// eased); one pass of one triangle into a texture the node's size, shown
// as one quad (helder.ui's part shader: PartShaderNode). Watch shows it
// while the canvas has nothing of the agent's.
class Orb {
	// a node drawing it, its colour colour(), brighter while busy()
	public static function node(colour:Void->String, busy:Void->Bool):Node {
		var eased = new Eased([0, 0, 0.8, 0, 0]);
		var look:Look<Dynamic> = Look.base.with({});
		var n = new PartShaderNode(OrbShader, eased, look);
		var holder = new Node("orb");
		holder.style.pointerEvents = None;
		holder.append(n);
		eased.node = n;
		var shown = false, last = "";
		// (each frame while it is in a window: its surface moves, its colour and brightness followed)
		Clock.addFor(n, _ -> {
			if (n.ui != null) shown = true else if (shown) return false;
			var c = colour();
			if (c != last) {
				last = c;
				var k = Color.parse(c);
				look.tokens.accent = {light: k, dark: k};
			}
			eased.set(Eased.CHECKED, busy());
			if (n.ui != null) n.ui.requestFrame();
			return true;
		});
		return holder;
	}
}

// (the sphere: lit from the top left, its surface waves slow, a rim of its
// colour, a glow around it falling off; premultiplied)
final OrbShader = shader({
	vertex: function(v:DrawVertex):DrawVaryings return drawVertex(v),
	fragment: function(i:DrawVaryings, p:{part:DrawParams}):Vec4 {
		var w = p.part.size.x;
		var h = p.part.size.y;
		var t = p.part.size.w;
		var m = min(w, h);
		var qx = (i.uv.x - 0.5) * w / m * 2;
		var qy = (i.uv.y - 0.5) * h / m * 2;
		var breath = 0.5 - 0.5 * cos(t * 1.2566);
		var busy = p.part.states.z;
		var r = length(vec2(qx, qy));
		var rr = 0.34 + 0.025 * breath + 0.015 * busy;
		var inside = 1 - smoothstep(rr - 0.015, rr, r);
		var z = sqrt(max(rr * rr - r * r, 0)) / rr;
		var n = vec3(qx / rr, qy / rr, z);
		var diffuse = max(dot(n, normalize(vec3(-0.45, -0.55, 0.7))), 0);
		var wave = sin(n.x * 5 + t * 0.7) * sin(n.y * 4 - t * 0.5) * 0.6 + sin((n.x - n.y) * 3 + t * 0.4) * 0.4;
		var rim = pow(1 - z, 2.5);
		var c = vec3(p.part.accent.x, p.part.accent.y, p.part.accent.z);
		var light = 0.3 + 0.7 * diffuse + wave * 0.12 + 0.25 * busy + 0.1 * breath;
		var spec = pow(diffuse, 12) * 0.45;
		var core = c * light + vec3(spec, spec, spec) + c * rim * 0.6;
		// (falling to nothing before the box's edge: no square around it)
		var glow = exp(-max(r - rr, 0) * 5.5) * (0.3 + 0.12 * breath + 0.22 * busy) * (1 - inside) * (1 - smoothstep(0.7, 0.98, r));
		var a = clamp(inside + glow, 0, 1);
		var rgb = core * inside + c * glow;
		return vec4(rgb.x, rgb.y, rgb.z, a);
	}
});
