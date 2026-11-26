import helder.gfx.Color;
import Model;
import helder.ui.*;
import helder.ui.widgets.Controls.Segmented;
import helder.ui.widgets.Controls.Slider;
import helder.ui.widgets.Controls.Tip;
import helder.ui.widgets.Theme;
import helder.ui.widgets.Theme.c;
import helder.ui.widgets.WindowButtons;
import helder.ui.widgets.WindowButtons.WindowControls;
import helder.view.*;
import helder.view.Flow.*;
import helder.view.graph.Graph.*;
import helder.view.graph.Read;
import helder.view.graph.Signal;

// The window: the glyphs (the first letters to draw, then every group) on
// the left; the board with its tools in the middle, the draft font under
// it; the font's settings on the right (its name and export, the pen,
// the proportions, this glyph's spacing, agents); a status bar.
@:renderer(helder.ui.view.NodeRenderer)
class Shell implements Markup {
	public static inline var SIDEBAR = 272;
	public static inline var INSPECTOR = 264;

	public static final PRESETS:Array<{name:String, pen:Pen}> = [
		{name: "Marker", pen: {width: 84, contrast: 0, angle: 30, cap: Round}},
		{name: "Fine", pen: {width: 40, contrast: 0, angle: 30, cap: Round}},
		{name: "Brush", pen: {width: 110, contrast: 0.55, angle: 20, cap: Round}},
		{name: "Nib", pen: {width: 120, contrast: 0.85, angle: 35, cap: Flat}}
	];

	static function t(name:String):Color
		return Color.parse('var(--$name)');

	// the theme's parts and Foundry's own (a glyph's cell, a first letter's chip)
	public static final sheet:StyleSheet = {
		rules: Theme.sheet.rules.concat([
			{slot: "cell", style: {height: 56, borderRadius: Theme.RADIUS_M, background: t("well"), borderWidth: 1, borderColor: Color.TRANSPARENT, cursor: Pointer,
				alignItems: Center, padding: [4, 2, 3, 2]}},
			{slot: "cell", when: ["hover"], style: {background: t("hover")}},
			{slot: "cell", when: ["data-on=true"], style: {background: t("on"), borderColor: t("accent")}},
			{slot: "cell", when: ["focus-visible"], style: {outlineWidth: 1, outlineOffset: 1, outlineColor: t("focus")}},
			{slot: "chip", style: {width: 28, height: 34, borderRadius: Theme.RADIUS, background: t("bg"), borderWidth: 1, borderColor: Color.TRANSPARENT,
				cursor: Pointer, alignItems: Center, justifyContent: Center}},
			{slot: "chip", when: ["hover"], style: {background: t("hover")}},
			{slot: "chip", when: ["data-on=true"], style: {borderColor: t("accent")}},
			{slot: "chip", when: ["data-done=true"], style: {background: t("on")}},
			{slot: "starter", style: {padding: 8, borderRadius: Theme.RADIUS_M + 2, background: t("bg"), borderWidth: 1, borderColor: t("line"), cursor: Pointer}},
			{slot: "starter", when: ["hover"], style: {background: t("hover"), borderColor: t("edge")}},
			{slot: "starter", when: ["focus-visible"], style: {outlineWidth: 1, outlineOffset: 1, outlineColor: t("focus")}},
		]),
		light: Theme.light,
		dark: Theme.dark
	};

	public static function view(ws:Workshop):View
		return <view slot="body" flexGrow={1} flexDirection="row" minHeight={0}>
			{sidebar(ws)}
			<view tag="main" flexGrow={1} minWidth={0} flexDirection="column" background={c("bg")}>
				{header(ws)}
				{context(ws)}
				{board(ws)}
				{preview(ws)}
				{status(ws)}
			</view>
			{inspector(ws)}
			{Start.view(ws)}
		</view>;

	static function icon(src:Svg, size = Theme.ICON_S):View
		return <image src={src} width={size} height={size} flexShrink={0}/>;

	// ---- the glyphs

	static function sidebar(ws:Workshop):View
		return <view tag="sidebar" slot="panel" width={SIDEBAR} flexShrink={0} borderWidth="0 1 0 0">
			<view flexDirection="row" alignItems="center" columnGap={8} dragRegion height={Theme.HEADER} padding={'0 ${Theme.PAD}'} flexShrink={0}
				borderWidth="0 0 1 0" borderColor={c("line")}>
				<Show when={WindowButtons.side() == "start"}><view flexDirection="row" alignItems="center" padding="0 6 0 0"><WindowControls/></view></Show>
				<view width={20} height={20} borderRadius={5} background={c("accent")} alignItems="center" justifyContent="center">
					<text color={c("accent-fg")} fontFamily={Draft.FAMILY} fontSize={14} lineHeight="14px">a</text>
				</view>
				<text fontWeight={Theme.MEDIUM}>Foundry</text>
				<view flexGrow={1}/>
				<text fontFamily={Theme.CODE} fontSize={Theme.SMALL} color={c("fg3")} fontVariantNumeric="tabular-nums">{() -> {
					var p = ws.progress();
					'${p.drawn + p.borrowed} / ${p.total}';
				}}</text>
			</view>
			<view padding="8 10 0" flexShrink={0}>
				<view slot="field">
					<text slot="field-label">Find</text>
					<field tag="search" slot="field-input" fontFamily={Theme.UI} aria-label="Find a glyph" placeholder="a letter, U+0142, a name" value={ws.search}
						onInput={e -> ws.search(e.text)}/>
				</view>
			</view>
			<scroll tag="glyphs" flexGrow={1} minHeight={0} padding="8 10 12" rowGap={14}>
				<Show when={ws.search() == ""}>{start(ws)}</Show>
				<For each={() -> [for (g in Charset.of(ws.face())) if (shown(ws, g.chars).length > 0) g.name]}>{(group:Read<String>) -> {
					var name = group();
					var chars = memo(() -> {
						var g = Lambda.find(Charset.of(ws.face()), g -> g.name == name);
						return g == null ? [] : shown(ws, g.chars);
					});
					<view rowGap={6}>
						<view slot="section-head" padding="0 2">
							<text fontSize={Theme.SMALL} flexGrow={1}>{name}</text>
							<text fontSize={Theme.SMALL} color={c("fg3")} fontFamily={Theme.CODE}>{() -> {
								var f = ws.face(), n = 0, all = chars();
								for (ch in all)
									if (Workshop.state(f, ch) != "empty") n++;
								'$n/${all.length}';
							}}</text>
						</view>
						<view display="grid" gridTemplateColumns="repeat(5, minmax(0, 1fr))" columnGap={4} rowGap={4} role="list" aria-label={name}>
							<For each={chars}>{(ch:Read<String>) -> cell(ws, ch())}</For>
						</view>
					</view>;
				}}</For>
			</scroll>
		</view>;

	// a group's glyphs the search finds: a character, its code (U+0142, 0142), a name's part
	static function shown(ws:Workshop, chars:Array<String>):Array<String> {
		var q = StringTools.trim(ws.search()).toLowerCase();
		if (q == "") return chars;
		var hex = StringTools.startsWith(q, "u+") ? q.substr(2) : q;
		var cp = q.length > 2 ? Std.parseInt("0x" + hex) : null;
		return chars.filter(c -> c == q || c.toLowerCase() == q || cp != null && Charset.code(c) == cp || Charset.unencoded(c) && c.toLowerCase().indexOf(q) >= 0);
	}

	// a glyph's label: its character, else its name
	static function label(char:String):String
		return Charset.unencoded(char) ? char.substr(1) : char;

	static function cell(ws:Workshop, char:String):View {
		var state = memo(() -> Workshop.state(ws.face(), char));
		return <button tag={"glyph-" + (Charset.unencoded(char) ? char.substr(1) : Std.string(Charset.code(char)))} slot="cell" role="listitem"
			aria-label={'${label(char)}, ${state()}'}
			data-on={ws.current() == char ? "true" : "false"} onPress={() -> ws.open(char)}>
			<view flexGrow={1} alignSelf="stretch" alignItems="center" justifyContent="center">
				<Show when={state() != "empty"} fallback={<text fontSize={20} color={c("fg3")} opacity={0.45}>{Charset.unencoded(char) ? "" : char}</text>}>
					{thumb(ws, char)}
				</Show>
			</view>
			{glimmer(ws, char)}
			<view flexDirection="row" alignItems="center" columnGap={3} height={12}>
				<text fontSize={10} lineHeight="12px" color={c("fg3")} lineClamp={1} textOverflow="ellipsis" maxWidth={44}>{label(char)}</text>
				<Show when={state() == "borrowed"}><view width={4} height={4} borderRadius={2} background={c("accent-ink")} aria-label="Borrowed"/></Show>
			</view>
		</button>;
	}

	static function glimmer(ws:Workshop, char:String):Node {
		var g = new Glimmer(ws, char);
		renderEffect(() -> ws.touched().get(char), _ -> g.wake());
		return g;
	}

	static function thumb(ws:Workshop, char:String):Node {
		var t = new Thumb(ws, char);
		t.style.alignSelf = Stretch;
		t.style.flexGrow = 1;
		renderEffect(() -> {
			ws.face();
			ws.dark();
		}, _ -> t.char = char);
		return t;
	}

	// the first letters, in order, while some are not drawn
	static function start(ws:Workshop):View {
		var next = memo(() -> {
			var f = ws.face();
			return Lambda.find(Charset.start, ch -> !Model.drawn(f, ch));
		});
		return <Show when={next() != null}>
			<view tag="start" rowGap={8} padding="10" borderRadius={Theme.RADIUS_M} background={c("well")}>
				<view flexDirection="row" alignItems="center" columnGap={6}>
					{icon(Icons.sparkles, 12)}
					<text fontWeight={Theme.MEDIUM} flexGrow={1}>Start with these</text>
					<text fontSize={Theme.SMALL} color={c("fg3")}>{() -> {
						var f = ws.face();
						'${Charset.start.filter(ch -> Model.drawn(f, ch)).length} of ${Charset.start.length}';
					}}</text>
				</view>
				<view flexDirection="row" columnGap={3}>
					<For each={Charset.start}>{(ch:Read<String>) -> {
						var char = ch();
						<button tag={"start-" + char} slot="chip" aria-label={"Draw " + char}
							data-on={ws.current() == char ? "true" : "false"} data-done={Model.drawn(ws.face(), char) ? "true" : "false"}
							onPress={() -> ws.open(char)}>
							<text fontSize={16} color={Model.drawn(ws.face(), char) ? c("accent-ink") : c("fg2")}>{char}</text>
						</button>;
					}}</For>
				</view>
				<text fontSize={Theme.SMALL} color={c("fg2")} lineHeight="16px">{() -> {
					var n = next() ?? "";
					'$n · ${Charset.why.get(n) ?? ""}';
				}}</text>
			</view>
		</Show>;
	}

	// ---- the board

	static function header(ws:Workshop):View
		return <view tag="header" flexDirection="row" alignItems="center" columnGap={8} dragRegion height={Theme.HEADER} flexShrink={0} padding={'0 ${Theme.PAD}'}
			borderWidth="0 0 1 0" borderColor={c("line")}>
			<view flexDirection="row" alignItems="baseline" columnGap={8} minWidth={0} flexShrink={1}>
				<text fontSize={15} fontWeight={Theme.MEDIUM} lineClamp={1}>{() -> label(ws.current())}</text>
				<text color={c("fg3")} fontFamily={Theme.CODE} fontSize={Theme.SMALL}>{() -> unicode(ws.current())}</text>
			</view>
			<Tip label="Letters to see together on the board: press one to open it, the arrows step, Alt and the arrows kern">
				<view slot="field" width={190}>
					<text slot="field-label">Text</text>
					<field tag="line" slot="field-input" fontFamily={Theme.UI} aria-label="Text on the board" placeholder="nanbnc HOHAH" value={ws.line}
						onInput={e -> {
							ws.line(e.text);
							ws.lineAt(-1);
						}}/>
				</view>
			</Tip>
			<view flexGrow={1}/>
			<Show when={ws.layer() == "pen"}>
				<Segmented tag="tool" label="Tool" value={ws.tool} onChange={v -> ws.tool(v)} options={[
					{value: "draw", label: "Draw", icon: Icons.pen, hint: "Draw (P)"},
					{value: "adjust", label: "Adjust", icon: Icons.pointer, hint: "Adjust (V)"},
					{value: "erase", label: "Erase", icon: Icons.eraser, hint: "Erase (E)"}
				]}/>
			</Show>
			<Segmented tag="layer" label="Edit" value={ws.layer} onChange={v -> {
				ws.layer(v);
				ws.points([]);
				ws.selected(null);
			}} options={[{value: "pen", label: "Pen", hint: "Pen lines"}, {value: "outline", label: "Outline", hint: "Outline points"}]}/>
			<view width={1} height={16} background={c("line")}/>
			<Tip label={ws.guide() ? "Hide the tracing letter" : "Show the tracing letter"} keys="T">
				<button tag="guide" slot="button" aria-label="Tracing letter" data-on={ws.guide() ? "true" : "false"}
					onPress={() -> ws.guide(!ws.guide.peek())}>{icon(Icons.eye)}</button>
			</Tip>
		</view>;

	static function unicode(char:String):String
		return Charset.unencoded(char) ? "no character" : "U+" + StringTools.hex(Charset.code(char), 4);

	// under the header: what this letter is, what can be done with it; on
	// the right, what an agent did, else how the tool is used
	static function context(ws:Workshop):View
		return <view tag="context" flexDirection="row" alignItems="center" columnGap={6} height={34} flexShrink={0} padding={'0 ${Theme.PAD}'}
			borderWidth="0 0 1 0" borderColor={c("line")}>
			{icon(Icons.component, 12)}
			<text color={c("fg2")} lineClamp={1} textOverflow="ellipsis" flexShrink={1} minWidth={0} padding="0 4 0 0">{() -> describe(ws)}</text>
			<Switch>
				<Match when={ws.layer() == "pen" && Model.outlined(Model.glyph(ws.face(), ws.current()))}>
					<button tag="trace" slot="button" aria-label="Trace into pen lines" onPress={() -> ws.trace(ws.current())}>
						<text>Trace into pen lines</text>
					</button>
				</Match>
				<Match when={ws.layer() == "outline" && !Model.outlined(Model.glyph(ws.face(), ws.current()))
					&& (Model.glyph(ws.face(), ws.current())?.lines.length ?? 0) > 0}>
					<button tag="bake" slot="button" aria-label="Edit as outline" onPress={() -> ws.bake(ws.current())}>
						<text>Edit as outline</text>
					</button>
				</Match>
				<Match when={Workshop.state(ws.face(), ws.current()) == "borrowed"}>
					<button tag="adopt" slot="button" aria-label="Make it its own" onPress={() -> ws.adopt(ws.current())}>
						<text>Make it its own</text>
					</button>
					<button tag="own" slot="button" aria-label="Draw it myself" onPress={() -> ws.own(ws.current())}>
						<text>Draw it myself</text>
					</button>
				</Match>
			</Switch>
			<view flexGrow={1}/>
			<Show when={ws.agent() != ""} fallback={<text fontSize={Theme.SMALL} color={c("fg3")} lineClamp={1} flexShrink={1} minWidth={0}>{() -> hint(ws)}</text>}>
				<view tag="agent" flexDirection="row" alignItems="center" columnGap={6} transition="fade">
					<image src={Icons.sparkles} width={12} height={12} color={c("violet")}/>
					<text fontSize={Theme.SMALL} color={c("violet")} fontWeight={Theme.MEDIUM}>{ws.agent}</text>
				</view>
			</Show>
			<Tip label={ws.view().fitted ? "Zoom: Cmd/Ctrl and the wheel, or a pinch" : "Fit the letter"} keys={Keys.primary("0")} placement="below">
				<button tag="zoom" slot="button" aria-label="Zoom" data-on={ws.view().fitted ? "false" : "true"} height={22}
					onPress={() -> ws.board?.fit()}>
					<text fontFamily={Theme.CODE} fontSize={Theme.SMALL} fontVariantNumeric="tabular-nums">{() -> Math.round(ws.view().scale * 100) + "%"}</text>
				</button>
			</Tip>
		</view>;

	// what the letter on the board is
	static function describe(ws:Workshop):String {
		var f = ws.face(), char = ws.current(), g = Model.glyph(f, char);
		var lines = g == null ? 0 : g.lines.length, contours = g?.outline?.length ?? 0;
		function count(n:Int, one:String, many:String)
			return '$n ${n == 1 ? one : many}';
		return switch Workshop.state(f, char) {
			case "borrowed": Charset.describe(Charset.parts(f, char));
			case "empty": "Not drawn yet";
			case _ if (contours > 0 && lines > 0): 'Outline, ${count(contours, "contour", "contours")}, and ${count(lines, "pen line", "pen lines")}';
			case _ if (contours > 0): 'Outline, ${count(contours, "contour", "contours")}';
			case _: 'Drawn with the pen, ${count(lines, "line", "lines")}';
		}
	}

	static function board(ws:Workshop):View {
		var area = signal({w: 0.0, h: 0.0});
		return <view tag="board-area" flexGrow={1} minHeight={0} position="relative" overflow="hidden" onResize={e -> area({w: e.target.width, h: e.target.height})}>
			{boardNode(ws)}
			{guides(ws, area)}
			<For each={ws.kerns} keyed={false}>{(l:Read<{x:Float, y:Float, text:String}>) -> <text position="absolute" left={l().x} top={l().y}
				fontFamily={Theme.CODE} fontSize={10} color={c("rose")} pointerEvents="none">{l().text}</text>}</For>
			<For each={ws.measure} keyed={false}>{(l:Read<{x:Float, y:Float, text:String}>) -> <view position="absolute" left={l().x} top={l().y}
				padding="1 5" borderRadius={4} background={c("rose")} pointerEvents="none">
				<text fontFamily={Theme.CODE} fontSize={10} color={c("bg")}>{l().text}</text>
			</view>}</For>
		</view>;
	}

	static function boardNode(ws:Workshop):Node {
		var b = new Board(ws);
		b.style.position = Absolute;
		b.style.inset = 0;
		renderEffect(() -> {
			ws.face();
			ws.current();
			ws.tool();
			ws.selected();
			ws.guide();
			ws.dark();
			ws.agentStroke();
			ws.layer();
			ws.points();
			0;
		}, _ -> b.repaint());
		return b;
	}

	// the guides' names, beside them
	static function guides(ws:Workshop, area:Read<{w:Float, h:Float}>):View
		return <view position="absolute" left={0} top={0} bottom={0} width={110} pointerEvents="none">
			<For each={() -> {
				var f = ws.face(), m = f.metrics, v = ws.view();
				var close = Math.abs(m.ascender - m.capHeight) * v.scale < 16;
				[
					{name: close ? "Capitals, ascenders" : "Ascenders", y: v.base - m.ascender * v.scale - 16},
					{name: "Capitals", y: close ? -100 : v.base - m.capHeight * v.scale - 16},
					{name: "x-height", y: v.base - m.xHeight * v.scale - 16},
					{name: "Baseline", y: v.base - 16},
					{name: "Descenders", y: v.base - m.descender * v.scale + 4}
				];
			}} keyed={false}>{(g:Read<{name:String, y:Float}>) -> <text position="absolute" left={14} top={g().y} fontSize={10} color={c("fg3")}
				opacity={g().y < 0 ? 0 : 1}>{g().name}</text>}</For>
		</view>;

	// ---- the draft font

	static final SAMPLES = ["Hamburgefonstiv", "The quick brown fox jumps over the lazy dog", "Sphinx of black quartz, judge my vow!", "Über café, ¿sí? Ça va."];

	static var sampleField:Null<Node> = null;

	static function preview(ws:Workshop):View
		return <view tag="preview" flexShrink={0} borderWidth="1 0 0 0" borderColor={c("line")} padding={'10 ${Theme.PAD} 12'} rowGap={8}>
			<view flexDirection="row" alignItems="center" columnGap={8}>
				<text slot="section-head" fontSize={Theme.SMALL} flexGrow={1}>Preview</text>
				<view flexDirection="row" columnGap={2}>
					<For each={SAMPLES}>{(s:Read<String>) -> {
						var text = s();
						<button slot="button" aria-label={text} data-on={ws.sample() == text ? "true" : "false"} onPress={() -> {
							ws.sample(text);
							// (shown from its start: the field keeps its caret, at the end of what it had)
							helder.ui.Clock.add(_ -> {
								sampleField?.select(0, 0);
								return false;
							});
						}}>
							<text fontSize={Theme.SMALL}>{text.substr(0, 3)}</text>
						</button>;
					}}</For>
				</view>
				<Segmented tag="size" label="Size" value={() -> Std.string(Std.int(ws.size()))} onChange={v -> ws.size(Std.parseFloat(v))} options={[
					{value: "32", label: "S"},
					{value: "56", label: "M"},
					{value: "96", label: "L"}
				]}/>
			</view>
			<field tag="sample" slot="input" fontFamily={Draft.FAMILY} fontSize={ws.size} aria-label="Preview text" value={ws.sample} placeholder="Type here"
				ref={(n:Node) -> sampleField = n}
				onInput={e -> ws.sample(e.text)}/>
			<text fontFamily={Draft.FAMILY} fontSize={15} lineHeight="22px" color={c("fg2")} lineClamp={1} textOverflow="ellipsis">
				Brave little letters, jumping quickly over 1,234 dozen boxes. ÀÉÎÕÜ àéîõü ç ñ ¿? ¡!
			</text>
		</view>;

	static function status(ws:Workshop):View
		return <view tag="status" flexDirection="row" alignItems="center" columnGap={10} height={24} flexShrink={0} padding={'0 ${Theme.PAD}'}
			borderWidth="1 0 0 0" borderColor={c("line")}>
			<text fontSize={Theme.SMALL} color={c("fg3")} flexGrow={1} lineClamp={1} textOverflow="ellipsis">{ws.status}</text>
			<text fontSize={Theme.SMALL} color={c("fg3")} fontVariantNumeric="tabular-nums">{() -> {
				var p = ws.progress();
				'${p.drawn} drawn, ${p.borrowed} borrowed';
			}}</text>
			<Tip label={ws.mcp() == "" ? "No agent server here" : "Agents connect at " + ws.mcp()} placement="above">
				<view flexDirection="row" alignItems="center" columnGap={5}>
					<view width={6} height={6} borderRadius={3} background={ws.mcp() == "" ? c("fg3") : c("green")}/>
					<text fontSize={Theme.SMALL} color={c("fg3")}>MCP</text>
				</view>
			</Tip>
		</view>;

	// how the tool on the board is used, in a few words
	static function hint(ws:Workshop):String
		return if (ws.layer() == "outline") "Shift picks several · double-click: smooth or corner, a new point · Alt measures" else switch ws.tool() {
			case "adjust": "Double-click a knot for a corner";
			case "erase": "Drag over lines to erase them";
			case _: "Shift draws straight · Alt and the arrows kern";
		}

	// ---- the font's settings

	static function inspector(ws:Workshop):View
		return <view tag="inspector" slot="panel" width={INSPECTOR} flexShrink={0} borderWidth="0 0 0 1">
			<view flexDirection="row" alignItems="center" columnGap={6} dragRegion height={Theme.HEADER}
				padding={'0 ${WindowButtons.side() == "end" ? 0 : Theme.PAD} 0 ${Theme.PAD}'} flexShrink={0} borderWidth="0 0 1 0" borderColor={c("line")}>
				<view flexGrow={1}/>
				<Show when={Workshop.canInstall()}>
					<button tag="install" slot="button" aria-label="Install the font" onPress={ws.install}>
						<text>Install</text>
					</button>
				</Show>
				<button tag="export" slot="primary" aria-label="Export the font" onPress={ws.export}>
					{icon(Icons.download)}<text>Export .ttf</text>
				</button>
				<WindowControls side="end"/>
			</view>
			<scroll flexGrow={1} minHeight={0}>
				<view slot="section" borderWidth="0 0 0 0">
					<view slot="section-head"><text>Font</text></view>
					<view slot="field">
						<text slot="field-label">Name</text>
						<field tag="name" slot="field-input" fontFamily={Theme.UI} aria-label="Font name" value={() -> ws.face().name} onInput={e -> ws.rename(e.text)}/>
					</view>
				</view>
				{languages(ws)}
				{pen(ws)}
				{proportions(ws)}
				{spacing(ws)}
				{agents(ws)}
			</scroll>
		</view>;

	// which languages the font sets, and what each still needs (a missing letter opens)
	static function languages(ws:Workshop):View {
		var all = memo(() -> Languages.of(ws.face()));
		var open = signal(false);
		return <view tag="languages" slot="section">
			<button slot="section-head" aria-label="Languages" onPress={() -> open(!open.peek())}>
				<text flexGrow={1}>Languages</text>
				<text color={c("fg3")} fontWeight={400}>{() -> {
					var ok = all().filter(l -> l.missing.length == 0).length;
					'$ok of ${all().length}';
				}}</text>
				<image src={open() ? Icons.down : Icons.right} width={12} height={12} color={c("fg3")}/>
			</button>
			<Show when={open()}>
				<For each={all} keyed={false}>{(l:Read<{name:String, missing:Array<String>}>) -> <view flexDirection="row" alignItems="center" columnGap={6}
					minHeight={20}>
					<view width={6} height={6} borderRadius={3} background={l().missing.length == 0 ? c("green") : c("sand")}/>
					<text color={c("fg2")} flexGrow={1} minWidth={0}>{l().name}</text>
					<view flexDirection="row" columnGap={2} flexWrap="wrap" justifyContent="end" maxWidth={130}>
						<For each={() -> l().missing.slice(0, 8)} keyed={false}>{(m:Read<String>) -> <button slot="button"
							aria-label={"Open " + m()} height={18} minWidth={18} padding="0 3" onPress={() -> ws.open(m())}>
							<text fontSize={Theme.SMALL}>{m()}</text>
						</button>}</For>
						<Show when={l().missing.length > 8}><text fontSize={Theme.SMALL} color={c("fg3")}>{() -> '+${l().missing.length - 8}'}</text></Show>
					</view>
				</view>}</For>
			</Show>
		</view>;
	}

	static function pen(ws:Workshop):View {
		var p = () -> ws.face().pen;
		function set(next:Pen)
			ws.setPen(next, "pen");
		return <view tag="pen" slot="section">
			<view slot="section-head"><text flexGrow={1}>Pen</text><text color={c("fg3")} fontWeight={400}>{() -> Draft.weightName(p())}</text></view>
			<Segmented tag="preset" label="Pen" value={() -> preset(p())} onChange={name -> {
				var found = Lambda.find(PRESETS, x -> x.name == name);
				if (found != null) ws.setPen(found.pen);
			}} options={[for (x in PRESETS) {value: x.name, label: x.name}]}/>
			<Slider tag="weight" label="Weight" value={() -> p().width} min={20} max={200} step={1} onChange={v -> set({width: v, contrast: p().contrast,
				angle: p().angle, cap: p().cap})}/>
			<Slider tag="contrast" label="Contrast" value={() -> p().contrast * 100} min={0} max={100} step={1} unit="%" onChange={v -> set({width: p().width,
				contrast: v / 100, angle: p().angle, cap: p().cap})}/>
			<Slider tag="angle" label="Angle" value={() -> p().angle} min={-90} max={90} step={1} unit="°" onChange={v -> set({width: p().width,
				contrast: p().contrast, angle: v, cap: p().cap})}/>
			<Segmented tag="ends" label="Ends" value={() -> (p().cap : String)} onChange={v -> ws.setPen({width: p().width, contrast: p().contrast,
				angle: p().angle, cap: v})} options={[{value: "round", label: "Round ends"}, {value: "flat", label: "Flat ends"}]}/>
		</view>;
	}

	static function preset(pen:Pen):String {
		for (x in PRESETS)
			if (x.pen.width == pen.width && x.pen.contrast == pen.contrast && x.pen.angle == pen.angle && x.pen.cap == pen.cap) return x.name;
		return "";
	}

	static function proportions(ws:Workshop):View {
		var m = () -> ws.face().metrics;
		function set(f:Metrics->Metrics)
			ws.setMetrics(f(m()), "metrics");
		return <view tag="proportions" slot="section">
			<view slot="section-head"><text>Proportions</text></view>
			<Slider tag="x-height" label="x-height" value={() -> m().xHeight} min={320} max={640} step={2} onChange={v -> set(x -> {xHeight: v,
				capHeight: x.capHeight, ascender: x.ascender, descender: x.descender, spacing: x.spacing})}/>
			<Slider tag="cap-height" label="Capitals" value={() -> m().capHeight} min={480} max={840} step={2} onChange={v -> set(x -> {xHeight: x.xHeight,
				capHeight: v, ascender: x.ascender, descender: x.descender, spacing: x.spacing})}/>
			<Slider tag="ascender" label="Ascenders" value={() -> m().ascender} min={560} max={900} step={2} onChange={v -> set(x -> {xHeight: x.xHeight,
				capHeight: x.capHeight, ascender: v, descender: x.descender, spacing: x.spacing})}/>
			<Slider tag="descender" label="Descenders" value={() -> -m().descender} min={120} max={380} step={2} onChange={v -> set(x -> {xHeight: x.xHeight,
				capHeight: x.capHeight, ascender: x.ascender, descender: -v, spacing: x.spacing})}/>
			<Slider tag="spacing" label="Spacing" value={() -> m().spacing} min={0} max={200} step={1} onChange={v -> set(x -> {xHeight: x.xHeight,
				capHeight: x.capHeight, ascender: x.ascender, descender: x.descender, spacing: v})}/>
		</view>;
	}

	static function spacing(ws:Workshop):View {
		var g = () -> {
			ws.face();
			return ws.glyph(ws.current());
		};
		return <view tag="glyph" slot="section">
			<view slot="section-head"><text flexGrow={1}>{() -> 'Glyph ${ws.current()}'}</text></view>
			<view slot="fields" flexDirection="row" columnGap={6}>
				<Slider tag="left" label="Left" value={() -> g().left ?? 0} min={-150} max={150} step={1} onChange={v -> ws.setSpacing(ws.current(), v,
					g().right ?? 0, "space")}/>
				<Slider tag="right" label="Right" value={() -> g().right ?? 0} min={-150} max={150} step={1} onChange={v -> ws.setSpacing(ws.current(),
					g().left ?? 0, v, "space")}/>
			</view>
			<view flexDirection="row" columnGap={4}>
				<button tag="clear" slot="button" aria-label="Clear this glyph" onPress={() -> ws.clear(ws.current())}>
					{icon(Icons.trash, 12)}<text>Clear</text>
				</button>
			</view>
		</view>;
	}

	static function agents(ws:Workshop):View
		return <view tag="agents" slot="section">
			<view slot="section-head">{icon(Icons.sparkles, 12)}<text>Draw with an agent</text></view>
			<Show when={ws.mcp() != ""} fallback={<text color={c("fg3")} lineHeight="17px">Agents connect to the desktop app over MCP.</text>}>
				<text color={c("fg2")} lineHeight="17px">Add Foundry to any agent that speaks MCP, as an HTTP server, then ask it for letters. Its strokes are written out here, in violet, and undo like yours.</text>
				<view padding="6 8" borderRadius={Theme.RADIUS} background={c("well")}>
					<text fontFamily={Theme.CODE} fontSize={Theme.SMALL} color={c("fg2")} userSelect="text" selectable>{ws.mcp}</text>
				</view>
			</Show>
		</view>;
}

// shortcuts as the system writes them
class Keys {
	public static function primary(key:String):String
		return (helder.ui.actions.Keymap.mac ? "⌘" : "Ctrl+") + key;
}
