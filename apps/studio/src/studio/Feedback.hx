package studio;

import helder.gfx.Color;
import helder.ui.*;
import helder.view.*;
import helder.view.Flow.*;
import helder.view.graph.Graph.*;
import helder.view.graph.Read;
import studio.Marks;
import studio.Presence.Peer;
import studio.Theme.c;

// The agents at work, drawn on the canvas in their colours (Marks and
// Presence: the boards' motion, Motion.dc.html): the frame an agent is on
// breathes a halo; its cursor sits where it last touched; what an edit
// made flashes, then holds an outline; a frame's new image after a build
// it caused is revealed behind a scan line; an agent off the view is a tab
// on the edge nearest it (a click flies there: the user's click, the
// camera never moved for the agent); so is a frame new since the project
// opened until it was in the view ("New: Settings ›"). What an agent
// changed is a line in the chat (Chat, Undo there: the canvas takes no
// input but a pan, a zoom, a frame aimed at or played, and these tabs).
// Its chip by a frame's caption and a frame not drawn yet (its shimmer) are
// Board's, from here.
@:renderer(helder.ui.view.NodeRenderer)
class Feedback implements Markup {
	// the layer, in the stage's points (Board's overlay)
	public static function canvas(studio:Studio):View
		return <view tag="watch" position="absolute" inset={0} pointerEvents="none">
			<For each={studio.marks.reveals()} by={(r:Reveal) -> r.screen}>{(r:Read<Reveal>) -> reveal(studio, r)}</For>
			<For each={halos(studio)} by={(p:Peer) -> p.id}>{(p:Read<Peer>) ->
				<view tag={"halo-" + Shell.slug(p().name)} position="absolute" left={frame(studio, p().screen).x} top={frame(studio, p().screen).y}
					width={frame(studio, p().screen).w} height={frame(studio, p().screen).h} borderRadius={3} opacity={p().working ? 1 : 0} transition="opacity 0.3s"
					boxShadow={breath(studio, p().colour)}/>
			}</For>
			<For each={picked(studio)} by={(p:{screen:String, colour:String}) -> p.screen}>{(p:Read<{screen:String, colour:String}>) ->
				<view tag={"picked-" + Shell.slug(p().screen)} position="absolute" left={frame(studio, p().screen).x} top={frame(studio, p().screen).y}
					width={frame(studio, p().screen).w} height={frame(studio, p().screen).h} borderRadius={3} boxShadow={Shadow.parse('0 0 0 2px ${p().colour}')}/>
			}</For>
			<For each={studio.marks.touches()} by={(t:Touch) -> t.id}>{(t:Read<Touch>) ->
				<view tag="touch" position="absolute" left={touchBox(studio, t()).x} top={touchBox(studio, t()).y} width={touchBox(studio, t()).w}
					height={touchBox(studio, t()).h} borderRadius={2} boxShadow={flash(studio, t())}/>
			}</For>
			<For each={studio.marks.cursors()} by={(h:Hand) -> h.peer}>{(h:Read<Hand>) ->
				<view tag={"hand-" + Shell.slug(h().name)} position="absolute" left={sx(studio, h().x)} top={sy(studio, h().y)} alignItems="flex-start"
					opacity={h().working ? 1 : 0} transition="opacity 0.3s">
					<image src={Icons.pointer} width={16} height={16} color={Color.parse(h().colour)}/>
					<view padding="2 7" borderRadius={5} background={Color.parse(h().colour)} transform="translate(12px, 2px)">
						<text fontSize={Theme.SMALL} fontWeight={Theme.MEDIUM} color={c("on-agent")} lineClamp={1} textWrap="nowrap">{h().name}</text>
					</view>
				</view>
			}</For>
			<For each={edges(studio)} by={(e:Edge) -> e.key}>{(e:Read<Edge>) ->
				<button tag={"edge-" + Shell.slug(e().key)} focusable={false} aria-label={e().text} pointerEvents="auto" cursor="pointer"
					position="absolute" left={e().angle == 0 ? null : e().x} right={e().angle == 0 ? 8 + studio.insets().right : null} top={e().y} height={26} flexDirection="row" alignItems="center" columnGap={6} padding="0 10"
					borderRadius={13} background={c("skeleton")} borderWidth={1} borderColor={c("hair2")} onPress={() -> studio.flyTo(e().screen)}>
					<view width={6} height={6} borderRadius={3} background={Color.parse(e().colour)}/>
					<text fontSize={Theme.SMALL} color={c("ink2")} lineClamp={1} textWrap="nowrap">{e().text}</text>
					<image src={Icons.chevronRight} width={Theme.ICON_XS} height={Theme.ICON_XS} color={c("ink3")} transform={'rotate(${e().angle}deg)'}/>
				</button>
			}</For>
		</view>;

	// a frame's chip by its caption: the agent working on it (its dot breathing, its status), its done note a few seconds after
	public static function chip(studio:Studio, screen:String):View
		return <For each={on(studio, screen).slice(0, 1)} by={(p:Peer) -> p.id}>{(p:Read<Peer>) ->
			<view tag={"working-" + Shell.slug(p().name)} height={20} padding="0 8" borderRadius={10} flexDirection="row" alignItems="center" columnGap={5}
				flexShrink={1} minWidth={0} background={tint(p().colour, 0.14)}>
				<view width={6} height={6} borderRadius={3} flexShrink={0} background={Color.parse(p().colour)} opacity={p().working ? pulse(studio) : 1}/>
				<text fontSize={Theme.SMALL} lineClamp={1} textWrap="nowrap" textOverflow="ellipsis" flexShrink={1} minWidth={0} color={light(p().colour)}>{p().status == "" ? p().name : p().status}</text>
			</view>
		}</For>;

	// the header's: a chip each, its status after its name
	public static function chips(studio:Studio):View
		return <view tag="agents" flexDirection="row" alignItems="center" columnGap={4} flexShrink={1} minWidth={0}>
			<For each={studio.presence.peers()} by={(p:Peer) -> p.id}>{(p:Read<Peer>) ->
				<view tag={"agent-" + Shell.slug(p().name)} flexDirection="row" alignItems="center" columnGap={5} height={22} padding="0 7" borderRadius={11}
					background={c("well")} flexShrink={1} minWidth={0} maxWidth={200} opacity={p().working ? 1 : 0.6}>
					<view width={6} height={6} borderRadius={3} background={Color.parse(p().colour)} flexShrink={0}/>
					<text fontSize={Theme.SMALL} lineClamp={1} color={c("fg")} flexShrink={0}>{p().name}</text>
					<text fontSize={Theme.SMALL} lineClamp={1} textOverflow="ellipsis" color={c("fg3")} flexShrink={1} minWidth={0}>{p().status}</text>
				</view>
			}</For>
		</view>;

	// a frame not drawn yet (its build running): its place held by a shimmer, 1.6 s a sweep
	public static function skeleton(studio:Studio, w:Float):View
		return <view tag="skeleton" position="absolute" inset={0} overflow="hidden" background={c("skeleton")}>
			<Show when={studio.shownFailure() == null}>
				<view position="absolute" top={0} bottom={0} width={260} left={((studio.marks.time() / 1.6) % 1) * (w + 260) - 260}
					background={SHIMMER}/>
			</Show>
		</view>;

	static inline var SHIMMER = "linear-gradient(90deg, rgba(37, 37, 43, 0), #25252b, rgba(37, 37, 43, 0))";

	// (a frame rising into place: from 8 points lower, at 0.97, faded; ease out)
	public static function arrive(studio:Studio, screen:String):{opacity:Float, transform:String} {
		var a = Lambda.find(studio.marks.arrivals(), a -> a.screen == screen);
		if (a == null) return {opacity: 1, transform: "none"};
		var t = Math.max(0, Math.min(1, (studio.marks.time() - a.at) / Marks.ARRIVE));
		var e = 1 - Math.pow(1 - t, 3);
		return {opacity: e, transform: 'translate(0px, ${8 * (1 - e)}px) scale(${0.97 + 0.03 * e})'};
	}

	// (a new image revealed top to bottom behind a scan line, ~1 s)
	static function reveal(studio:Studio, r:Read<Reveal>):View
		return <view tag={"reveal-" + Shell.slug(r().screen)} position="absolute" left={frame(studio, r().screen).x} top={frame(studio, r().screen).y}
			width={frame(studio, r().screen).w} height={frame(studio, r().screen).h} overflow="hidden">
			<view position="absolute" left={0} right={0} bottom={0} height={frame(studio, r().screen).h * (1 - scan(studio, r()))} background={c("card")}/>
			<view position="absolute" left={0} right={0} height={2} top={frame(studio, r().screen).h * scan(studio, r()) - 1} background={Color.parse(r().colour)}
				boxShadow={Shadow.parse('0 0 12px 2px ${rgba(r().colour, 0.6)}')}/>
		</view>;

	// (where the scan line is, 0 to 1: ease in-out)
	static function scan(studio:Studio, r:Reveal):Float {
		var t = Math.max(0, Math.min(1, (studio.marks.time() - r.at) / Marks.REVEAL));
		return t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2;
	}

	// (the halo: a ring and a soft spread breathing 6 to 12 points, 2 s)
	static function breath(studio:Studio, colour:String):Shadow {
		var s = (1 - Math.cos(Math.PI * studio.marks.time())) / 2;
		return Shadow.parse('0 0 0 1.5px ${rgba(colour, 0.9)}, 0 0 0 ${6 + 6 * s}px ${rgba(colour, 0.12 - 0.09 * s)}');
	}

	// (a working dot's pulse: 0.35 to 1, 1.4 s)
	static function pulse(studio:Studio):Float
		return 0.35 + 0.65 * (1 - Math.cos(2 * Math.PI * studio.marks.time() / 1.4)) / 2;

	// (an edit's flash: a 2-point ring and a 10-point spread, then a 1.5-point outline until 1.5 s, faded out)
	static function flash(studio:Studio, t:Touch):Shadow {
		var a = studio.marks.time() - t.at;
		var ring = 1.5, spread = 0.0, glow = 0.0;
		if (a < 0.15) {
			ring = 1.5 + a / 0.15 * 0.5;
			spread = 10 * a / 0.15;
			glow = 0.35;
		} else if (a < 0.5) {
			var k = (a - 0.15) / 0.35;
			ring = 2 - 0.5 * k;
			spread = 10 * (1 - k);
			glow = 0.35 * (1 - k);
		}
		var alpha = a < 1.5 ? 1 : Math.max(0, 1 - (a - 1.5) / 0.3);
		return Shadow.parse('0 0 0 ${ring}px ${rgba(t.colour, alpha)}' + (spread > 0 ? ', 0 0 0 ${spread}px ${rgba(t.colour, glow)}' : ''));
	}

	// (the agents on a frame: at work, or done a few seconds ago)
	public static function on(studio:Studio, screen:String):Array<Peer> {
		var pr = studio.presence;
		return [
			for (p in pr.peers())
				if (p.screen == screen && (p.working || (p.doneAt > 0 && pr.now() - p.doneAt < Marks.DONE && studio.marks.time() >= 0))) p
		];
	}

	// (the frames picked in the chat's last questions: ringed here too)
	static function picked(studio:Studio):Array<{screen:String, colour:String}> {
		var last = studio.talk.turns().length - 1, out:Array<{screen:String, colour:String}> = [];
		for (q in studio.questions.all())
			if (q.turn < 0 || q.turn == last)
				for (o in q.options)
					if (o.screen != null && q.picked.contains(o.id) && !Lambda.exists(out, x -> x.screen == o.screen)) out.push({screen: o.screen, colour: q.colour});
		return out;
	}

	// (the agents whose frame is on the canvas)
	static function halos(studio:Studio):Array<Peer>
		return [for (p in studio.presence.peers()) if (p.screen != null && studio.layout.rect(p.screen) != null) p];

	// (an agent at work whose frame is out of the view, a frame new and not seen yet:
	// a tab on the edge nearest it, along it at the frame's place; several on
	// one edge fold into one, at the nearest of them, flying there: "3 new",
	// "Claude · Rally · 2 more")
	static function edges(studio:Studio):Array<Edge> {
		studio.camera.changed();
		studio.stageSize();
		// (the view: the stage less what the panels cover)
		var i = studio.insets(), cam = studio.camera;
		var l = i.left, t = i.top, w = studio.stageWidth - i.right, h = studio.stageHeight - i.bottom;
		var of = [for (p in studio.presence.peers()) if (p.screen != null && p.working) {key: p.id, text: '${p.name} · ${label(studio, p.screen)}', colour: p.colour, screen: p.screen, fresh: false}];
		for (n in studio.marks.fresh())
			if (!Lambda.exists(of, o -> o.screen == n)) of.push({key: "new:" + n, text: 'New: ${label(studio, n)}', colour: studio.marks.lastColour ?? "#8b8b94", screen: n, fresh: true});
		// (each edge's: the ones out of the view there, the nearest first)
		var sides = [for (_ in 0...4) []];
		for (o in of) {
			var r = studio.layout.rect(o.screen);
			if (r == null) continue;
			var x0 = cam.sx(r.x), y0 = cam.sy(r.y), x1 = cam.sx(r.x + r.w), y1 = cam.sy(r.y + r.h);
			if (x1 > l && y1 > t && x0 < w && y0 < h) continue;
			var cx = (x0 + x1) / 2, cy = (y0 + y1) / 2;
			var side = x0 >= w ? 0 : x1 <= l ? 1 : y1 <= t ? 2 : 3;
			sides[side].push({o: o, cx: cx, cy: cy, d: Math.pow(cx - (l + w) / 2, 2) + Math.pow(cy - (t + h) / 2, 2)});
		}
		var out:Array<Edge> = [];
		for (side in 0...4) {
			var all = sides[side];
			if (all.length == 0) continue;
			all.sort((a, b) -> a.d < b.d ? -1 : a.d > b.d ? 1 : 0);
			var near = all[0], agent = Lambda.find(all, a -> !a.o.fresh);
			var text = folded([for (a in all) a.o]), colour = (agent ?? near).o.colour, tw = 40 + 6.5 * text.length;
			function along(v:Float, lo:Float, hi:Float)
				return Math.max(lo + 8, Math.min(hi - 8, v));
			var key = "side" + side;
			out.push(switch side {
				case 0: {key: key, text: text, colour: colour, screen: near.o.screen, x: w - tw - 8, y: along(near.cy - 13, t, h - 26), angle: 0};
				case 1: {key: key, text: text, colour: colour, screen: near.o.screen, x: l + 8, y: along(near.cy - 13, t, h - 26), angle: 180};
				case 2: {key: key, text: text, colour: colour, screen: near.o.screen, x: along(near.cx - tw / 2, l, w - tw), y: t + 8, angle: -90};
				case _: {key: key, text: text, colour: colour, screen: near.o.screen, x: along(near.cx - tw / 2, l, w - tw), y: h - 34, angle: 90};
			});
		}
		return out;
	}

	// an edge's tab's text, its tabs folded (the nearest first)
	public static function folded(tabs:Array<{text:String, fresh:Bool}>):String {
		if (tabs.length == 1) return tabs[0].text;
		var agent = Lambda.find(tabs, t -> !t.fresh);
		return agent == null ? '${tabs.length} new' : '${agent.text} · ${tabs.length - 1} more';
	}

	static function label(studio:Studio, screen:String):String
		return studio.project?.screen(screen)?.label ?? screen;

	// (a frame's box in the stage's points)
	static function frame(studio:Studio, screen:Null<String>):{x:Float, y:Float, w:Float, h:Float} {
		var r = screen == null ? null : studio.layout.rect(screen);
		if (r == null) return {x: -1000, y: -1000, w: 0, h: 0};
		studio.camera.changed();
		var cam = studio.camera;
		return {x: cam.sx(r.x), y: cam.sy(r.y), w: r.w * cam.k, h: r.h * cam.k};
	}

	static function touchBox(studio:Studio, t:Touch):{x:Float, y:Float, w:Float, h:Float} {
		var f = frame(studio, t.screen), k = studio.camera.k;
		return {x: f.x + t.x * k, y: f.y + t.y * k, w: t.w * k, h: t.h * k};
	}

	static function sx(studio:Studio, wx:Float):Float {
		studio.camera.changed();
		return studio.camera.sx(wx);
	}

	static function sy(studio:Studio, wy:Float):Float {
		studio.camera.changed();
		return studio.camera.sy(wy);
	}

	static function rgba(hex:String, a:Float):String {
		var c = Color.parse(hex);
		return 'rgba(${c.r}, ${c.g}, ${c.b}, ${Math.round(a * 1000) / 1000})';
	}

	static function tint(hex:String, a:Float):Color
		return Color.parse(rgba(hex, a));

	// (the agent's colour lightened for text on its tint)
	static function light(hex:String):Color
		return Color.mix(Color.parse(hex), Color.parse("#ffffff"), 0.25);
}

private typedef Edge = {key:String, text:String, colour:String, screen:String, x:Float, y:Float, angle:Float};
