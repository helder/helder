package studio;

import helder.ui.*;
import helder.view.*;
import helder.view.Flow.*;
import helder.view.graph.Graph.*;
import helder.view.graph.Read;
import helder.view.graph.Signal;
import studio.Theme.c;

using StringTools;

// Play (the toolbar's): what is selected run as it would run, else the app
// from its start. In the studio (the default target; the only one in the
// browser): a story full size and live, the pointer's, the wheel's and the
// keys' events its own (the preview host's Input.*), its controls in a panel
// (Story.controls, Story.set); the app the same (a project whose program is
// its stories has no App screen: run it in a window instead); a design's
// frame as a prototype, the page's frames one after the other with the
// arrow keys (flows and interactions are not made yet). Elsewhere a target
// is `helder dev` on the project (StudioCommand's helder, HELDER_CLI): a
// window of its own (hot reload kept), a phone (Android's, connected:
// --target android), a browser's tab (--target web, the page it serves
// opened). Escape or Stop ends it.
@:renderer(helder.ui.view.NodeRenderer)
class Play implements Markup {
	public static final targets = ["studio", "window", "phone", "browser"];

	public static function label(t:String):String
		return switch t {
			case "window": "Window";
			case "phone": "Phone";
			case "browser": "Browser";
			case _: "Studio";
		}

	public static function icon(t:String):Svg
		return switch t {
			case "window": Icons.appWindow;
			case "phone": Icons.smartphone;
			case "browser": Icons.globe;
			case _: Icons.monitor;
		}

	// the toolbar's Play and the target beside it
	public static function button(studio:Studio):View {
		var picking = signal(false);
		return <view flexDirection="row" alignItems="center" columnGap={2}>
			<button tag="play" slot="primary" aria-label={studio.playing() == null ? "Play" : "Stop"}
				onPress={() -> if (studio.playing.peek() != null) studio.stopPlay() else studio.play()}>
				<image src={studio.playing() == null ? Icons.play : Icons.element} width={Theme.ICON_S} height={Theme.ICON_S}/>
				<text>{studio.playing() == null ? "Play" : "Stop"}</text>
			</button>
			<Show when={targetsHere().length > 1}>
				<button tag="play-target" slot="button" aria-label={"Play in: " + label(studio.target())} data-on={picking() ? "true" : "false"}
					onPress={() -> picking(!picking.peek())}>
					<image src={icon(studio.target())} width={Theme.ICON_S} height={Theme.ICON_S}/>
					<image src={Icons.chevronDown} width={Theme.ICON_XS} height={Theme.ICON_XS}/>
				</button>
			</Show>
			<Show when={picking()}>
				<view tag="play-targets" slot="floating" position="absolute" top={Theme.HEADER - 6} right={0} width={210} padding={4} boxShadow={Theme.POPOVER}>
					{[for (t in targetsHere()) <button tag={"target-" + t} slot="menu-item" aria-label={label(t)} data-on={studio.target() == t ? "true" : "false"}
						onPress={() -> {
							studio.target(t);
							picking(false);
						}}>
						<image src={icon(t)} width={Theme.ICON_S} height={Theme.ICON_S}/>
						<text flexGrow={1}>{label(t)}</text>
						<text fontSize={Theme.SMALL} color={c("fg3")}>{t == "studio" ? "here" : t == "phone" ? "Android" : "helder dev"}</text>
					</button>]}
				</view>
			</Show>
		</view>;
	}

	// (in the browser the studio's own alone)
	static function targetsHere():Array<String>
		return #if (hxmc.target == "wasm32-wasi") ["studio"] #else targets #end;

	// the player over the canvas; compact, the page below the top bar: the
	// screen fitted alone, the controls a sheet (Sheets' "controls")
	public static function view(studio:Studio):View {
		var p = studio.playing();
		if (p == null) return null;
		var info = p.screen == null ? null : studio.project.screen(p.screen);
		if (studio.compact()) return <view tag="player" flexGrow={1} minHeight={0} background={c("canvas")} onPress={e -> e.stop()} onPointerDown={e -> e.stop()}>
			<view flexGrow={1} minHeight={0}>{stage(studio, p, info)}</view>
			<view height={studio.sheet() == null ? 0.0 : studio.sheetHeight(studio.detent())} flexShrink={0}/>
		</view>;
		return <view tag="player" flexGrow={1} minHeight={0} background={c("canvas")} onPress={e -> e.stop()} onPointerDown={e -> e.stop()}>
			<view tag="player-head" flexDirection="row" alignItems="center" columnGap={8} height={Theme.HEADER} padding={'0 8 0 ${Theme.PAD}'} background={c("bg")}
				borderWidth="0 0 1 0" borderColor={c("line")} flexShrink={0}>
				<image src={p.kind == "design" ? Icons.penTool : p.kind == "app" ? Icons.appWindow : p.kind == "target" ? icon(studio.target()) : Icons.bookOpen}
					width={Theme.ICON_S} height={Theme.ICON_S} color={c("fg2")}/>
				<text fontWeight={Theme.MEDIUM} lineClamp={1}>{info == null ? label(studio.target()) : info.label}</text>
				<text tag="player-note" fontSize={Theme.SMALL} color={c("fg3")} lineClamp={1} flexShrink={1}>{p.kind == "target" ? studio.playLog() : p.note}</text>
				<view flexGrow={1}/>
				<Show when={p.kind == "design"}>
					<button tag="player-prev" slot="button" aria-label="The frame before" onPress={() -> studio.playStep(-1)}>
						<image src={Icons.chevronRight} width={Theme.ICON_S} height={Theme.ICON_S} transform="rotate(180deg)"/>
					</button>
					<button tag="player-next" slot="button" aria-label="The next frame" onPress={() -> studio.playStep(1)}>
						<image src={Icons.chevronRight} width={Theme.ICON_S} height={Theme.ICON_S}/>
					</button>
				</Show>
			</view>
			<view flexDirection="row" flexGrow={1} minHeight={0}>
				{stage(studio, p, info)}
				<Show when={p.kind == "story"}>
					<view tag="player-controls" width={Theme.INSPECTOR} flexShrink={0} background={c("bg")} borderWidth="0 0 0 1" borderColor={c("line")}>
						{controls(studio)}
					</view>
				</Show>
			</view>
		</view>;
	}

	static function stage(studio:Studio, p:Playing, info:Null<Project.ScreenInfo>):View
		return <view tag="player-stage" flexGrow={1} minWidth={0} alignItems="center" justifyContent="center" focusable ref={(n:Node) -> haxe.Timer.delay(() -> n.focus(false), 0)}
			onKeyDown={e -> key(studio, p, e, "down")} onKeyUp={e -> key(studio, p, e, "up")} onTextInput={e -> if (p.kind != "design") send(studio, p, "Input.text", {text: e.text})}>
			{p.kind == "target" ? <text color={c("fg3")} padding={24}>{"Running in " + label(studio.target()).toLowerCase() + ": its output above."}</text>
				: info == null ? <text color={c("fg3")} padding={24}>{p.note}</text>
				: p.kind == "design" ? design(studio, info) : live(studio, p, info)}
		</view>;

	// compact: the top bar's buttons while playing (a story's controls, a prototype's frames)
	public static function tools(studio:Studio):View
		return <view flexDirection="row" alignItems="center">
			<Show when={studio.playing()?.kind == "story"}>
				<button tag="player-controls-open" slot="button" aria-label="Controls"
					data-on={studio.sheet() == "controls" ? "true" : "false"} onPress={() -> studio.openSheet("controls")}>
					<image src={Icons.ruler} width={Theme.ICON} height={Theme.ICON}/>
				</button>
			</Show>
			<Show when={studio.playing()?.kind == "design"}>
				<button tag="player-prev" slot="button" aria-label="The frame before" onPress={() -> studio.playStep(-1)}>
					<image src={Icons.chevronRight} width={Theme.ICON} height={Theme.ICON} transform="rotate(180deg)"/>
				</button>
				<button tag="player-next" slot="button" aria-label="The next frame" onPress={() -> studio.playStep(1)}>
					<image src={Icons.chevronRight} width={Theme.ICON} height={Theme.ICON}/>
				</button>
			</Show>
		</view>;

	// (compact: the room around the screen)
	public static inline var PAD = 12;

	// the frame's scale: 1:1, else fitted into the player; compact, fitted
	// to the page below the top bar (above the controls' sheet), larger too
	public static function fit(studio:Studio, w:Float, h:Float, panel:Bool):Float {
		studio.stageSize();
		if (studio.compact()) {
			var below = studio.sheet() == null ? 0.0 : studio.sheetHeight(studio.detent());
			return Math.min((studio.stageWidth - 2 * PAD) / Math.max(1, w), (studio.stageHeight - Theme.TOPBAR - below - 2 * PAD) / Math.max(1, h));
		}
		var aw = studio.stageWidth - Theme.SIDEBAR - (panel ? Theme.INSPECTOR : 0) - 48;
		var ah = studio.stageHeight - Theme.HEADER - Theme.HEADER - 48;
		return Math.min(1, Math.min(aw / Math.max(1, w), ah / Math.max(1, h)));
	}

	// a story's or the app's screen: its frames, its input the program's
	static function live(studio:Studio, p:Playing, info:Project.ScreenInfo):View {
		var s = studio.previews?.screen(info.name);
		if (s == null) return <text color={c("fg3")}>{"Not built yet."}</text>;
		studio.playScreen = null;
		var down = false;
		function at(e:Event):{x:Float, y:Float} {
			var k = fit(studio, s.width(), s.height(), p.kind == "story");
			return {x: e.localX / k, y: e.localY / k};
		}
		return <view tag="player-screen" ref={(n:Node) -> studio.playScreen = n} width={s.width() * fit(studio, s.width(), s.height(), p.kind == "story")}
			height={s.height() * fit(studio, s.width(), s.height(), p.kind == "story")} borderWidth={1} borderColor={c("line")} overflow="hidden"
			onPointerDown={e -> {
				down = true;
				var q = at(e);
				send(studio, p, "Input.pointer", {type: "down", x: q.x, y: q.y, button: 1});
			}} onPointerMove={e -> {
				var q = at(e);
				send(studio, p, "Input.pointer", {type: "move", x: q.x, y: q.y});
			}} onPointerUp={e -> {
				down = false;
				var q = at(e);
				send(studio, p, "Input.pointer", {type: "up", x: q.x, y: q.y, button: 1});
			}} onWheel={e -> {
				var q = at(e);
				send(studio, p, "Input.wheel", {x: q.x, y: q.y, dx: e.deltaX, dy: e.deltaY});
				e.stop();
			}}>
			<image src={s.image()} width="100%" height="100%"/>
		</view>;
	}

	// a design's frame at its size (fitted), its nodes as the canvas draws them
	static function design(studio:Studio, info:Project.ScreenInfo):View {
		var w = info.width > 0 ? info.width : 390, h = info.height > 0 ? info.height : 844, k = fit(studio, w, h, false);
		return <view tag="player-design" width={w * k} height={h * k} borderWidth={1} borderColor={c("line")} overflow="hidden">
			<view width={w} height={h} transformOrigin="left top" transform={'scale($k)'} pointerEvents="none" background="#ffffff" color="#000000"
				fontFamily={helder.ui.Style.DEFAULT_FAMILY} fontSize={helder.ui.Style.DEFAULT_SIZE} fontWeight={helder.ui.Style.DEFAULT_WEIGHT}
				ref={(n:Node) -> n.theme = {rules: []}}>{studio.designs.content(info.name)}</view>
		</view>;
	}

	// a story's controls: each kind its field, set in the program at once
	public static function controls(studio:Studio):View {
		return <view>
			<view slot="section" borderWidth={0}>
				<view slot="section-head"><text>Controls</text></view>
				<Show when={studio.playControls().length > 0} fallback={<text fontSize={Theme.SMALL} color={c("fg3")}>{"This story has no controls."}</text>}>
					<For each={studio.playControls()} by={(x:Dynamic) -> x.name}>{(x:Read<Dynamic>) -> {
						var ctl:Dynamic = x();
						<view tag={"control-" + Shell.slug(ctl.name)} slot="field">
							<text slot="field-label" cursor="default" lineClamp={1}>{ctl.name}</text>
							{switch (ctl.kind : String) {
								case "bool": <button slot="seg-item" aria-label={ctl.name} data-on={ctl.value == true ? "true" : "false"}
										onPress={() -> studio.setControl(ctl.name, ctl.value != true)}><text>{ctl.value == true ? "On" : "Off"}</text></button>;
								case "choice": <view slot="seg">{[for (o in (ctl.options : Array<String>)) <button slot="seg-item" aria-label={o}
										data-on={ctl.value == o ? "true" : "false"} onPress={() -> studio.setControl(ctl.name, o)}><text>{o}</text></button>]}</view>;
								case kind: <field slot="field-input" aria-label={ctl.name} value={kind == "color" ? "#" + StringTools.hex(ctl.value, 8) : Std.string(ctl.value)}
										onInput={e -> studio.setControl(ctl.name, kind == "number" ? Std.parseFloat(e.text) : kind == "color" ? Std.parseInt("0x" + e.text.replace("#", "")) : e.text)}/>;
							}}
						</view>;
					}}</For>
				</Show>
			</view>
		</view>;
	}

	static function key(studio:Studio, p:Playing, e:Event, type:String) {
		if (e.key == Key.ESCAPE) {
			if (type == "down") studio.stopPlay();
			e.stop();
			return;
		}
		if (p.kind == "design") {
			if (type == "down" && (e.key == Key.RIGHT || e.key == Key.DOWN)) studio.playStep(1);
			if (type == "down" && (e.key == Key.LEFT || e.key == Key.UP)) studio.playStep(-1);
			return;
		}
		send(studio, p, "Input.key", {type: type, key: e.key, mods: e.mods});
		e.stop();
	}

	static function send(studio:Studio, p:Playing, method:String, params:Dynamic) {
		var s = p.screen == null ? null : studio.previews?.screen(p.screen);
		if (s != null) studio.previews.request(s, method, params, _ -> {});
	}
}

// what plays: its kind ("story", "app", "design"; "target": another target's
// process), its screen, what to say about it
typedef Playing = {kind:String, screen:Null<String>, note:String};
