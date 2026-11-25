import Reel.*;
import Reel.SceneDef;
import helder.view.*;
import helder.view.Flow.*;
import helder.view.graph.Read;

// A launch dashboard assembling itself: the cards rise in on springs one
// after another, their numbers count up, the traffic chart's bars grow
// (their heights laid out anew, helder.ui.motion springing each), the
// checklist ticks green item by item and the status pill turns from
// staging to live through OKLab.
class Launch implements Markup {
	public static final scene:SceneDef = {name: "launch", title: "A launch, assembling", duration: 7.5, view: view};

	static final KPIS = [
		{label: "Requests / s", value: 48210, unit: "", color: BLUE},
		{label: "p99 latency", value: 112, unit: " ms", color: VIOLET},
		{label: "Error rate", value: 3, unit: "‰", color: CORAL},
		{label: "Regions live", value: 14, unit: " / 14", color: MINT}
	];

	static final CHECKS = ["Build signed", "Migrations applied", "Canary healthy", "Traffic shifted", "Status page updated"];

	static function bar(i:Int):Float {
		var x = i / 23;
		return 0.28 + 0.62 * (0.5 + 0.5 * Math.sin(x * 5.1 + 0.6)) * (0.55 + 0.45 * x) + 0.1 * rand(i);
	}

	static function Kpi(props:{t:Read<Float>, i:Int}):View {
		var k = KPIS[props.i], from = 0.35 + props.i * 0.14;
		return <view tag={"kpi-" + props.i} flexGrow={1} flexBasis={0} padding="18 20" rowGap={10} borderRadius={18} background={PANEL} borderWidth={1}
			borderColor={LINE} transition="fade slide-up(28)" motion="bouncy">
			<view flexDirection="row" alignItems="center" columnGap={8}>
				<view width={8} height={8} borderRadius={4} background={k.color}/>
				<text fontSize={13} color={MUTED} fontWeight={500}>{k.label}</text>
			</view>
			<text fontFamily="Inter Display" fontSize={38} fontWeight={650} letterSpacing={-0.8} fontVariantNumeric="tabular-nums">{
				thousands(Math.round(k.value * out(lin(props.t(), from + 0.2, from + 1.6)))) + k.unit
			}</text>
			<view height={4} borderRadius={2} background={LINE}>
				<view height={4} borderRadius={2} background={k.color} width={at(props.t(), from + 0.4) ? (70 + props.i * 9) + "%" : "0%"}/>
			</view>
		</view>;
	}

	static function Check(props:{t:Read<Float>, i:Int}):View {
		var when = 2.2 + props.i * 0.55;
		return <view flexDirection="row" alignItems="center" columnGap={12} padding="10 12" borderRadius={12}
			background={at(props.t(), when) ? RAISED : PANEL}>
			<view width={22} height={22} borderRadius={11} alignItems="center" justifyContent="center" background={at(props.t(), when) ? MINT : LINE}>
				<Show when={() -> at(props.t(), when)}>
					<view transition="pop"><icon name="check" width={14} height={14} color={NIGHT}/></view>
				</Show>
			</view>
			<text flexGrow={1} fontSize={15} fontWeight={at(props.t(), when) ? 550 : 400} color={at(props.t(), when) ? INK : MUTED}>{CHECKS[props.i]}</text>
			<text fontSize={12} color={MUTED} fontVariantNumeric="tabular-nums">{at(props.t(), when) ? "0" + (1 + props.i) + ":0" + (2 * props.i + 1) : ""}</text>
		</view>;
	}

	static function countdown(t:Float):String {
		var left = Math.max(0, 5.2 - t);
		return "T−00:00:0" + Std.int(left) + "." + Std.int((left * 10) % 10);
	}

	static function checked(t:Float):Int {
		var n = 0;
		for (i in 0...CHECKS.length)
			if (at(t, 2.2 + i * 0.55)) n++;
		return n;
	}

	public static function view(t:Read<Float>):View {
		var live = () -> at(t(), 5.2);
		return <view flexGrow={1} padding="34 44" rowGap={22} background={NIGHT} color={INK} fontFamily="Inter" motion="default" motionColor="calm">
			<view flexDirection="row" alignItems="center" columnGap={14}>
				<view width={34} height={34} borderRadius={10} background="linear-gradient(135deg, #6d8bff, #a98bff)"/>
				<view rowGap={0}>
					<text fontSize={20} fontWeight={700} letterSpacing={-0.3}>Orbit</text>
					<text fontSize={13} color={MUTED}>Launch control · v4.0</text>
				</view>
				<view flexGrow={1}/>
				<text fontSize={15} color={MUTED} fontVariantNumeric="tabular-nums">{countdown(t())}</text>
				<view flexDirection="row" alignItems="center" columnGap={8} padding="8 16" borderRadius={999} background={live() ? "#0f3b2c" : "#2a2412"}
					borderWidth={1} borderColor={live() ? MINT : AMBER}>
					<view width={8} height={8} borderRadius={4} background={live() ? MINT : AMBER}/>
					<text fontSize={14} fontWeight={600} color={live() ? MINT : AMBER}>{live() ? "Live" : "Staging"}</text>
				</view>
			</view>
			<view flexDirection="row" columnGap={18} height={150}>
				<Repeat count={4}>{i -> <Show when={() -> at(t(), 0.35 + i * 0.14)}><Kpi t={t} i={i}/></Show>}</Repeat>
			</view>
			<view flexDirection="row" columnGap={18} flexGrow={1} minHeight={0}>
				<Show when={() -> at(t(), 0.9)}>
					<view flexGrow={1} padding="20 22" borderRadius={18} background={PANEL} borderWidth={1} borderColor={LINE} rowGap={14} transition="fade slide-up(28)">
						<view flexDirection="row" alignItems="baseline" columnGap={10}>
							<text fontSize={16} fontWeight={600}>Traffic</text>
							<text fontSize={13} color={MUTED}>last 24 hours</text>
							<view flexGrow={1}/>
							<text fontSize={13} color={MINT} fontWeight={600}>{at(t(), 4.2) ? "+38% after shift" : ""}</text>
						</view>
						<view flexGrow={1} flexDirection="row" alignItems="end" columnGap={7}>
							<Repeat count={24}>{i -> <view flexGrow={1} flexBasis={0} borderRadius={5} motion="bouncy"
								background={at(t(), 4.2) && i >= 18 ? "linear-gradient(180deg, #3ee0a8, #1d8f6c)" : "linear-gradient(180deg, #6d8bff, #3b4fb8)"}
								height={(at(t(), 1.15 + i * 0.045) ? Math.round(bar(i) * (at(t(), 4.2) && i >= 18 ? 300 : 230)) : 4)}/>}</Repeat>
						</view>
					</view>
				</Show>
				<Show when={() -> at(t(), 1.6)}>
					<view width={380} padding="20 18" borderRadius={18} background={PANEL} borderWidth={1} borderColor={LINE} rowGap={8} transition="fade slide-left(28)">
						<view flexDirection="row" alignItems="baseline" padding="0 4 6 4">
							<text flexGrow={1} fontSize={16} fontWeight={600}>Checklist</text>
							<text fontSize={13} color={MUTED} fontVariantNumeric="tabular-nums">{checked(t()) + " / " + CHECKS.length}</text>
						</view>
						<Repeat count={5}>{i -> <Check t={t} i={i}/>}</Repeat>
					</view>
				</Show>
			</view>
		</view>;
	}
}
