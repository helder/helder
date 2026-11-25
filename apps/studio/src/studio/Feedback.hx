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
// camera never moved for the agent); the toast says what changed, Undo
// beside it. Its chip by a frame's caption and a frame not drawn yet (its
// shimmer) are Board's, from here. Nothing else on the canvas takes input.
class Feedback implements Markup {
	// the layer, in the stage's points (Board's overlay)
	public static function canvas(studio:Studio):View
		return <view tag="watch" position="absolute" inset={0} pointer-events="none">
			<For each={studio.marks.reveals()} by={(r:Reveal) -> r.screen}>{(r:Read<Reveal>) -> reveal(studio, r)}</For>
			<For each={halos(studio)} by={(p:Peer) -> p.id}>{(p:Read<Peer>) ->
				<view tag={"halo-" + Shell.slug(p().name)} position="absolute" left={frame(studio, p().screen).x} top={frame(studio, p().screen).y}
					width={frame(studio, p().screen).w} height={frame(studio, p().screen).h} radius={3} opacity={p().working ? 1 : 0} transition="opacity 0.3s"
					shadow={breath(studio, p().colour)}/>
			}</For>
			<For each={studio.marks.touches()} by={(t:Touch) -> t.id}>{(t:Read<Touch>) ->
				<view tag="touch" position="absolute" left={touchBox(studio, t()).x} top={touchBox(studio, t()).y} width={touchBox(studio, t()).w}
					height={touchBox(studio, t()).h} radius={2} shadow={flash(studio, t())}/>
			}</For>
			<For each={studio.marks.cursors()} by={(h:Hand) -> h.peer}>{(h:Read<Hand>) ->
				<view tag={"hand-" + Shell.slug(h().name)} position="absolute" left={sx(studio, h().x)} top={sy(studio, h().y)} align-items="flex-start"
					opacity={h().working ? 1 : 0} transition="opacity 0.3s">
					<image src={Icons.pointer} width={16} height={16} color={Color.parse(h().colour)}/>
					<view padding="2 7" radius={5} background={Color.parse(h().colour)} transform="translate(12px, 2px)">
						<text font-size={Theme.SMALL} font-weight={Theme.MEDIUM} color={c("on-agent")} max-lines={1} text-wrap="nowrap">{h().name}</text>
					</view>
				</view>
			}</For>
			<For each={edges(studio)} by={(e:Edge) -> e.peer}>{(e:Read<Edge>) ->
				<view:button tag={"edge-" + Shell.slug(e().name)} role="button" label={'${e().name} · ${e().label}'} pointer-events="auto" cursor="pointer"
					position="absolute" left={e().angle == 0 ? null : e().x} right={e().angle == 0 ? 8 + studio.insets().right : null} top={e().y} height={26} direction="row" align-items="center" column-gap={6} padding="0 10"
					radius={13} background={c("skeleton")} border-width={1} border-color={c("hair2")} onPress={() -> studio.flyTo(e().screen)}>
					<view width={6} height={6} radius={3} background={Color.parse(e().colour)}/>
					<text font-size={Theme.SMALL} color={c("ink2")} max-lines={1} text-wrap="nowrap">{'${e().name} · ${e().label}'}</text>
					<image src={Icons.chevronRight} width={Theme.ICON_XS} height={Theme.ICON_XS} color={c("ink3")} transform={'rotate(${e().angle}deg)'}/>
				</view:button>
			}</For>
			<Show when={studio.marks.toast() != null}>{toast(studio)}</Show>
		</view>;

	// a frame's chip by its caption: the agent working on it (its dot breathing, its status), its done note a few seconds after
	public static function chip(studio:Studio, screen:String):View
		return <For each={on(studio, screen)} by={(p:Peer) -> p.id}>{(p:Read<Peer>) ->
			<view tag={"working-" + Shell.slug(p().name)} height={20} padding="0 8" radius={10} direction="row" align-items="center" column-gap={5}
				shrink={1} min-width={0} background={tint(p().colour, 0.14)}>
				<view width={6} height={6} radius={3} shrink={0} background={Color.parse(p().colour)} opacity={p().working ? pulse(studio) : 1}/>
				<text font-size={Theme.SMALL} max-lines={1} text-wrap="nowrap" text-overflow="ellipsis" shrink={1} min-width={0} color={light(p().colour)}>{p().status == "" ? p().name : p().status}</text>
			</view>
		}</For>;

	// the header's: a chip each, its status after its name
	public static function chips(studio:Studio):View
		return <view tag="agents" direction="row" align-items="center" column-gap={4} shrink={1} min-width={0}>
			<For each={studio.presence.peers()} by={(p:Peer) -> p.id}>{(p:Read<Peer>) ->
				<view tag={"agent-" + Shell.slug(p().name)} direction="row" align-items="center" column-gap={5} height={22} padding="0 7" radius={11}
					background={c("well")} shrink={1} min-width={0} max-width={200} opacity={p().working ? 1 : 0.6}>
					<view width={6} height={6} radius={3} background={Color.parse(p().colour)} shrink={0}/>
					<text font-size={Theme.SMALL} max-lines={1} color={c("fg")} shrink={0}>{p().name}</text>
					<text font-size={Theme.SMALL} max-lines={1} text-overflow="ellipsis" color={c("fg3")} shrink={1} min-width={0}>{p().status}</text>
				</view>
			}</For>
		</view>;

	// a frame not drawn yet (its build running): its place held by a shimmer, 1.6 s a sweep
	public static function skeleton(studio:Studio, w:Float):View
		return <view tag="skeleton" position="absolute" inset={0} overflow="hidden" background={c("skeleton")}>
			<view position="absolute" top={0} bottom={0} width={260} left={((studio.marks.time() / 1.6) % 1) * (w + 260) - 260}
				background={SHIMMER}/>
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

	// (the toast: what changed, by whom; Undo while that edit is still the one undo takes)
	static function toast(studio:Studio):View {
		var t = () -> studio.marks.toast();
		return <view tag="toast" position="absolute" top={studio.insets().top + 12} left={studio.insets().left} right={studio.insets().right} align-items="center">
			<view pointer-events="auto" direction="row" align-items="center" column-gap={8} height={32} padding="0 6 0 12" radius={8} background={c("card")}
				border-width={1} border-color={c("hair2")} shadow={Theme.POPOVER}>
				<view width={6} height={6} radius={3} background={Color.parse(t()?.colour ?? "#ffffff")}/>
				<text font-size={Theme.BODY} color={c("ink2")} max-lines={1} text-wrap="nowrap">{'${t()?.by} changed ${t()?.file}'}</text>
				<Show when={t()?.entry != null && studio.docs.nextUndo() == t().entry}>
					<view:button tag="toast-undo" role="button" label="Undo" cursor="pointer" height={22} padding="0 8" radius={6} justify="center"
						background={c("hair")} onPress={() -> {
							studio.undo();
							studio.marks.toast(null);
						}}>
						<text font-size={Theme.SMALL} color={c("ink")}>Undo</text>
					</view:button>
				</Show>
			</view>
		</view>;
	}

	// (a new image revealed top to bottom behind a scan line, ~1 s)
	static function reveal(studio:Studio, r:Read<Reveal>):View
		return <view tag={"reveal-" + Shell.slug(r().screen)} position="absolute" left={frame(studio, r().screen).x} top={frame(studio, r().screen).y}
			width={frame(studio, r().screen).w} height={frame(studio, r().screen).h} overflow="hidden">
			<view position="absolute" left={0} right={0} bottom={0} height={frame(studio, r().screen).h * (1 - scan(studio, r()))} background={c("card")}/>
			<view position="absolute" left={0} right={0} height={2} top={frame(studio, r().screen).h * scan(studio, r()) - 1} background={Color.parse(r().colour)}
				shadow={Shadow.parse('0 0 12px 2px ${rgba(r().colour, 0.6)}')}/>
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
	static function on(studio:Studio, screen:String):Array<Peer> {
		var pr = studio.presence;
		return [
			for (p in pr.peers())
				if (p.screen == screen && (p.working || (p.doneAt > 0 && pr.now() - p.doneAt < Marks.DONE && studio.marks.time() >= 0))) p
		];
	}

	// (the agents whose frame is on the canvas)
	static function halos(studio:Studio):Array<Peer>
		return [for (p in studio.presence.peers()) if (p.screen != null && studio.layout.rect(p.screen) != null) p];

	// (an agent whose frame is out of the view: a tab on the edge nearest it, along it at the frame's place)
	static function edges(studio:Studio):Array<Edge> {
		studio.camera.changed();
		studio.stageSize();
		// (the view: the stage less what the panels cover)
		var i = studio.insets(), cam = studio.camera, out:Array<Edge> = [];
		var l = i.left, t = i.top, w = studio.stageWidth - i.right, h = studio.stageHeight - i.bottom;
		for (p in studio.presence.peers()) {
			var r = p.screen == null ? null : studio.layout.rect(p.screen);
			if (r == null) continue;
			var x0 = cam.sx(r.x), y0 = cam.sy(r.y), x1 = cam.sx(r.x + r.w), y1 = cam.sy(r.y + r.h);
			if (x1 > l && y1 > t && x0 < w && y0 < h) continue;
			var cx = (x0 + x1) / 2, cy = (y0 + y1) / 2, tw = 40 + 6.5 * (p.name.length + label(studio, p.screen).length);
			function along(v:Float, lo:Float, hi:Float)
				return Math.max(lo + 8, Math.min(hi - 8, v));
			var e:Edge = if (x0 >= w) {peer: p.id, name: p.name, colour: p.colour, screen: p.screen, label: label(studio, p.screen), x: w - tw - 8, y: along(cy - 13, t, h - 26), angle: 0}
			else if (x1 <= l) {peer: p.id, name: p.name, colour: p.colour, screen: p.screen, label: label(studio, p.screen), x: l + 8, y: along(cy - 13, t, h - 26), angle: 180}
			else if (y1 <= t) {peer: p.id, name: p.name, colour: p.colour, screen: p.screen, label: label(studio, p.screen), x: along(cx - tw / 2, l, w - tw), y: t + 8, angle: -90}
			else {peer: p.id, name: p.name, colour: p.colour, screen: p.screen, label: label(studio, p.screen), x: along(cx - tw / 2, l, w - tw), y: h - 34, angle: 90};
			out.push(e);
		}
		return out;
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

private typedef Edge = {peer:String, name:String, colour:String, screen:String, label:String, x:Float, y:Float, angle:Float};
