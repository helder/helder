import Reel.*;
import Reel.SceneDef;
import helder.view.*;
import helder.view.Flow.*;
import helder.view.graph.Read;

// A matched-element zoom: the gallery's photos (painted by Photos.hx) are
// matched="photo-<n>"; one picked leaves the grid and the same id is laid
// out across the stage, so it flies from where it was seen, its radius
// and frame with it, its picture scaled to cover the frame as it goes;
// the caption rides in beside it. Then back, and another.
class Zoom implements Markup {
	public static final scene:SceneDef = {name: "zoom", title: "A matched zoom", duration: 7.5, view: view};

	// the photo shown large at t (-1: the grid)
	static function open(t:Float):Int
		return t >= 1.3 && t < 3.5 ? 1 : t >= 4.3 && t < 6.6 ? 5 : -1;

	static function Photo(props:{i:Int, big:Bool}):View
		return <view tag={"photo-" + props.i} matched={"photo-" + props.i} flexGrow={1} flexBasis={0} minWidth={0} minHeight={0} borderRadius={props.big ? 24 : 16} overflow="hidden" background={RAISED}>
			<image src={Photos.images[props.i]} objectFit="cover" flexGrow={1} minWidth={0} minHeight={0}/>
		</view>;

	static function Tile(props:{t:Read<Float>, i:Int}):View
		return <view flexGrow={1} flexBasis={0} minWidth={0} minHeight={0} rowGap={10}>
			<Photo i={props.i} big={false}/>
			<view flexDirection="row" alignItems="baseline" columnGap={8}>
				<text fontSize={14} fontWeight={600} flexGrow={1}>{Photos.PLACES[props.i].title}</text>
				<text fontSize={12} color={MUTED}>{"No. " + (props.i + 1)}</text>
			</view>
		</view>;

	static function Grid(props:{t:Read<Float>}):View
		return <view flexGrow={1} rowGap={22} transition="fade">
			<view flexDirection="row" flexGrow={1} columnGap={22}>
				<Repeat count={3}>{i -> <Show when={() -> at(props.t(), 0.1 + i * 0.1)}><view flexGrow={1} flexBasis={0} minWidth={0} transition="fade pop"><Tile t={props.t} i={i}/></view></Show>}</Repeat>
			</view>
			<view flexDirection="row" flexGrow={1} columnGap={22}>
				<Repeat count={3}>{i -> <Show when={() -> at(props.t(), 0.4 + i * 0.1)}><view flexGrow={1} flexBasis={0} minWidth={0} transition="fade pop"><Tile t={props.t} i={i + 3}/></view></Show>}</Repeat>
			</view>
		</view>;

	static function Large(props:{i:Int}):View {
		var p = Photos.PLACES[props.i];
		return <view flexGrow={1} flexDirection="row" columnGap={28}>
			<Photo i={props.i} big={true}/>
			<view width={300} justifyContent="end" rowGap={12} padding="0 0 12 0" transition="fade slide-left(40)">
				<text fontSize={13} color={MUTED} letterSpacing={1.6} fontWeight={600}>{"PLATE " + (props.i + 1) + " OF 6"}</text>
				<text fontFamily="Inter Display" fontSize={40} fontWeight={700} lineHeight={1.05} letterSpacing={-1}>{p.title}</text>
				<text fontSize={15} color={MUTED} fontVariantNumeric="tabular-nums">{p.meta}</text>
				<view height={1} background={LINE} margin="8 0"/>
				<text fontSize={14} color={MUTED} lineHeight={1.5}>Painted with helder.canvas when the reel starts: a sky's gradient, a sun's glow and five ridges of sines fading into the haze.</text>
			</view>
		</view>;
	}

	public static function view(t:Read<Float>):View {
		var shown = () -> open(t());
		return <view flexGrow={1} padding="40 48" rowGap={24} background={NIGHT} color={INK} fontFamily="Inter" motion="default">
			<view flexDirection="row" alignItems="baseline" columnGap={14}>
				<text fontFamily="Inter Display" fontSize={30} fontWeight={700} letterSpacing={-0.6}>Field notes</text>
				<text fontSize={15} color={MUTED}>six plates · matched="photo-n"</text>
			</view>
			<view flexGrow={1} minHeight={0}>
				<Show when={() -> shown() < 0} fallback={<view flexGrow={1}>{() -> <Large i={shown()}/>}</view>}>
					<Grid t={t}/>
				</Show>
			</view>
		</view>;
	}
}
