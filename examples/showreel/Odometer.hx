import Reel.*;
import Reel.SceneDef;
import helder.view.*;
import helder.view.Flow.*;
import helder.view.graph.Graph.*;
import helder.view.graph.Read;

// Rolling numbers: each digit a column of 0 to 9 behind a window one
// figure tall, moved to its digit by a transform that springs
// (helder.ui.motion's transform lanes); the columns on the right a little
// quicker than those on the left, so a change ripples across. The figures
// are Inter Display's tabular ones.
class Odometer implements Markup {
	public static final scene:SceneDef = {name: "odometer", title: "Rolling numbers", duration: 6.5, view: view};

	// the revenue at t: steps up every 0.42 s, a big jump at 4.2 s
	static function revenue(t:Float):Int {
		if (t < 0.6) return 1048_210;
		var n = Std.int((t - 0.6) / 0.42), v = 1048_210;
		for (k in 0...n)
			v += 1200 + hash(k) % 23000;
		if (t >= 4.2) v += 61_000;
		return v;
	}

	static function stat(t:Float, k:Int):Int {
		var n = t < 0.8 ? 0 : Std.int((t - 0.8) / (0.55 + 0.1 * k)) + 1;
		return switch k {
			case 0: 18_204 + n * 37 + hash(n) % 29;
			case 1: 982 + n * 3;
			case _: 4_418 + n * 121 + hash(n + 9) % 97;
		}
	}

	// a digit's column: figures stacked, the window on the one shown
	static function Digit(props:{value:Read<Int>, size:Int, place:Int}):View {
		var h = Math.round(props.size * 1.3), v = memo(() -> props.value());
		return <view height={h} overflow="hidden" motionTransform={props.place < 2 ? "snappy" : props.place < 4 ? "default" : "calm"}>
			<view transform={"translate(0px, " + (-v() * h) + "px)"}>
				<Repeat count={10}>{d -> <view height={h} justifyContent="center"><text fontSize={props.size} fontFamily="Inter Display" fontWeight={680}
					lineHeight={1} fontVariantNumeric="tabular-nums" letterSpacing={-props.size * 0.02}>{"" + d}</text></view>}</Repeat>
			</view>
		</view>;
	}

	// a number's place (0: units), its comma after it
	static function Place(props:{value:Read<Int>, place:Int, size:Int}):View
		return <view flexDirection="row" alignItems="center" overflow="hidden" motion="calm"
			maxWidth={props.place == 0 || props.value() >= Math.pow(10, props.place) ? props.size : 0}
			opacity={props.place == 0 || props.value() >= Math.pow(10, props.place) ? 1 : 0}>
			<Digit value={() -> Std.int(props.value() / Math.pow(10, props.place)) % 10} size={props.size} place={props.place}/>
			<Show when={props.place > 0 && props.place % 3 == 0}>
				<text fontSize={props.size} fontFamily="Inter Display" fontWeight={680} lineHeight={1}>,</text>
			</Show>
		</view>;

	// a number of so many places, with commas, rolling
	static function Number(props:{value:Read<Int>, places:Int, size:Int, color:String, under:String}):View
		return <view flexDirection="row" alignItems="center" color={props.color}>
			<Repeat count={props.places}>{i -> <Place value={props.value} place={props.places - 1 - i} size={props.size}/>}</Repeat>
			<view position="absolute" left={0} right={0} top={0} height={Math.round(props.size * 0.2)} background={"linear-gradient(180deg, " + props.under + ", " + props.under + "00)"}/>
			<view position="absolute" left={0} right={0} bottom={0} height={Math.round(props.size * 0.2)} background={"linear-gradient(0deg, " + props.under + ", " + props.under + "00)"}/>
		</view>;

	static final STATS = [{label: "Orders today", color: BLUE}, {label: "New customers", color: VIOLET}, {label: "Cups of coffee", color: AMBER}];

	public static function view(t:Read<Float>):View {
		return <view flexGrow={1} padding="64 80" background={NIGHT} color={INK} fontFamily="Inter" justifyContent="center" rowGap={36}>
			<view rowGap={6}>
				<view flexDirection="row" alignItems="center" columnGap={12}>
					<text fontSize={15} color={MUTED} fontWeight={600} letterSpacing={1.6}>REVENUE · THIS QUARTER</text>
					<view padding="4 10" borderRadius={999} background={at(t(), 4.2) ? "#0f3b2c" : RAISED} motionColor="calm">
						<text fontSize={13} fontWeight={650} color={at(t(), 4.2) ? MINT : MUTED} fontVariantNumeric="tabular-nums">{at(t(), 4.2) ? "▲ 12.4% · a big order" : "▲ 6.1%"}</text>
					</view>
				</view>
				<view flexDirection="row" alignItems="center" columnGap={6}>
					<text fontFamily="Inter Display" fontSize={150} fontWeight={300} color={MUTED} lineHeight={1}>$</text>
					<Number value={() -> revenue(t())} places={7} size={150} color={INK} under={NIGHT}/>
				</view>
			</view>
			<view flexDirection="row" columnGap={20}>
				<Repeat count={3}>{k -> <view flexGrow={1} flexBasis={0} padding="20 24" borderRadius={18} background={PANEL} borderWidth={1} borderColor={LINE} rowGap={10}>
					<view flexDirection="row" alignItems="center" columnGap={8}>
						<view width={8} height={8} borderRadius={4} background={STATS[k].color}/>
						<text fontSize={14} color={MUTED} fontWeight={500}>{STATS[k].label}</text>
					</view>
					<Number value={() -> stat(t(), k)} places={5} size={48} color={INK} under={PANEL}/>
				</view>}</Repeat>
			</view>
		</view>;
	}
}
