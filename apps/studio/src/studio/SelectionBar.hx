package studio;

import helder.ui.*;
import helder.view.*;
import helder.view.Flow.*;
import helder.view.graph.Graph.*;
import helder.view.graph.Read;
import studio.Theme.c;

// The selected frame's bar, under it on the watched canvas: in the stage's
// points from the camera (moving with it, readable at any zoom, as wide as
// the frame within MIN and MAX). Its label (group · name); Play from here
// (a window of the app from this frame's moment: Studio.playEntry); Ask
// (the prompt about it: its chip over the chat's field); Code (its story's,
// scenario's or design's file at its line). A loop frame's recorded loop
// (the frames file's, never the live program) played or scrubbed: shown
// over the frame (Board), its time beside.
@:renderer(helder.ui.view.NodeRenderer)
class SelectionBar implements Markup {
	static inline var MIN = 440.0;
	static inline var MAX = 560.0;
	static inline var GAP = 10.0;

	public static function view(studio:Studio):View
		return <For each={selected(studio)} by={(n:String) -> n}>{(n:Read<String>) -> bar(studio, n())}</For>;

	// (the frame the bar is for: selected, on the canvas, nothing playing in it)
	public static function selected(studio:Studio):Array<String> {
		var f = studio.focused();
		return f == null || studio.classic || studio.playing() != null || studio.mode() == "stories" || studio.layout.rect(f) == null ? [] : [f];
	}

	// what it holds for a frame: its label, Play from here (not a design's), a loop's scrubber
	public static function parts(project:Project, name:String):Null<{label:String, play:Bool, loop:Null<Float>}> {
		var info = project.screen(name);
		if (info == null) return null;
		var design = info.source.match(Design(_));
		return {label: (info.group ?? info.flow) + " · " + info.label, play: !design, loop: design ? null : info.loop};
	}

	static function bar(studio:Studio, name:String):View {
		var p = parts(studio.project, name);
		if (p == null) return <view/>;
		return <view tag="selection-bar" position="absolute" left={box(studio, name).x} top={box(studio, name).y} width={box(studio, name).w}
			pointerEvents="auto" onPointerDown={e -> e.stop()} onPress={e -> e.stop()} onPan={_ -> {}} padding="6 6 6 12" rowGap={6} borderRadius={10} background={c("card")} borderWidth={1} borderColor={c("hair2")}
			boxShadow="0 8 24 rgba(0,0,0,0.35)">
			<view flexDirection="row" alignItems="center" columnGap={4}>
				<text tag="selection-label" fontSize={Theme.SMALL} fontWeight={Theme.MEDIUM} color={c("ink")} lineClamp={1} textWrap="nowrap"
					textOverflow="ellipsis" flexGrow={1} flexShrink={1} minWidth={0}>{p.label}</text>
				<Show when={p.play}>{button(studio, "play-from-here", Icons.play, "Play from here", () -> studio.playWindow(name))}</Show>
				{button(studio, "selection-ask", Icons.sparkles, "Ask", () -> studio.askAbout(name))}
				{button(studio, "selection-code", Icons.code, "Code", () -> studio.codeOf(name))}
			</view>
			<Show when={p.loop != null}>{scrubber(studio, name, p.loop)}</Show>
		</view>;
	}

	static function button(studio:Studio, tag:String, icon:Svg, label:String, press:Void->Void):View
		return <button tag={tag} aria-label={label} flexDirection="row" alignItems="center" columnGap={5} height={26} padding="0 9" borderRadius={7}
			flexShrink={0} background={c("bubble")} color={c("ink2")} cursor="pointer" onPress={press}>
			<image src={icon} width={Theme.ICON_XS} height={Theme.ICON_XS}/>
			<text fontSize={Theme.SMALL} textWrap="nowrap">{label}</text>
		</button>;

	// (where it goes in the stage: place's, from the frames and their captions there)
	static function box(studio:Studio, name:String):{x:Float, y:Float, w:Float} {
		studio.camera.changed();
		studio.stageSize();
		var r = studio.layout.rect(name), cam = studio.camera, p = parts(studio.project, name);
		if (r == null || p == null) return {x: 0, y: 0, w: MIN};
		function stage(x:Float, y:Float, w:Float, h:Float):FrameBox
			return {x0: cam.sx(x), y0: cam.sy(y) - CAPTION, x1: cam.sx(x + w), y1: cam.sy(y + h)};
		var w = Math.max(MIN, Math.min(MAX, r.w * cam.k));
		var at = place(stage(r.x, r.y, r.w, r.h), [for (o in studio.layout.screens()) stage(o.x, o.y, o.w, o.h)], w, p.loop == null ? SHORT : TALL,
			studio.stageWidth, studio.stageHeight);
		return {x: at.x, y: at.y, w: w};
	}

	// (its heights: one row, a loop's two; a frame's caption above it, stage points)
	static inline var SHORT = 40.0;
	static inline var TALL = 72.0;
	static inline var CAPTION = 26.0;

	// where a bar w by h goes for a frame (its box from its caption's top,
	// stage points) among the others: centred on it, inside the stage's
	// sides, covering none of them: under it when the gap there fits; else
	// above its caption; else the first gap further down its column, then
	// up (pinned to its x); else (no gap in the stage) the stage's bottom edge
	public static function place(frame:FrameBox, frames:Array<FrameBox>, w:Float, h:Float, stageW:Float, stageH:Float):{x:Float, y:Float} {
		var x = Math.max(GAP, Math.min(stageW - w - GAP, (frame.x0 + frame.x1) / 2 - w / 2));
		var column = frames.filter(f -> f.x1 > x && f.x0 < x + w);
		function free(y:Float):Bool
			return y >= GAP && y + h <= stageH - GAP && !Lambda.exists(column, f -> f.y1 + GAP > y && f.y0 - GAP < y + h);
		var below = frame.y1 + GAP, above = frame.y0 - GAP - h;
		if (free(below)) return {x: x, y: below};
		if (free(above)) return {x: x, y: above};
		var down = [for (f in column) if (f.y1 > frame.y1) f.y1 + GAP];
		down.sort(Reflect.compare);
		for (y in down)
			if (free(y)) return {x: x, y: y};
		var up = [for (f in column) if (f.y0 < frame.y0) f.y0 - GAP - h];
		up.sort((a, b) -> Reflect.compare(b, a));
		for (y in up)
			if (free(y)) return {x: x, y: y};
		return {x: x, y: stageH - GAP - h};
	}

	// a loop frame's recorded loop: play, pause, the time scrubbed; none
	// recorded (a loop a non-data pass draws in is played live: no frames
	// kept), said, nothing to scrub
	static function scrubber(studio:Studio, name:String, seconds:Float):View {
		var s = studio.previews?.screen(name);
		function rec() {
			s?.kept();
			return studio.previews?.recorded(name);
		}
		function length():Float {
			var r = rec();
			return r == null ? seconds : r.lists.length / r.fps;
		}
		function now():Float {
			var c = studio.scrub();
			return c != null && c.screen == name ? c.t : 0.0;
		}
		var dragging = false;
		function seek(e:Event) {
			var w = e.current.rect().width;
			if (w > 0) studio.scrubTo(name, e.localX / w * length(), length());
		}
		return <view tag="scrubber" flexDirection="row" alignItems="center" columnGap={8} height={24} opacity={rec() == null ? 0.5 : 1}>
			<button tag="scrub-play" aria-label={studio.scrub()?.playing == true ? "Pause" : "Play the loop"} width={24} height={24} borderRadius={6}
				alignItems="center" justifyContent="center" flexShrink={0} background={c("bubble")} color={c("ink2")} cursor={rec() == null ? "default" : "pointer"}
				onPress={() -> if (rec() != null) studio.scrubPlay(name, !(studio.scrub.peek()?.screen == name && studio.scrub.peek().playing), length())}>
				<image src={studio.scrub()?.playing == true ? Icons.pause : Icons.play} width={Theme.ICON_XS} height={Theme.ICON_XS}/>
			</button>
			<Show when={rec() != null} fallback={
				<text tag="scrub-none" fontSize={Theme.SMALL} color={c("fg3")} flexGrow={1} lineClamp={1} textWrap="nowrap">{'Loop not recorded yet · ${fmt(seconds)} s'}</text>
			}>
				<view tag="scrub-track" flexGrow={1} height={24} justifyContent="center" cursor="pointer" onPointerDown={e -> {
					dragging = true;
					e.current.capture();
					seek(e);
				}} onPointerMove={e -> if (dragging) seek(e)} onPointerUp={e -> {
					dragging = false;
					e.current.releaseCapture();
				}}>
					<view height={3} borderRadius={2} background={c("hair2")}/>
					<view position="absolute" left={0} top={10.5} height={3} borderRadius={2} background={c("ink2")} width={now() / Math.max(0.001, length()) * 100 + "%"}/>
				</view>
				<text tag="scrub-time" fontSize={Theme.SMALL} color={c("ink2")} flexShrink={0} textWrap="nowrap">{'${fmt(now())} s / ${fmt(length())} s'}</text>
			</Show>
		</view>;
	}

	// (seconds to a tenth: 3.2, 7)
	public static function fmt(t:Float):String {
		var r = Math.round(t * 10) / 10;
		return r == Math.floor(r) ? Std.string(Std.int(r)) : Std.string(r);
	}
}

// (a frame's box in the stage, its caption's top to its bottom)
typedef FrameBox = {x0:Float, y0:Float, x1:Float, y1:Float};
