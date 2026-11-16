// title: Rewind Regiment
// summary: Toy soldiers fight by themselves on a play tray; lose, drag the timeline back to where it went wrong, change one thing (send a squad, roll the marble, tip the dominoes, start the train, pop the jack-in-the-box, push the tower, fling the eraser) and watch the battle play out anew. Seventeen levels in six rooms: grunts, riflemen, bazookas, tin tanks, jeeps, helicopters and wind-up robots, deterministic physics (helder.physics' snapshots), photo-real toys modelled in code under a tilt-shift lens
// tags: 3d, physics, game, showcase
// demo: canvas 390x780
import Sim;
import helder.scene.view.SceneTags.*;
import helder.ui.Clock;
import helder.ui.StyleSheet;
import helder.ui.Transform;
import helder.ui.draw.UiWindow;
import helder.ui.draw.UiWindow.Surface;
import helder.view.*;
import helder.view.Flow.*;
import helder.view.graph.Graph.*;

// The window: the <Scene> (the tray, drawn by helder.scene in half floats
// with bloom and a tilt-shift lens: Game) under an input layer that takes
// the touches on the field, and the HUD in ui's markup over both: the title,
// the campaign, the briefing, the battle's bar (who is ahead), the squads'
// badges and the props' tags where they stand, the timeline (a graph of who
// was ahead, the run before the last change as a line; dragged to go back)
// and the report at the end. The look is the toy box's: olive crates and
// stencils (Black Ops One), kraft-paper briefings and masking tape (Oswald),
// dog tags for the levels, medals for how well each went (OFL, fonts/).
class RewindRegiment implements Markup {
	static inline var INK = "#1d2210";
	static inline var OLIVE = "#4f5f28";
	static inline var OLIVE_DARK = "#2c3514";
	static inline var KHAKI = "#d8c895";
	static inline var KRAFT = "#d2ab72";
	static inline var TAPE = "#f2e8c9";
	static inline var BLUE = "#2f6bd8";
	static inline var RED = "#d8402f";
	static inline var GOLD = "#ffb21a";
	static inline var ORANGE = "#ff7f1f";
	static inline var STENCIL = "Black Ops One";
	static inline var TEXT = "Oswald";

	@:nullSafety(Loose)
	static function main() {
		fonts();
		var game = new Game();
		Clock.add(t -> {
			game.frame(t);
			true;
		});
		UiWindow.run(<Surface title="Rewind Regiment" width={390} height={780} theme={sheet}>
			{view(game)}
		</Surface>);
	}

	static var fontsAdded = false;

	public static function fonts() {
		if (fontsAdded) return;
		fontsAdded = true;
		try helder.text.SystemFonts.get().add(helder.asset.Asset.embed("fonts/BlackOpsOne.ttf")) catch (_:Dynamic) {}
		try helder.text.SystemFonts.get().add(helder.asset.Asset.embed("fonts/Oswald.ttf")) catch (_:Dynamic) {}
	}

	static final sheet:StyleSheet = {
		rules: [
			{slot: "pop", when: ["starting"], style: {opacity: 0, transform: Transform.parse("scale(0.7) rotate(-8deg)")}},
			{slot: "rise", when: ["starting"], style: {opacity: 0, transform: Transform.parse("translate(0, 30px)")}},
			{slot: "drop", when: ["starting"], style: {opacity: 0, transform: Transform.parse("translate(0, -40px) rotate(-6deg)")}},
			{slot: "button", when: ["active"], style: {transform: Transform.parse("translate(0, 3px)")}},
			{slot: "button", when: ["hover"], style: {opacity: 0.94}},
			{slot: "medal", when: ["starting"], style: {opacity: 0, transform: Transform.parse("translate(0, -60px) rotate(-30deg)")}},
			{slot: "fade", when: ["starting"], style: {opacity: 0}}
		]
	};

	@:nullSafety(Off)
	public static function view(game:Game):View
		return <view grow={1} background={OLIVE_DARK} font-family={TEXT} color={INK}>
			<Scene grow={1} world={game.world} camera={game.camera} hdr animate setup={game.setup} ref={game.attach}/>
			<view position="absolute" left={0} top={0} right={0} bottom={0} cursor="pointer" onPointerDown={e -> {
				e.current.capture();
				game.down(e.localX, e.localY);
			}} onPointerMove={e -> game.move(e.localX, e.localY)} onPointerUp={e -> game.up(e.localX, e.localY)} onPointerCancel={_ -> game.cancel()}/>
			<Hud game={game}/>
			<view position="absolute" left={0} top={0} right={0} bottom={0} pointer-events="none" background={OLIVE_DARK} opacity={game.ready() ? 0.0 : 1.0}
				transition="opacity 0.4s ease-in-out" align-items="center" justify="center" row-gap={10}>
				<text font-family={STENCIL} font-size={26} color={TAPE} letter-spacing={2}>UNPACKING THE TOYS</text>
				<view width={140} height={8} radius={2} background={"repeating-linear-gradient(45deg, " + GOLD + " 0px, " + GOLD + " 8px, " + INK + " 8px, " + INK + " 16px)"}/>
			</view>
		</view>;

	// ---- pieces

	// a medal: its ribbon in the two sides' colours and white, a brass disc with a star
	static function starPoints(cx:Float, cy:Float, r:Float):String
		return [for (k in 0...10) {
			var a = -Math.PI / 2 + k * Math.PI / 5, d = k % 2 == 0 ? r : r * 0.42;
			(Math.round((cx + Math.cos(a) * d) * 100) / 100) + "," + (Math.round((cy + Math.sin(a) * d) * 100) / 100);
		}].join(" ");

	static final medalFull = helder.ui.Svg.parse('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 30">'
		+ '<path d="M6 0h4l3 13h-4z" fill="$BLUE"/><path d="M14 0h4l-3 13h-4z" fill="$RED"/><path d="M10 0h4l-1 9h-2z" fill="#ffffff"/>'
		+ '<circle cx="12" cy="20" r="8.6" fill="#b77d0c"/><circle cx="12" cy="19.4" r="8" fill="$GOLD"/>'
		+ '<circle cx="12" cy="19.4" r="6" fill="none" stroke="#c98a0e" stroke-width="1"/>'
		+ '<polygon points="${starPoints(12, 19.6, 4.4)}" fill="#fff3c4"/></svg>');
	static final medalEmpty = helder.ui.Svg.parse('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 30">'
		+ '<path d="M6 0h12l-3 13h-6z" fill="#000000" fill-opacity="0.14"/>'
		+ '<circle cx="12" cy="19.4" r="8" fill="#000000" fill-opacity="0.16"/>'
		+ '<polygon points="${starPoints(12, 19.6, 4.4)}" fill="#000000" fill-opacity="0.14"/></svg>');
	static final lock = helder.ui.Svg.parse('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path d="M7.5 10.5V8a4.5 4.5 0 0 1 9 0v2.5" fill="none" stroke="#d6d9dd" stroke-width="2.4" stroke-linecap="round"/><rect x="4.5" y="10" width="15" height="11" rx="2" fill="#d6d9dd"/><circle cx="12" cy="15.2" r="1.7" fill="#4a4f57"/></svg>');
	static final playIcon = helder.ui.Svg.parse('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path d="M8 5.5v13l10.5-6.5z" fill="$INK" stroke="$INK" stroke-width="1.5" stroke-linejoin="round"/></svg>');
	static final pauseIcon = helder.ui.Svg.parse('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><rect x="6.5" y="5.5" width="4" height="13" rx="1" fill="$INK"/><rect x="13.5" y="5.5" width="4" height="13" rx="1" fill="$INK"/></svg>');

	static function hazard(a:String, b:String, w = 8):String
		return 'repeating-linear-gradient(45deg, $a 0px, $a ${w}px, $b ${w}px, $b ${w * 2}px)';

	static function Medals(props:{n:Int, size:Float}):View
		return <view direction="row" column-gap={2} align-items="center">
			{[for (i in 0...3) <image width={props.size} height={props.size * 1.25} src={props.n > i ? medalFull : medalEmpty}/>]}
		</view>;

	// a chunky plastic button, pressed down under the finger: go (orange), blue, or khaki
	static function Button(props:{label:String, onPress:Void->Void, ?kind:String, ?wide:Bool, ?small:Bool}):View {
		var kind = props.kind ?? "plain";
		var bg = kind == "go" ? ORANGE : kind == "blue" ? BLUE : KHAKI;
		var edge = kind == "go" ? "#a8470a" : kind == "blue" ? "#173c86" : "#8f7e4c";
		return <view:button slot="button" role="button" focusable pointer-events="auto" cursor="pointer" padding={props.small == true ? "9 16 7 16" : "13 26 11 26"}
			radius={8} min-width={props.wide == true ? 220 : 0} align-items="center" background={bg} color={kind == "blue" ? "#ffffff" : INK}
			border-width={2} border-color={INK} shadow={'0 4 0 $edge'} font-family={STENCIL} font-size={props.small == true ? 15 : 19} letter-spacing={1.2}
			transition="transform 0.08s ease-out" onPress={props.onPress}>{props.label.toUpperCase()}</view:button>;
	}

	// ---- the HUD

	static function Hud(props:{game:Game}):View {
		var g = props.game;
		return <view position="absolute" left={0} top={0} right={0} bottom={0} pointer-events="none">
			<Show when={(g.screen() == "battle" || g.screen() == "deploy") && !g.replaying()}>
				<Markers game={g}/>
			</Show>
			<Show when={g.replaying()}>
				<Replay game={g}/>
			</Show>
			<view position="absolute" left={0} top={0} right={0} bottom={0} pointer-events="none"
				padding-top="calc(env(safe-area-inset-top) + 10px)" padding-bottom="calc(env(safe-area-inset-bottom) + 12px)"
				padding-left="max(12px, env(safe-area-inset-left))" padding-right="max(12px, env(safe-area-inset-right))">
				<Show when={(g.screen() == "battle" || g.screen() == "deploy") && !g.replaying()}>
					<TopBar game={g}/>
				</Show>
				<view grow={1} align-items="center" justify="center">
					<Show when={g.screen() == "battle" && g.card()}>
						<Card game={g}/>
					</Show>
				</view>
				<Show when={g.screen() == "deploy"}>
					<Deploy game={g}/>
				</Show>
				<Show when={g.screen() == "battle" && !g.replaying()}>
					<Timeline game={g}/>
				</Show>
			</view>
			<Show when={g.screen() == "title"}>
				<Title game={g}/>
			</Show>
			<Show when={g.screen() == "levels"}>
				<LevelSelect game={g}/>
			</Show>
		</view>;
	}

	// a won battle shown again: letterboxed, its label stamped on, a touch skips it
	static function Replay(props:{game:Game}):View {
		return <view position="absolute" left={0} top={0} right={0} bottom={0} pointer-events="none" justify="space-between">
			<view slot="drop" transition="opacity 0.4s ease-out, transform 0.5s ease-out" height="13%" background={INK} justify="flex-end" align-items="center"
				padding-bottom={8}>
				<text font-family={STENCIL} font-size={22} color={GOLD} letter-spacing={4}>VICTORY REPLAY</text>
			</view>
			<view slot="rise" transition="opacity 0.4s ease-out, transform 0.5s ease-out" height="11%" background={INK} align-items="center" padding-top={10}>
				<text font-size={14} font-weight={500} color={TAPE} letter-spacing={1}>Tap to skip</text>
			</view>
		</view>;
	}

	// the level's dog tag, the orders given, who is ahead, what to do now
	static function TopBar(props:{game:Game}):View {
		var g = props.game;
		var blue = memo(() -> {
			g.tick();
			g.sim.count(0);
		});
		var red = memo(() -> {
			g.tick();
			g.sim.count(1);
		});
		var share = memo(() -> {
			var b = blue(), r = red();
			b + r == 0 ? 0.5 : b / (b + r);
		});
		return <view row-gap={8}>
			<view direction="row" align-items="center" column-gap={8}>
				<view:button slot="button" role="button" pointer-events="auto" cursor="pointer" direction="row" align-items="center" column-gap={8}
					padding="4 14 4 6" radius={14} background="linear-gradient(170deg, #eef0f2, #a9afb7)" border-width={1.5} border-color="#6e757e"
					shadow="0 3 0 #50565e" transition="transform 0.08s ease-out" onPress={() -> g.screen("levels")}>
					<view width={10} height={10} radius={5} background="#50565e" margin-right={2}/>
					<text font-family={STENCIL} font-size={20} color="#2e333a">{"" + (g.levelIndex() + 1)}</text>
					<text font-size={15} font-weight={600} color="#2e333a">{Levels.levels[g.levelIndex()].name.toUpperCase()}</text>
				</view:button>
				<view grow={1}/>
				<Show when={g.screen() == "battle"}>
					<view direction="row" align-items="center" column-gap={6} padding="5 10" radius={6} background={KHAKI} border-width={2} border-color={INK}>
						<text font-size={12} font-weight={600} color={INK} letter-spacing={1}>ORDERS</text>
						<text font-family={STENCIL} font-size={18}>{"" + {
							g.tick();
							g.sim.orders.length;
						}}</text>
					</view>
				</Show>
			</view>
			<view height={30} radius={6} background={INK} padding={3} direction="row" shadow="0 3 8 #00000040">
				<view width={(share() * 100) + "%"} radius={3} background={"linear-gradient(180deg, #5b8ef0, " + BLUE + ")"} justify="center" padding-left={8}>
					<text font-family={STENCIL} font-size={16} color="#ffffff">{"" + blue()}</text>
				</view>
				<view width={3} background={GOLD}/>
				<view grow={1} radius={3} background={"linear-gradient(180deg, #f07a5c, " + RED + ")"} justify="center" align-items="flex-end" padding-right={8}>
					<text font-family={STENCIL} font-size={16} color="#ffffff">{"" + red()}</text>
				</view>
			</view>
			<Show when={hint(g) != ""}>
				<view align-items="center" margin-top={4}>
					<view slot="pop" transition="opacity 0.2s ease-out, transform 0.25s ease-out" padding="6 14" background={TAPE} transform="rotate(-1.5deg)"
						shadow="0 2 4 #00000040">
						<text font-size={15} font-weight={500} color={INK} text-align="center">{hint(g)}</text>
					</view>
				</view>
			</Show>
		</view>;
	}

	static function hint(g:Game):String {
		g.tick();
		var s = g.screen(), sel = g.selected();
		if (s == "deploy") return g.moving >= 0 ? "Let go where they should stand" : "Drag your squads into place";
		if (s != "battle") return "";
		if (g.card()) return "";
		var sim = g.sim;
		if (sel >= Sim.PROP) return "Tap where to " + Game.verb(sim.props[sel - Sim.PROP].def.type).toLowerCase() + " it  ·  time slowed";
		if (sel >= 0) return "Tap where squad " + String.fromCharCode(65 + sel) + " goes  ·  time slowed";
		if (g.downOn >= 0) return "Let go where it should go";
		if (sim.over()) return sim.won() ? "" : "Drag the timeline back to where it went wrong";
		if (!g.playing() && !sim.over() && sim.step > 0 && laterOrders(sim)) return "Play on from here and your orders after it are undone";
		if (!g.playing() && sim.step == 0 && sim.started) return g.moving >= 0 ? "Let go where they should stand" : "Back at the start: drag squads to new places";
		if (!g.playing()) return "Drag a squad to steer it, or tap a toy";
		return "";
	}

	static function laterOrders(sim:Sim):Bool {
		for (o in sim.orders)
			if (o.step >= sim.step) return true;
		return false;
	}

	// the squads' badges and the props' tags, where they stand on the field
	static function Markers(props:{game:Game}):View {
		var g = props.game;
		return <view position="absolute" left={0} top={0} right={0} bottom={0} pointer-events="none">
			{{
				g.levelIndex();
				g.screen();
				var ns = g.sim.sqTeam.length;
				[for (k in 0...ns + g.sim.props.length) <Leader game={g} k={k} color={k >= ns ? INK : g.sim.sqTeam[k] == 0 ? "#ffffff" : "#ffd9d2"}/>]
					.concat([for (s in 0...ns) <Badge game={g} s={s}/>])
					.concat([for (p in g.sim.props) <PropMark game={g} p={p.index}/>]);
			}}
			<Guides game={g}/>
		</view>;
	}

	// the paths over the field: dots to where each squad was sent, a flag there; gold to the finger
	static final flagBlue = helder.ui.Svg.parse('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 30 40"><ellipse cx="5" cy="37" rx="5" ry="2.5" fill="#000000" fill-opacity="0.35"/><rect x="3.5" y="2" width="3" height="35" rx="1.5" fill="$INK"/><path d="M6 3h21l-5 7 5 7H6z" fill="$BLUE" stroke="#ffffff" stroke-width="1.5" stroke-linejoin="round"/></svg>');
	static final flagGold = helder.ui.Svg.parse('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 30 40"><ellipse cx="5" cy="37" rx="5" ry="2.5" fill="#000000" fill-opacity="0.35"/><rect x="3.5" y="2" width="3" height="35" rx="1.5" fill="$INK"/><path d="M6 3h21l-5 7 5 7H6z" fill="$GOLD" stroke="$INK" stroke-width="1.5" stroke-linejoin="round"/></svg>');

	static function Guides(props:{game:Game}):View {
		var g = props.game;
		function dot(k:Int):View {
			var v = memo(() -> {
				g.tick();
				var a = g.guides;
				k * 3 < a.length ? {x: a[k * 3], y: a[k * 3 + 1], gold: a[k * 3 + 2] > 0, on: true} : {x: -50.0, y: -50.0, gold: false, on: false};
			});
			return <view position="absolute" left={v().x - 6} top={v().y - 4} width={12} height={8} radius={4} background={v().gold ? GOLD : "#ffffff"}
				border-width={2} border-color={v().gold ? INK : BLUE} opacity={v().on ? 1.0 : 0.0}/>;
		}
		function flag(k:Int):View {
			var v = memo(() -> {
				g.tick();
				var a = g.flagsAt;
				k * 3 < a.length ? {x: a[k * 3], y: a[k * 3 + 1], gold: a[k * 3 + 2] > 0, on: true} : {x: -80.0, y: -80.0, gold: false, on: false};
			});
			return <image position="absolute" left={v().x - 5} top={v().y - 37} width={30} height={40} src={v().gold ? flagGold : flagBlue}
				opacity={v().on ? 1.0 : 0.0}/>;
		}
		return <view position="absolute" left={0} top={0} right={0} bottom={0} pointer-events="none">
			{[for (k in 0...Game.GUIDES) dot(k)]}
			{[for (k in 0...6) flag(k)]}
		</view>;
	}

	// the line from a label to what it names (under the label: from its edge on)
	static function Leader(props:{game:Game, k:Int, color:String}):View {
		var g = props.game, k = props.k;
		var v = memo(() -> {
			g.tick();
			var l = g.label(k), dx = l.ax - l.x, dy = l.ay - l.y, len = Math.sqrt(dx * dx + dy * dy);
			{x: (l.x + l.ax) / 2, y: (l.y + l.ay) / 2, len: len, a: Math.atan2(dy, dx) * 180 / Math.PI, on: l.on && len > 16};
		});
		return <view position="absolute" left={v().x - v().len / 2} top={v().y - 1} width={v().len} height={2} radius={1} background={props.color}
			opacity={v().on ? 0.9 : 0.0} transform={"rotate(" + v().a + "deg)"} shadow="0 1 2 #00000060"/>;
	}

	static function Badge(props:{game:Game, s:Int}):View {
		var g = props.game, s = props.s;
		var mine = g.sim.sqTeam[s] == 0;
		var n = memo(() -> {
			g.tick();
			g.sim.standing(s);
		});
		var at = memo(() -> {
			g.tick();
			g.label(s);
		});
		var chosen = memo(() -> {
			g.tick();
			g.selected() == s || g.downOn == s || g.moving == s;
		});
		var marching = memo(() -> {
			g.tick();
			g.sim.started && g.sim.heading(s) != null;
		});
		var label = mine ? String.fromCharCode(65 + s) : "";
		var kind = g.sim.sqKind[s];
		return <view position="absolute" left={at().x - 50} top={at().y - 13} width={100} align-items="center" opacity={n() > 0 ? 1.0 : 0.0}
			transition="opacity 0.3s ease-out">
			<view direction="row" align-items="center" column-gap={5} padding="1 7 1 3" radius={5} background={chosen() ? GOLD : mine ? BLUE : RED}
				border-width={1.5} border-color={chosen() ? INK : "#ffffffa0"} shadow="0 2 4 #00000050" transform={chosen() ? "scale(1.22)" : "none"}
				transition="transform 0.15s ease-out">
				<Show when={mine}>
					<view width={20} height={20} radius={3} background={chosen() ? INK : "#ffffff"} align-items="center" justify="center">
						<text font-family={STENCIL} font-size={14} color={chosen() ? GOLD : BLUE}>{label}</text>
					</view>
				</Show>
				<text font-size={13} font-weight={600} color={chosen() ? INK : "#ffffff"}>{icon(kind) + " " + n()}</text>
			</view>
			<Show when={mine && marching() && !chosen()}>
				<text font-size={11} font-weight={700} color="#ffffff" letter-spacing={1} text-shadow="0 1 2 #000000c0" margin-top={2}>ON THE MOVE</text>
			</Show>
		</view>;
	}

	static function icon(kind:Int):String
		return ["⚔", "◎", "▣", "➤", "✈", "✸", "⚙"][kind];

	// a prop's tag (blue's, not yet used) or warning (red's, counting down)
	static function PropMark(props:{game:Game, p:Int}):View {
		var g = props.game, pi = props.p;
		var p = g.sim.props[pi];
		var mine = p.def.team == 0;
		var at = memo(() -> {
			g.tick();
			g.label(g.sim.sqTeam.length + pi);
		});
		var shown = memo(() -> {
			g.tick();
			g.screen() == "battle" && p.firedAt < 0 && (mine || p.def.at - g.sim.step < 60 * 4);
		});
		var chosen = memo(() -> {
			g.tick();
			g.selected() == Sim.PROP + pi || g.downOn == Sim.PROP + pi;
		});
		var label = memo(() -> {
			g.tick();
			mine ? Game.verb(p.def.type).toUpperCase() : "IN " + Math.max(0, Math.ceil((p.def.at - g.sim.step) / 60));
		});
		return <view position="absolute" left={at().x - 44} top={at().y - 13} width={88} align-items="center" opacity={shown() ? 1.0 : 0.0}
			transition="opacity 0.25s ease-out">
			<view padding="3 10 2 10" radius={4} background={mine ? (chosen() ? GOLD : TAPE) : hazard(RED, "#a8261a", 6)} border-width={2}
				border-color={mine ? INK : "#ffffff"} shadow="0 3 0 #00000050" transform={chosen() ? "scale(1.18)" : "rotate(-2deg)"} transition="transform 0.15s ease-out">
				<text font-family={STENCIL} font-size={14} color={mine ? INK : "#ffffff"} letter-spacing={1}>{label()}</text>
			</view>
		</view>;
	}

	// before the battle: the briefing on its clipboard, Fight
	static function Deploy(props:{game:Game}):View {
		var g = props.game;
		var level = memo(() -> Levels.levels[g.levelIndex()]);
		return <view align-items="center" row-gap={14}>
			<view slot="rise" transition="opacity 0.4s ease-out, transform 0.5s ease-out" padding="20 18 18 18" radius={4}
				background={"linear-gradient(175deg, #e6c792, " + KRAFT + ")"} border-width={1} border-color="#9c7840" shadow="0 8 18 #00000050"
				max-width={360} row-gap={6} align-items="center">
				<view position="absolute" top={-9} left="50%" margin-left={-36} width={72} height={18} radius={4} background="linear-gradient(180deg, #8d949c, #4f555c)"
					border-width={1} border-color="#33373c"/>
				<text font-family={STENCIL} font-size={13} color="#6b4c1e" letter-spacing={2}>{"BRIEFING · LEVEL " + (g.levelIndex() + 1) + " · " + Levels.settings[level().setting].name.toUpperCase()}</text>
				<text font-size={17} font-weight={500} text-align="center" color={INK}>{level().hint}</text>
				<Show when={g.best()[g.levelIndex()] > 0}>
					<view direction="row" align-items="center" column-gap={6} margin-top={2}>
						<text font-size={12} font-weight={600} color="#5a4220" letter-spacing={1}>YOUR BEST</text>
						<Medals n={g.best()[g.levelIndex()]} size={16}/>
					</view>
				</Show>
			</view>
			<Button label="Fight!" kind="go" wide onPress={g.begin}/>
		</view>;
	}

	// the timeline: play or pause, the graph of who was ahead (dragged: back to then), the moment
	static function Timeline(props:{game:Game}):View {
		var g = props.game;
		var dragging = false;
		var graph = memo(() -> {
			g.tick();
			var sim = g.sim;
			// (redrawn as it grows: every half second of the battle, or when the ghost changes)
			graphOf(sim, Std.int(sim.recorded / 30), sim.ghost.length);
		});
		var at = memo(() -> {
			g.tick();
			g.sim.step / g.sim.span();
		});
		var marks = memo(() -> {
			g.tick();
			var sim = g.sim, span = sim.span();
			// (yours after the moment, paused there: faint, undone once it plays on)
			var undone = !g.playing();
			var list:Array<{f:Float, red:Bool, later:Bool}> = [for (o in sim.orders) {f: o.step / span, red: false, later: undone && o.step >= sim.step}];
			for (p in sim.props)
				if (p.def.team == 1) list.push({f: p.def.at / span, red: true, later: false});
			list;
		});
		return <view row-gap={0}>
			<view height={6} margin="0 14" radius="3 3 0 0" background={hazard(GOLD, INK, 6)}/>
			<view direction="row" align-items="center" column-gap={10} padding="8 10" radius={10} background="#1d2210f2" border-width={2} border-color={OLIVE}
				shadow="0 6 18 #00000060" pointer-events="auto">
				<view:button slot="button" role="button" cursor="pointer" width={48} height={48} radius={8} background={g.playing() ? GOLD : ORANGE}
					border-width={2} border-color={INK} shadow="0 3 0 #00000080" align-items="center" justify="center" transition="transform 0.08s ease-out"
					onPress={g.togglePlay}>
					<image width={26} height={26} src={g.playing() ? pauseIcon : playIcon}/>
				</view:button>
				<view grow={1} height={54} cursor="ew-resize" onPointerDown={e -> {
					dragging = true;
					e.current.capture();
					g.scrub(e.localX / Math.max(1, e.current.width));
				}} onPointerMove={e -> if (dragging) g.scrub(e.localX / Math.max(1, e.current.width))} onPointerUp={_ -> dragging = false}
					onPointerCancel={_ -> dragging = false}>
					<view position="absolute" left={0} top={0} right={0} bottom={0} radius={4} background="#ffffff10"/>
					<image position="absolute" left={0} top={0} right={0} bottom={0} src={graph()}/>
					{{
						[for (m in marks()) <view position="absolute" left={(m.f * 100) + "%"} top={m.red ? 0 : 42} width={m.red ? 2 : 10} height={m.red ? 54 : 10}
							margin-left={m.red ? -1 : -5} radius={m.red ? 1 : 2} background={m.red ? "#ff8a70c0" : GOLD} border-width={m.red ? 0 : 1.5} border-color={INK}
							opacity={m.later ? 0.35 : 1.0}/>];
					}}
					<view position="absolute" left={(at() * 100) + "%"} top={-8} bottom={-8} width={14} margin-left={-7} align-items="center">
						<view width={14} height={10} radius={2} background={TAPE}/>
						<view width={3} grow={1} background={TAPE}/>
						<view width={14} height={10} radius={2} background={TAPE}/>
					</view>
				</view>
			</view>
		</view>;
	}

	// the graph: who was ahead (blue up, red down), the ghost's line over it
	static var graphKey = "";
	static var graphLast:Null<helder.ui.Svg> = null;

	static function graphOf(sim:Sim, version:Int, ghost:Int):helder.ui.Svg {
		var key = '$version/$ghost/${sim.ahead.length}/${sim.span()}';
		var last = graphLast;
		if (key == graphKey && last != null) return last;
		graphKey = key;
		var w = 400.0, h = 54.0, mid = h / 2;
		var span = sim.span(), n = sim.ahead.length;
		inline function xOf(k:Int):Float
			return k * Sim.KEY / span * w;
		inline function amp(a:Float):Float
			return (a < 0 ? -Math.min(1, -a * 2.5) : Math.min(1, a * 2.5)) * (mid - 3);
		var up = new StringBuf(), down = new StringBuf();
		up.add('M0 $mid ');
		down.add('M0 $mid ');
		for (k in 0...n) {
			var a = amp(sim.ahead[k]);
			up.add('L${xOf(k)} ${mid - Math.max(0, a)} ');
			down.add('L${xOf(k)} ${mid - Math.min(0, a)} ');
		}
		var end = n > 0 ? xOf(n - 1) : 0;
		up.add('L$end $mid Z');
		down.add('L$end $mid Z');
		var ghostPath = new StringBuf();
		for (k in 0...sim.ghost.length)
			ghostPath.add((k == 0 ? "M" : "L") + '${xOf(k)} ${mid - amp(sim.ghost[k])} ');
		var svg = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 $w $h" preserveAspectRatio="none">'
			+ '<line x1="0" y1="$mid" x2="$w" y2="$mid" stroke="#ffffff" stroke-opacity="0.25" stroke-width="1"/>'
			+ '<path d="${up.toString()}" fill="$BLUE"/><path d="${down.toString()}" fill="$RED"/>'
			+ (sim.ghost.length > 1 ? '<path d="${ghostPath.toString()}" fill="none" stroke="$TAPE" stroke-opacity="0.9" stroke-width="2" stroke-dasharray="5 4"/>' : "")
			+ '</svg>';
		var s = helder.ui.Svg.parse(svg);
		graphLast = s;
		return s;
	}

	// the end: the report, stamped; the medals; how it went before the last change
	static function Card(props:{game:Game}):View {
		var g = props.game, sim = g.sim;
		var o = sim.outcome(), b = sim.before;
		var medals = o.won ? Game.starsFor(o.orders, o.blue, sim.army(0)) : 0;
		var last = g.levelIndex.peek() == Levels.levels.length - 1;
		var stamp = o.won ? "#2f7d32" : RED;
		function medal(k:Int):View {
			var d = 0.35 + k * 0.22;
			return <view slot={medals > k ? "medal" : "fade"} transition={'opacity 0.2s ease-out ${d}s, transform 0.5s cubic-bezier(0.34, 1.56, 0.64, 1) ${d}s'}>
				<image width={44} height={55} src={medals > k ? medalFull : medalEmpty}/>
			</view>;
		}
		return <view slot="pop" transition="opacity 0.3s ease-out, transform 0.4s cubic-bezier(0.34, 1.4, 0.64, 1)" pointer-events="auto" align-items="center"
			row-gap={10} padding="22 24 18 24" radius={4} background={"linear-gradient(175deg, #e6c792, " + KRAFT + ")"} border-width={1} border-color="#9c7840"
			shadow="0 14 34 #00000060" max-width={340}>
			<text font-family={STENCIL} font-size={13} color="#6b4c1e" letter-spacing={2}>{"REPORT · LEVEL " + (g.levelIndex.peek() + 1)}</text>
			<view padding="4 16 2 16" radius={6} border-width={4} border-color={stamp} transform="rotate(-5deg)">
				<text font-family={STENCIL} font-size={40} color={stamp} letter-spacing={2}>{o.won ? "VICTORY" : o.blue == 0 ? "DEFEAT" : "TIME'S UP"}</text>
			</view>
			<Show when={o.won}>
				<view direction="row" column-gap={8} align-items="flex-start">{medal(0)}{medal(1)}{medal(2)}</view>
			</Show>
			<text font-size={16} font-weight={500} text-align="center" color={INK}>{o.won ? o.blue + " of your soldiers still standing · " + o.orders + (o.orders == 1 ? " order" : " orders") : "Red has " + o.red + " left. Every battle can be turned."}</text>
			<Show when={!o.won}>
				<text font-size={14} font-weight={400} color="#5a4220" text-align="center">Rewind goes to just before it went wrong. Then steer a squad or set off a toy.</text>
			</Show>
			<Show when={b != null}>
				<text font-size={14} font-weight={400} color="#5a4220" text-align="center">{b == null ? "" : "Before your last change: " + (b.won ? "won with " + b.blue + " left" : "lost, red had " + b.red + " left")}</text>
			</Show>
			<Show when={o.won && o.orders > 1}>
				<text font-size={14} font-weight={400} color="#5a4220" text-align="center">One single order can win this. Three medals for that.</text>
			</Show>
			<view direction="row" column-gap={10} margin-top={6}>
				<Show when={!o.won}>
					<Button label="Rewind" kind="blue" onPress={g.rewindToTrouble}/>
				</Show>
				<Button label="Retry" small onPress={g.retry}/>
				<Show when={o.won}>
					<Button label={last ? "Campaign" : "Next"} kind="go" onPress={g.next}/>
				</Show>
			</view>
		</view>;
	}

	// ---- the title and the campaign

	static function Title(props:{game:Game}):View {
		var g = props.game;
		return <view position="absolute" left={0} top={0} right={0} bottom={0} pointer-events="none" align-items="center" justify="space-between"
			padding-top="calc(env(safe-area-inset-top) + 64px)" padding-bottom="calc(env(safe-area-inset-bottom) + 48px)"
			background="linear-gradient(180deg, #1d221088 0%, #1d221000 45%, #1d221000 60%, #1d2210b0 100%)">
			<view slot="drop" transition="opacity 0.5s ease-out, transform 0.7s cubic-bezier(0.34, 1.4, 0.64, 1)" align-items="center">
				<view padding="16 22 12 22" radius={6} background={"linear-gradient(180deg, #5f7130, " + OLIVE + ")"} border-width={3} border-color={INK}
					shadow="0 7 0 #1d2210" transform="rotate(-3deg)" align-items="center">
					<view position="absolute" top={-14} left={-18} padding="4 14" background={TAPE} transform="rotate(-12deg)" shadow="0 2 4 #00000050">
						<text font-family={STENCIL} font-size={20} color={RED} letter-spacing={3}>REWIND</text>
					</view>
					<text font-family={STENCIL} font-size={44} color={TAPE} letter-spacing={1} text-shadow="0 3 0 #1d2210">REGIMENT</text>
					<view height={8} align-self="stretch" margin-top={4} radius={1} background={hazard(GOLD, INK, 7)}/>
				</view>
			</view>
			<view slot="rise" transition="opacity 0.5s ease-out, transform 0.6s ease-out" align-items="center" row-gap={14}>
				<Button label="To battle" kind="go" wide onPress={() -> g.openLevel(firstOpen(g))}/>
				<Button label="Campaign" wide onPress={() -> g.screen("levels")}/>
				<view direction="row" align-items="center" column-gap={6} padding="4 12" radius={6} background="#1d2210c0">
					<image width={16} height={20} src={medalFull}/>
					<text font-size={15} font-weight={500} color={TAPE}>{total(g.best()) + " of " + Levels.levels.length * 3 + " medals"}</text>
				</view>
			</view>
		</view>;
	}

	static function firstOpen(g:Game):Int {
		var b = g.best.peek();
		for (i in 0...b.length)
			if (b[i] == 0 && g.unlocked(i)) return i;
		return 0;
	}

	static function total(b:Array<Int>):Int {
		var s = 0;
		for (x in b)
			s += x;
		return s;
	}

	// the campaign: a crate a room, its levels' dog tags in it
	static function LevelSelect(props:{game:Game}):View {
		var g = props.game;
		function tag(i:Int):View {
			var l = Levels.levels[i], open = g.unlocked(i), medals = g.best()[i];
			return <view:button slot="button" role="button" pointer-events="auto" cursor={open ? "pointer" : "default"}
				width={Math.floor(Math.min(150, (g.width() - 64) / 3))} padding="8 10 8 10" radius={14}
				background={open ? "linear-gradient(165deg, #f1f3f5, #aeb4bc)" : "linear-gradient(165deg, #6d737b, #4e545b)"} border-width={1.5}
				border-color={open ? "#6e757e" : "#3a3f45"} shadow="0 3 0 #00000060" row-gap={2} transition="transform 0.08s ease-out"
				onPress={() -> if (open) g.openLevel(i)}>
				<view direction="row" align-items="center" column-gap={6}>
					<view width={9} height={9} radius={5} background={open ? "#6e757e" : "#2e3237"}/>
					<text font-family={STENCIL} font-size={22} color={open ? "#2e333a" : "#9aa0a8"}>{"" + (i + 1)}</text>
					<view grow={1}/>
					<Show when={!open}>
						<image width={16} height={16} src={lock}/>
					</Show>
				</view>
				<text font-size={12} font-weight={600} color={open ? "#2e333a" : "#9aa0a8"} min-height={32}>{l.name.toUpperCase()}</text>
				<Medals n={medals} size={15}/>
			</view:button>;
		}
		return <view position="absolute" left={0} top={0} right={0} bottom={0} pointer-events="auto" background={"linear-gradient(180deg, #d9b57e, #b8894e)"}
			padding-top="calc(env(safe-area-inset-top) + 18px)" padding-bottom="calc(env(safe-area-inset-bottom) + 18px)" align-items="center" row-gap={12}>
			<view direction="row" align-items="center" column-gap={12}>
				<text font-family={STENCIL} font-size={32} color={INK} letter-spacing={2}>CAMPAIGN</text>
				<view direction="row" align-items="center" column-gap={4} padding="3 10" radius={6} background={INK}>
					<image width={16} height={20} src={medalFull}/>
					<text font-size={16} font-weight={600} color={TAPE}>{"" + total(g.best())}</text>
				</view>
			</view>
			<scroll grow={1} align-self="stretch">
				<view row-gap={16} padding="4 12 16 12">
					{[for (w in 0...Levels.settings.length) if (w * 3 < Levels.levels.length) <view radius={6} padding="10 8 12 8" row-gap={10} align-items="center"
						background={"repeating-linear-gradient(0deg, #56682b 0px, #56682b 30px, #46561f 30px, #46561f 33px)"} border-width={3} border-color={INK}
						shadow="0 5 0 #00000050">
						<view direction="row" align-items="center" column-gap={10}>
							<text font-family={STENCIL} font-size={13} color={GOLD} letter-spacing={2}>{"SECTOR " + (w + 1)}</text>
							<text font-family={STENCIL} font-size={20} color={TAPE} letter-spacing={2}>{Levels.settings[w].name.toUpperCase()}</text>
						</view>
						<view direction="row" wrap="wrap" justify="center" column-gap={8} row-gap={8}>
							{[for (i in w * 3...Std.int(Math.min(Levels.levels.length, w == Levels.settings.length - 1 ? Levels.levels.length : w * 3 + 3))) tag(i)]}
						</view>
					</view>]}
				</view>
			</scroll>
			<Button label="Back" small onPress={() -> g.screen(g.sim.started ? "battle" : "title")}/>
		</view>;
	}
}
