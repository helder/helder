package studio;

import helder.os.Rect;
import helder.gfx.Color;
import helder.async.*;
import helder.ui.*;
import helder.view.*;
import helder.view.Flow.*;
import helder.view.graph.Graph.*;
import helder.view.graph.Read;
import helder.view.graph.Signal;
import studio.Presence.Peer;
import studio.Project.Source;
import studio.Theme.c;

// Where the agents are, drawn quietly from Presence (a redesign restyles
// these alone): on the canvas a chip in the agent's colour above the frame
// it is on, while it works, and the nodes its last patch made outlined in
// its colour, fading; in the header a chip each (Shell).
class Marks implements Markup {
	public static inline var FADE = 1.5;

	final studio:Studio;
	// the boxes a patch touched (each in its screen's points; on: just made, then fading)
	public final boxes:Signal<Array<Touch>> = signal([]);
	// (the truth: a signal's write lands at the event's end)
	var all:Array<Touch> = [];
	var next = 0;

	public function new(studio)
		this.studio = studio;

	// an agent's patch of file: the elements it changed (ranges: offsets of
	// the text after it) outlined on the screens in view that show them
	public function touched(colour:String, file:String, ranges:Array<{start:Int, end:Int}>) {
		var p = studio.project;
		if (p == null) return;
		var doc = studio.docs.get(file).doc, starts = [];
		for (r in ranges) {
			var held = doc.elementHolding(r.start);
			if (held != null && !starts.contains(held.start)) starts.push(held.start);
			for (e in doc.elements())
				if (e.start > r.start && e.start <= r.end && !starts.contains(e.start)) starts.push(e.start);
		}
		if (starts.length == 0) return;
		var shown = studio.layout.inView();
		for (s in p.screens)
			if (s.file == file && s.source.match(Design(_)) && shown.contains(s.name))
				add(colour, s.name, [for (n in studio.designs.nodesAt(s.name, starts)) studio.designs.box(s.name, n)]);
		var pr = studio.previews;
		if (pr != null) for (s in pr.screens) {
			var name = s.info.name;
			if (shown.contains(name)) pr.request(s, "Ui.getTree", {}, t -> {
				var found = [];
				function walk(n:Dynamic) {
					if (n == null) return;
					var at:Null<Array<Dynamic>> = n.source?.offsets;
					if (at != null && at.length > 0 && p.real(n.source.file) == file && starts.contains(doc.fromByte(Std.int(at[0]))))
						found.push({x: (n.x : Float), y: (n.y : Float), width: (n.width : Float), height: (n.height : Float)});
					for (c in (n.children : Array<Dynamic>) ?? []) walk(c);
				}
				walk(Studio.rootOf(t));
				add(colour, name, found);
			});
		}
	}

	// (outlined at once, then faded out and let go)
	function add(colour:String, screen:String, found:Array<Rect>) {
		if (found.length == 0) return;
		var made:Array<Touch> = [for (b in found.slice(0, 24)) {id: next++, colour: colour, screen: screen, x: b.x, y: b.y, w: b.width, h: b.height, on: true}];
		var ids = [for (m in made) m.id];
		boxes(all = all.concat(made));
		Async.launch(_ -> {
			Async.delay(0.05);
			boxes(all = [for (b in all) if (ids.contains(b.id)) {var o = Reflect.copy(b); o.on = false; o;} else b]);
			Async.delay(FADE + 0.1);
			boxes(all = all.filter(b -> !ids.contains(b.id)));
		});
	}

	// the canvas' marks, in the stage's points (Board's overlay)
	public static function canvas(studio:Studio):View
		return <view tag="agent-marks" position="absolute" inset={0} pointer-events="none">
			<For each={studio.marks.boxes()} by={(b:Touch) -> b.id}>{(b:Read<Touch>) ->
				<view tag="agent-touch" position="absolute" left={box(studio, b()).x} top={box(studio, b()).y} width={box(studio, b()).w}
					height={box(studio, b()).h} border-width={1.5} border-color={Color.parse(b().colour)} opacity={b().on ? 1 : 0} transition="opacity 1.5s ease-out"/>
			}</For>
			<For each={onFrames(studio)} by={(g:OnFrame) -> g.screen}>{(g:Read<OnFrame>) ->
				<view tag="agent-chips" position="absolute" right={right(studio, g().screen)} top={top(studio, g().screen) - 22} height={18}
					direction="row" column-gap={4}>
					<For each={g().peers} by={(p:Peer) -> p.id}>{(p:Read<Peer>) ->
						<view tag={"agent-on-" + Shell.slug(p().name)} direction="row" align-items="center" column-gap={4} height={18} padding="0 6"
							radius={9} background={c("bg")} opacity={p().working ? 1 : 0} transition="opacity 0.6s">
							<view width={6} height={6} radius={3} background={Color.parse(p().colour)}/>
							<text font-size={Theme.SMALL} max-lines={1} color={c("fg2")}>{p().name}</text>
						</view>
					}</For>
				</view>
			}</For>
		</view>;

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

	// (the agents by the frame each is on: the one it named, else one of the file it works on)
	static function onFrames(studio:Studio):Array<OnFrame> {
		var out:Array<OnFrame> = [], p = studio.project;
		if (p == null) return out;
		for (a in studio.presence.peers()) {
			var s = a.screen;
			if (s == null && a.file != null) s = Lambda.find(p.screens, i -> i.file == p.dir + "/" + a.file)?.name;
			if (s == null || studio.layout.rect(s) == null) continue;
			var g = Lambda.find(out, g -> g.screen == s);
			if (g == null) out.push({screen: s, peers: [a]}) else g.peers.push(a);
		}
		return out;
	}

	static function box(studio:Studio, b:Touch):{x:Float, y:Float, w:Float, h:Float} {
		var r = studio.layout.rect(b.screen);
		if (r == null) return {x: -100, y: -100, w: 0, h: 0};
		studio.camera.changed();
		var cam = studio.camera;
		return {x: cam.sx(r.x + b.x), y: cam.sy(r.y + b.y), w: b.w * cam.k, h: b.h * cam.k};
	}

	static function top(studio:Studio, screen:String):Float {
		var r = studio.layout.rect(screen);
		studio.camera.changed();
		return r == null ? -100 : studio.camera.sy(r.y);
	}

	static function right(studio:Studio, screen:String):Float {
		var r = studio.layout.rect(screen);
		studio.camera.changed();
		studio.stageSize();
		return r == null ? -1000 : studio.stageWidth - studio.camera.sx(r.x + r.w) - 4;
	}
}

typedef Touch = {id:Int, colour:String, screen:String, x:Float, y:Float, w:Float, h:Float, on:Bool};

private typedef OnFrame = {screen:String, peers:Array<Peer>};
