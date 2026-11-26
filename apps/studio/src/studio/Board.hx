package studio;

import helder.os.Mods;
import helder.ui.*;
import helder.view.*;
import helder.view.Flow.*;
import helder.view.graph.Graph.*;
import helder.view.graph.Read;
import studio.Project.Source;
import studio.Theme.c;

using StringTools;

// The canvas: every screen of the project at once, grouped by flow (a row
// each), a story's frames the program's (Previews: refreshed as they draw),
// a design's frame its own nodes, interpreted here (Designs).
// Pan with a drag or the wheel, zoom with secondary and the wheel (a
// trackpad's pinch) or two fingers; a screen clicked zooms into it on a
// short spring, a click inside the zoomed screen selects the node there
// (the program's tree, the node's source), outlined at once.
// The world (the screens) is one node under the camera's transform; what is
// read at any zoom (flows' titles, captions, the selection) is drawn in the
// stage's own points from the camera.
// Watched (the default shell, not --classic): nothing on it takes input but
// the camera (pan, zoom), a click (a frame the prompt's focus) and a double
// click (Play): no selection, no drags, no drops; its ground the dots.
@:renderer(helder.ui.view.NodeRenderer)
class Board implements Markup {
	public static function view(studio:Studio):View {
		var stage:Null<Node> = null, panned = false, watch = !studio.classic;
		// (the camera at rest: a frame drawn, the frames in view told how sharp, Studio.showVisible)
		effect(() -> studio.camera.rest(), _ -> stage?.ui?.requestFrame());
		return <view tag="stage" flexGrow={1} minWidth={0} overflow="hidden" cursor={watch ? studio.camera.hand() : (Default : Cursor)} background={c(watch ? "ground" : "canvas")} ref={n -> {
			stage = n;
			studio.stageNode = n;
		}}
			focusable={watch} onPointerDown={e -> {
				panned = false;
				// (the watched canvas takes the keys when pressed, from the chat's field too: Space shows the hand)
				if (watch) e.current.focus(false);
			}}
			onPointerEnter={e -> if (watch && e.current.ui?.focus == null) e.current.focus(false)}
			onKeyDown={e -> if (watch && e.key == Key.SPACE) {
				studio.camera.held(true);
				e.preventDefault();
			}} onKeyUp={e -> if (watch && e.key == Key.SPACE) studio.camera.held(false)}
			onBlur={_ -> studio.camera.held(false)}
			onPress={e -> if (e.type != Click) {} else if (watch && !panned) studio.aimAt(e.localX, e.localY) else if (studio.mode() != "stories" && !panned)
				studio.clickStage(e.localX, e.localY, e.mods & Mods.SHIFT != 0)}
			onWheel={e -> {
				// (a pinch's deltaY is -100 ln of its scale, as browsers make it:
				// e^(-dy/100) follows the fingers; a wheel's notch, 40 to 120
				// points at once, capped to a step of about 1.28)
				studio.camera.taken = true;
				if (e.mods & (Mods.CONTROL | Mods.META) != 0) studio.camera.zoomAt(e.localX, e.localY, Math.exp(-Math.max(-25, Math.min(25, e.deltaY)) / 100))
				else studio.camera.panBy(-e.deltaX, -e.deltaY);
				e.preventDefault();
				e.stop();
			}}
			onPan={g -> {
				// (a drag that edits a design: a frame moved, a node moved or resized; else the canvas panned)
				var d = studio.drag;
				// (the mouse's release after a drag is a click too: not the stage's)
				panned = true;
				if (watch) {
					studio.camera.taken = true;
					studio.camera.panBy(g.dx, g.dy);
					studio.camera.dragging(g.state != Ended && g.state != Cancelled);
					return;
				}
				if (g.state == Began) d.begin(g.x - g.tx, g.y - g.ty);
				if (!d.active) studio.camera.panBy(g.dx, g.dy) else if (g.state == Ended || g.state == Cancelled) d.end() else d.move(g.tx, g.ty);
			}}
			onDragOver={e -> if (!watch && Std.isOfType(e.data, String) && FileTree.kindOf(e.data) == Image) e.preventDefault()}
			onDrop={e -> if (!watch && Std.isOfType(e.data, String)) studio.dropImage(e.data, e.localX, e.localY)}
			onPinch={g -> {
				studio.camera.taken = true;
				studio.camera.zoomAt(g.x, g.y, g.dscale);
				if (g.state == Ended) studio.log("pinched", {k: studio.camera.k});
			}}>
			{watch ? dots(studio) : null}
			<Show when={studio.mode() != "stories" && (studio.classic || !Watch.blank(studio) && !studio.waiting())}>
				<view tag="world" position="absolute" left={0} top={0} width={1} height={1} transformOrigin="left top" transform={transform(studio)}>
					<For each={studio.layout.screens()} by={(r:Rect) -> r.name + "@" + studio.revived.peek()}>{(r:Read<Rect>) -> {
						var info = studio.project.screen(r().name);
						info.source.match(Design(_)) ? design(studio, r, info) : live(studio, r);
					}}</For>
				</view>
				{overlay(studio)}
			</Show>
			<Show when={studio.mode() == "stories"}>{stories(studio)}</Show>
			<Show when={studio.classic && studio.mode() != "code" && !studio.compact()}>{Prompt.view(studio)}</Show>
		</view>;
	}

	// (the ground's dots, following the camera)
	static function dots(studio:Studio):Node {
		// (the hand's changes told to checks)
		effect(() -> studio.camera.hand(), h -> studio.log("hand", {cursor: (cast h : String)}));
		var d = new Dots(studio.camera, c("dots"));
		d.style.position = Absolute;
		d.style.inset = 0;
		effect(() -> studio.camera.changed(), _ -> d.moved());
		return d;
	}

	// a story's or the app's screen: the program's last frame
	static function live(studio:Studio, r:Read<Rect>):View {
		var s = studio.previews.screen(r().name);
		return <view tag={"screen-" + Shell.slug(s.info.name)} slot="screen" position="absolute" left={r().x} top={r().y} width={r().w}
			height={r().h} data-on={studio.focused() == s.info.name ? "true" : "false"} data-frame={s.frames()}
			onPointerEnter={_ -> studio.hover(s.info.name)} onPointerLeave={_ -> if (studio.hovered.peek() == s.info.name) studio.hovered(null)}
			opacity={Feedback.arrive(studio, s.info.name).opacity} transform={Feedback.arrive(studio, s.info.name).transform}>
			<image src={s.image()} width={r().w} height={r().h} opacity={studio.shownFailure() == null && !s.crashedSignal() ? 1 : 0.45}/>
			<Show when={s.still() != null && (s.image() == null || studio.hovered() == s.info.name && studio.previews.fileLoops(s.info.name))}>{still(studio, s, r)}</Show>
			<Show when={s.frames() == 0 && s.still() == null && !s.crashedSignal()}>{Feedback.skeleton(studio, r().w)}</Show>
		</view>;
	}

	// (a screen's still from the frames file until the program draws it: dimmed when its files changed since)
	static function still(studio:Studio, s:Previews.Screen, r:Read<Rect>):Node {
		var n = new StillFrame(s.still.peek(), s.stillPasses, s.stillWidth, s.stillHeight);
		n.tag = "still";
		// (its scenes' worlds let go with it)
		onCleanup(n.dispose);
		effect(() -> studio.sharpness(), k -> n.sharp = k);
		effect(() -> {w: r().w, h: r().h, dim: s.stale() || studio.shownFailure() != null || s.crashedSignal()}, v -> {
			n.style.set({position: Absolute, left: 0, top: 0, width: v.w, height: v.h, opacity: v.dim ? 0.45 : 1});
		});
		// (hovered: its loop from the file, played; let go, the still)
		var name = s.info.name;
		effect(() -> studio.hovered() == name, on -> {
			var l = on ? studio.previews.fileLoop(s) : null;
			if (l == null) n.stop() else n.play(l.fps, l.lists, l.passes, () -> studio.loopShown(name, "file"),
				(frames, ms) -> studio.log("loop-played", {screen: name, frames: frames, msPerFrame: Math.round(ms * 1000) / 1000}));
		});
		return n;
	}

	// a design's frame: its nodes, interpreted, under a theme of none and
	// ui's own defaults (not the studio's), as the app would draw them; a
	// click goes through them to the stage
	static function design(studio:Studio, r:Read<Rect>, info:Project.ScreenInfo):View
		return <view tag={"screen-" + Shell.slug(info.name)} slot="screen" position="absolute" left={r().x} top={r().y} width={r().w}
			height={r().h} data-on={studio.focused() == info.name ? "true" : "false"} opacity={Feedback.arrive(studio, info.name).opacity}
			transform={Feedback.arrive(studio, info.name).transform}>
			<view tag="design" width={r().w} height={r().h} overflow="hidden" pointerEvents="none" background="#ffffff" color="#000000"
				fontFamily={helder.ui.Style.DEFAULT_FAMILY} fontSize={helder.ui.Style.DEFAULT_SIZE} fontWeight={helder.ui.Style.DEFAULT_WEIGHT}
				ref={(n:Node) -> n.theme = {rules: []}}>
				{studio.designs.content(info.name)}
			</view>
		</view>;

	static function transform(studio:Studio):String {
		studio.camera.changed();
		return studio.camera.transform();
	}

	// what is drawn in the stage's points: the flows' titles and lines, the screens' captions, the selection
	static function overlay(studio:Studio):View {
		return <view tag="overlay" position="absolute" inset={0} pointerEvents="none">
			<For each={flows(studio)}>{(f:Read<{name:String, x:Float, y:Float}>) ->
				<text tag="flow-title" position="absolute" left={sx(studio, f().x)} top={sy(studio, f().y) - 50} fontSize={Theme.SMALL} fontWeight={Theme.MEDIUM}
					color={c("fg3")} opacity={titleShown(studio, f().y) ? 1 : 0}>{f().name}</text>
			}</For>
			<For each={studio.layout.groups()} by={(g:GroupRect) -> g.file + "#" + g.title}>{(g:Read<GroupRect>) ->
				<text tag={"group-" + Shell.slug(g().title)} position="absolute" left={sx(studio, g().x)} top={sy(studio, g().y) - 52} fontSize={Theme.GROUP_TITLE}
					fontWeight={Theme.MEDIUM} color={c("ink")} lineClamp={1} textWrap="nowrap">{g().title}</text>
			}</For>
			<For each={studio.layout.screens()} by={(r:Rect) -> r.name}>{(r:Read<Rect>) ->
				<view tag={"caption-" + Shell.slug(r().name)} position="absolute" left={sx(studio, r().x) - 4} top={sy(studio, r().y) - 22} height={18} padding="0 4"
					flexDirection="row" alignItems="center" columnGap={6} maxWidth={frameWidth(studio, r()) + 8}>
					<text fontSize={Theme.SMALL} lineClamp={1} flexShrink={0} fontWeight={studio.focused() == r().name ? Theme.MEDIUM : 400}
						color={studio.focused() == r().name ? c("accent-ink") : c("fg3")}>{label(studio, r().name)}</text>
					<Show when={studio.project?.screen(r().name)?.loop != null}>
						<image tag={"loop-" + Shell.slug(r().name)} src={Icons.repeat} width={Theme.ICON_XS} height={Theme.ICON_XS} flexShrink={0}
							color={studio.hovered() == r().name ? c("ink2") : c("fg3")}/>
					</Show>
					{Feedback.chip(studio, r().name)}
					<Show when={trouble(studio, r().name) != "" && Feedback.on(studio, r().name).length == 0}>
						<view tag={"failed-" + Shell.slug(r().name)} height={20} padding="0 8" borderRadius={10} flexDirection="row" alignItems="center" columnGap={5}
							flexShrink={1} minWidth={0} background={c("error-soft")}>
							<view width={6} height={6} borderRadius={3} flexShrink={0} background={c("error")}/>
							<text fontSize={Theme.SMALL} lineClamp={1} textWrap="nowrap" textOverflow="ellipsis" flexShrink={1} minWidth={0} color={c("error")}>{trouble(studio, r().name)}</text>
						</view>
					</Show>
				</view>
			}</For>
			<Show when={selected(studio) != null}>{selectionBox(studio)}</Show>
			<For each={otherBoxes(studio)}>{(b:Read<{x:Float, y:Float, w:Float, h:Float}>) ->
				<view tag="selection-other" position="absolute" left={b().x} top={b().y} width={b().w} height={b().h} borderWidth={1} borderColor={c("sel")}/>
			}</For>
			<For each={handles(studio)}>{(h:Read<{x:Float, y:Float}>) ->
				<view tag="handle" position="absolute" left={h().x - Theme.HANDLE / 2} top={h().y - Theme.HANDLE / 2} width={Theme.HANDLE} height={Theme.HANDLE} borderRadius={1}
					background="#ffffff" borderWidth={1} borderColor={c("sel")}/>
			}</For>
			<For each={guides(studio)}>{(g:Read<{x:Float, y:Float, w:Float, h:Float}>) ->
				<view tag="guide" position="absolute" left={g().x} top={g().y} width={g().w} height={g().h} background={c("sel")}/>
			}</For>
			{Feedback.canvas(studio)}
		</view>;
	}

	// (by a live frame: a failed build's first error and where, else what it
	// threw when run; "": neither. A failed build: one chip a row, by its first frame)
	static function trouble(studio:Studio, name:String):String {
		var info = studio.project?.screen(name);
		if (info == null || info.source.match(Design(_))) return "";
		var f = studio.shownFailure();
		if (f != null) return first(studio, name) ? "Build failed · " + (f.at == null ? f.message : '${f.at} · ${f.message}') : "";
		var s = studio.previews?.screen(name);
		return s != null && s.crashedSignal() ? "Crashed · " + s.report() : "";
	}

	// (the first of its row's frames)
	static function first(studio:Studio, name:String):Bool {
		var rs = studio.layout.screens(), r = Lambda.find(rs, r -> r.name == name);
		return r != null && Lambda.find(rs, x -> x.flow == r.flow)?.name == name;
	}

	// (a frame's width in the stage's points)
	static function frameWidth(studio:Studio, r:Rect):Float {
		studio.camera.changed();
		return r.w * studio.camera.k;
	}

	// (a design's selection: the others' boxes, in the stage's points)
	static function otherBoxes(studio:Studio):Array<{x:Float, y:Float, w:Float, h:Float}> {
		var s = selected(studio), r = s == null ? null : studio.layout.rect(s.screen);
		if (r == null) return [];
		studio.camera.changed();
		studio.docs.version();
		var cam = studio.camera, out = [];
		for (o in studio.others()) {
			var n = studio.designs.nodeAt(o.screen, o.start);
			if (n == null) continue;
			var b = studio.designs.box(o.screen, n);
			out.push({x: cam.sx(r.x + b.x), y: cam.sy(r.y + b.y), w: b.width * cam.k, h: b.height * cam.k});
		}
		return out;
	}

	// (a design's selection alone: its handles, dragged to resize it)
	static function handles(studio:Studio):Array<{x:Float, y:Float}> {
		var s = selected(studio), r = s == null ? null : studio.layout.rect(s.screen);
		var info = s == null ? null : studio.project.screen(s.screen);
		if (r == null || info == null || !info.source.match(Design(_)) || studio.others().length > 0) return [];
		studio.camera.changed();
		return Drag.handles(studio.camera, r.x + s.x, r.y + s.y, s.width, s.height);
	}

	// (the snaps' guides, a point wide in the stage)
	static function guides(studio:Studio):Array<{x:Float, y:Float, w:Float, h:Float}> {
		studio.camera.changed();
		var cam = studio.camera;
		return [
			for (g in studio.drag.guides())
				g.vertical ? {x: cam.sx(g.at), y: cam.sy(g.from), w: 1.0, h: (g.to - g.from) * cam.k} : {x: cam.sx(g.from), y: cam.sy(g.at), w: (g.to - g.from) * cam.k, h: 1.0}
		];
	}

	// the selected node's box (the zoomed screen's), outlined: at once, where the node is
	static function selectionBox(studio:Studio):View {
		function box():{x:Float, y:Float, w:Float, h:Float} {
			var s = selected(studio), r = s == null ? null : studio.layout.rect(s.screen);
			if (s == null || r == null) return {x: -100, y: -100, w: 0, h: 0};
			studio.camera.changed();
			var kk = studio.camera.k;
			return {x: studio.camera.sx(r.x + s.x), y: studio.camera.sy(r.y + s.y), w: s.width * kk, h: s.height * kk};
		}
		return <view tag="selection" position="absolute" left={box().x} top={box().y} width={box().w} height={box().h} borderWidth={1} borderColor={c("sel")}/>;
	}

	// (the selection while its screen is the one zoomed into)
	static function selected(studio:Studio):Null<Studio.Selection> {
		var s = studio.selection();
		return s != null && studio.focused() == s.screen ? s : null;
	}

	static function stories(studio:Studio):View {
		var p = studio.project;
		return <scroll tag="stories" position="absolute" inset={0} padding="20 24" rowGap={6}>
			<For each={p == null ? [] : [for (f in p.flows()) for (s in f.screens) s]}>{(s:Read<Project.ScreenInfo>) -> {
				var i = s();
				<button tag={"story-" + Shell.slug(i.name)} slot="nav-item" columnGap={12} aria-label={i.name} onPress={() -> {
					studio.setMode("design");
					studio.focus(i.name);
				}}>
					<text flexGrow={1}>{i.name}</text>
					<text fontFamily={Theme.CODE} fontSize={Theme.SMALL} color={c("fg3")}>{(i.width > 0 ? i.width + " × " + i.height + "  " : "")
						+ Shell.fileLabel(studio, i.file)}</text>
				</button>;
			}}</For>
		</scroll>;
	}

	// (a flow's title above its row: the first's always, the others' while the rows are far enough apart to hold it, not over the row before)
	static function titleShown(studio:Studio, wy:Float):Bool {
		studio.camera.changed();
		return studio.focused() == null && (wy <= 0 || studio.layout.gap() * studio.camera.k >= 50);
	}

	static function flows(studio:Studio):Array<{name:String, x:Float, y:Float}> {
		var out:Array<{name:String, x:Float, y:Float}> = [], seen = [];
		// (a page whose first frame is a group's: the group's title says it)
		for (r in studio.layout.screens())
			if (!seen.contains(r.flow)) {
				seen.push(r.flow);
				if (studio.project?.screen(r.name)?.group == null) out.push({name: r.flow, x: r.x, y: r.y});
			}
		return out;
	}

	static function label(studio:Studio, name:String):String {
		var s = studio.project == null ? null : Lambda.find(studio.project.screens, x -> x.name == name);
		return s == null ? name : s.label;
	}

	static function sx(studio:Studio, wx:Float):Float {
		studio.camera.changed();
		return studio.camera.sx(wx);
	}

	static function sy(studio:Studio, wy:Float):Float {
		studio.camera.changed();
		return studio.camera.sy(wy);
	}
}

private typedef Rect = {name:String, flow:String, x:Float, y:Float, w:Float, h:Float};
private typedef GroupRect = {file:String, title:String, x:Float, y:Float, w:Float, h:Float};
