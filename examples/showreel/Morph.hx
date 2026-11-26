import Reel.*;
import Reel.SceneDef;
import helder.view.*;
import helder.view.Flow.*;
import helder.view.graph.Read;

// A theme switch where everything morphs: four themes, each a set of
// colours, a corner radius and a spacing; switching moves every colour
// through OKLab (text a little ahead, keeping its contrast), every radius
// and every box's edges on springs, the selected theme's marker flying
// to its pill (matched="marker") and the switches' knobs sliding.
typedef Theme = {
	name:String,
	bg:String,
	card:String,
	ink:String,
	muted:String,
	line:String,
	accent:String,
	accentInk:String,
	radius:Int,
	gap:Int,
	pad:Int
}

class Morph implements Markup {
	public static final scene:SceneDef = {name: "theme", title: "A theme, morphing", duration: 7.5, view: view};

	static final THEMES:Array<Theme> = [
		{name: "Daylight", bg: "#eef0f5", card: "#ffffff", ink: "#12141c", muted: "#6b7080", line: "#e2e5ec", accent: "#4f5bff", accentInk: "#ffffff", radius: 16, gap: 20, pad: 22},
		{name: "Midnight", bg: "#090b12", card: "#141824", ink: "#eef1fb", muted: "#8a91a8", line: "#232838", accent: "#8b7bff", accentInk: "#0b0c14", radius: 16, gap: 20, pad: 22},
		{name: "Dusk", bg: "#2b1834", card: "#3d2348", ink: "#ffe9d6", muted: "#c9a3b8", line: "#55325f", accent: "#ff8a65", accentInk: "#2b1834", radius: 30, gap: 26, pad: 28},
		{name: "Paper", bg: "#f3efe6", card: "#fffdf7", ink: "#1f2a24", muted: "#6f7a70", line: "#e0dacb", accent: "#127a5a", accentInk: "#fffdf7", radius: 4, gap: 12, pad: 16}
	];

	// the theme at t
	static function themeAt(t:Float):Int
		return t < 1.2 ? 0 : t < 2.8 ? 1 : t < 4.4 ? 2 : t < 6.0 ? 3 : 1;

	static function Pill(props:{t:Read<Float>, i:Int}):View {
		var th = () -> THEMES[themeAt(props.t())];
		return <view padding="8 16" borderRadius={999} alignItems="center" justifyContent="center">
			<Show when={() -> themeAt(props.t()) == props.i}>
				<view matched="marker" position="absolute" left={0} top={0} right={0} bottom={0} borderRadius={999} background={th().accent}/>
			</Show>
			<text fontSize={14} fontWeight={600} color={themeAt(props.t()) == props.i ? th().accentInk : th().muted}>{THEMES[props.i].name}</text>
		</view>;
	}

	static function Switch(props:{t:Read<Float>, on:Read<Bool>}):View {
		var th = () -> THEMES[themeAt(props.t())];
		return <view width={46} height={28} borderRadius={14} padding={3} flexDirection="row" justifyContent={props.on() ? "end" : "start"}
			background={props.on() ? th().accent : th().line}>
			<view width={22} height={22} borderRadius={11} background="#ffffff" boxShadow="0 1px 3px rgba(0,0,0,0.25)"/>
		</view>;
	}

	static function Row(props:{t:Read<Float>, label:String, detail:String, on:Read<Bool>}):View {
		var th = () -> THEMES[themeAt(props.t())];
		return <view flexDirection="row" alignItems="center" columnGap={12} padding={"" + Math.round(th().gap * 0.55) + " 0"} borderWidth="0 0 1 0" borderColor={th().line}>
			<view flexGrow={1} rowGap={2}>
				<text fontSize={15} fontWeight={550} color={th().ink}>{props.label}</text>
				<text fontSize={13} color={th().muted}>{props.detail}</text>
			</view>
			<Switch t={props.t} on={props.on}/>
		</view>;
	}

	public static function view(t:Read<Float>):View {
		var th = () -> THEMES[themeAt(t())];
		var k = () -> themeAt(t());
		return <view flexGrow={1} padding="40 52" rowGap={28} background={th().bg} color={th().ink} fontFamily="Inter" motion="default" motionColor="calm">
			<view flexDirection="row" alignItems="center">
				<view flexGrow={1} rowGap={2}>
					<text fontFamily="Inter Display" fontSize={32} fontWeight={700} letterSpacing={-0.7}>Appearance</text>
					<text fontSize={14} color={th().muted}>Colours, corners and spacing, all of them springs</text>
				</view>
				<view flexDirection="row" columnGap={4} padding={4} borderRadius={999} background={th().card} borderWidth={1} borderColor={th().line}>
					<Repeat count={4}>{i -> <Pill t={t} i={i}/>}</Repeat>
				</view>
			</view>
			<view flexDirection="row" flexGrow={1} columnGap={th().gap} minHeight={0}>
				<view width={330} padding={th().pad} rowGap={th().gap} borderRadius={th().radius} background={th().card} borderWidth={1} borderColor={th().line}>
					<view flexDirection="row" alignItems="center" columnGap={14}>
						<view width={64} height={64} borderRadius={th().radius >= 16 ? 32 : th().radius * 2} background={"linear-gradient(135deg, " + th().accent + ", #ffbf47)"}/>
						<view rowGap={2}>
							<text fontSize={19} fontWeight={700}>Noor Vandamme</text>
							<text fontSize={14} color={th().muted}>@noor · Ghent</text>
						</view>
					</view>
					<view flexDirection="row" columnGap={th().gap}>
						<view flexGrow={1} rowGap={2}><text fontFamily="Inter Display" fontSize={30} fontWeight={700} fontVariantNumeric="tabular-nums">2,481</text><text fontSize={13} color={th().muted}>Followers</text></view>
						<view flexGrow={1} rowGap={2}><text fontFamily="Inter Display" fontSize={30} fontWeight={700} fontVariantNumeric="tabular-nums">318</text><text fontSize={13} color={th().muted}>Following</text></view>
					</view>
					<view flexGrow={1}/>
					<view padding="12 0" borderRadius={Math.min(th().radius, 999)} alignItems="center" background={th().accent}>
						<text fontSize={15} fontWeight={650} color={th().accentInk}>Follow</text>
					</view>
				</view>
				<view flexGrow={1} padding={th().pad} rowGap={th().gap} borderRadius={th().radius} background={th().card} borderWidth={1} borderColor={th().line}>
					<view flexGrow={1} borderRadius={Math.max(2, th().radius - 6)} background={"linear-gradient(160deg, " + th().accent + " 0%, " + th().bg + " 120%)"} justifyContent="end" padding={th().pad}>
						<text fontFamily="Inter Display" fontSize={34} fontWeight={700} color="#ffffff" letterSpacing={-0.6}>Slow Tides</text>
						<text fontSize={15} color="#ffffffcc">Lowland Hum · 3:41</text>
					</view>
					<view height={6} borderRadius={3} background={th().line}>
						<view height={6} borderRadius={3} background={th().accent} width={(18 + 70 * lin(t(), 0, 7.5)) + "%"}/>
					</view>
					<view flexDirection="row" justifyContent="center" alignItems="center" columnGap={28}>
						<image src={icon("skip-back")} width={22} height={22} color={th().ink}/>
						<view width={54} height={54} borderRadius={27} alignItems="center" justifyContent="center" background={th().accent}>
							<image src={icon("pause")} width={22} height={22} color={th().accentInk}/>
						</view>
						<image src={icon("skip-forward")} width={22} height={22} color={th().ink}/>
					</view>
				</view>
				<view width={340} padding={th().pad} borderRadius={th().radius} background={th().card} borderWidth={1} borderColor={th().line}>
					<text fontSize={16} fontWeight={650} padding="0 0 6 0">Preferences</text>
					<Row t={t} label="Sound effects" detail="Clicks and chimes" on={() -> k() == 0 || k() == 3}/>
					<Row t={t} label="Dark interface" detail="Follows the theme" on={() -> k() == 1 || k() == 2}/>
					<Row t={t} label="Rounder corners" detail="Radius by theme" on={() -> THEMES[k()].radius >= 16}/>
					<Row t={t} label="Compact spacing" detail="Tighter rows" on={() -> THEMES[k()].gap < 16}/>
				</view>
			</view>
		</view>;
	}
}
