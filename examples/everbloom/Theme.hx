import Api;
import helder.ui.*;
import helder.view.*;
import helder.view.Flow.*;
import helder.view.graph.Graph.*;
import helder.view.graph.Read;

// The design's tokens (design/screens/Tokens.dc.html), its four icons and
// the stepper's and states' glyphs (its SVGs, drawn in a colour), and the
// pieces the screens share: a product's card and price, the error state.
typedef Icon = (size:Float, color:String) -> View;

class Theme implements Markup {
	public static inline var BACKGROUND = "#FFFFFF";
	public static inline var SURFACE = "#F4F1EC";
	public static inline var SKELETON = "#EDE9E3";
	public static inline var BORDER = "#E6E1D9";
	public static inline var TEXT = "#1C1B19";
	public static inline var MUTED = "#6E6A63";
	public static inline var BODY = "#3D3A35";
	public static inline var SALE = "#B4361E";

	// the icons (24 units, stroked in their color): markup's <svg>, drawn
	// from shapes read when compiling
	public static function HOME(size:Float, color:String):View
		return <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round"
			width={size} height={size} color={color} hidden><path d="M3 10.5 12 3l9 7.5V20a1 1 0 0 1-1 1h-5v-6H9v6H4a1 1 0 0 1-1-1z"/></svg>;

	public static function SEARCH(size:Float, color:String):View
		return <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round"
			width={size} height={size} color={color} hidden><circle cx="11" cy="11" r="7"/><path d="m20 20-3.5-3.5"/></svg>;

	public static function CART(size:Float, color:String):View
		return <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round"
			width={size} height={size} color={color} hidden><path d="M6 7h12l-1 13H7z"/><path d="M9 7a3 3 0 0 1 6 0"/></svg>;

	public static function BACK(size:Float, color:String):View
		return <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round"
			width={size} height={size} color={color} hidden><path d="m15 5-7 7 7 7"/></svg>;

	public static function MINUS(size:Float, color:String):View
		return <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"
			width={size} height={size} color={color} hidden><path d="M5 12h14"/></svg>;

	public static function PLUS(size:Float, color:String):View
		return <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"
			width={size} height={size} color={color} hidden><path d="M12 5v14M5 12h14"/></svg>;

	public static function ERROR(size:Float, color:String):View
		return <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.25" stroke-linecap="round" stroke-linejoin="round"
			width={size} height={size} color={color} hidden><circle cx="12" cy="12" r="9"/><path d="M12 7.5v5.5"/><path d="M12 16.5h.01"/></svg>;

	public static function icon(glyph:Icon, size:Float, color:String):View
		return glyph(size, color);

	// $45.00, in the sale colour with the compare-at price struck through when it is higher
	public static function Price(props:{price:Money, ?compareAt:Money, ?size:Float}):View {
		var size = props.size ?? 15;
		return <view direction="row" column-gap={6} align-items="baseline">
			<text font-size={size} font-weight={700} color={props.compareAt != null ? SALE : TEXT}>{props.price.toString()}</text>
			<Show when={props.compareAt != null}>
				<text font-size={13} color={MUTED} text-decoration={TextDecoration.LineThrough}>{props.compareAt?.toString() ?? ""}</text>
			</Show>
		</view>;
	}

	// an image of the API's at a width, cover-cropped into its frame (the surface colour until it lands)
	public static function Picture(props:{url:Null<String>, width:Int, ?w:Dynamic, ?h:Dynamic, ?ratio:Float, ?radius:Float}):View
		return <image src={Img.of(props.url, props.width)} fit="cover" width={props.w} height={props.h} aspect-ratio={props.ratio} radius={props.radius ?? 8}
			background={SURFACE} hidden/>;

	// a grid's or a carousel's card: the image (3:4), the title (two lines at most), the price
	public static function Card(props:{product:Product, id:String, onOpen:Product->Void, ?width:Float}):View {
		var p = props.product;
		return <view:button id={props.id} role="button" label={p.title} focusable width={props.width} grow={props.width == null ? 1 : 0}
			basis={props.width == null ? 0 : null} min-width={0} shrink={props.width == null ? 1 : 0} row-gap={8} onPress={() -> props.onOpen(p)}>
			<Picture url={p.image} width={480} ratio={0.75}/>
			<text font-size={14} line-height="18px" max-lines={2} text-overflow="ellipsis">{p.title}</text>
			<Price price={p.price} compareAt={p.compareAt}/>
		</view:button>;
	}

	public static function Button(props:{label:String, onPress:Void->Void, ?id:String, ?secondary:Bool, ?disabled:Read<Bool>, ?height:Float}):View
		return <view:button id={props.id} role="button" focusable disabled={props.disabled != null && props.disabled()} height={props.height ?? 52}
			padding="0 24" radius={12} align-items="center" justify="center" background={props.secondary == true ? BACKGROUND : TEXT}
			border-width={props.secondary == true ? 1 : 0} border-color={TEXT} opacity={props.disabled != null && props.disabled() ? 0.5 : 1}
			onPress={() -> if (props.disabled == null || !props.disabled.peek()) props.onPress()}>
			<text font-size={16} font-weight={600} color={props.secondary == true ? TEXT : "#ffffff"}>{props.label}</text>
		</view:button>;

	// (States.dc.html's error: the glyph, the title, the hint, Retry)
	public static function Failed(props:{onRetry:Void->Void}):View
		return <view grow={1} align-items="center" justify="center" row-gap={12} padding="0 32">
			{icon(ERROR, 48, MUTED)}
			<text font-size={17} font-weight={700}>Couldn't load products</text>
			<text font-size={15} line-height="22px" color={MUTED} text-align="center">Check your connection and try again.</text>
			<view margin-top={8}><Button id="error-retry" label="Retry" secondary height={48} onPress={props.onRetry}/></view>
		</view>;

	public static function Spinner():View
		return <view padding={24} align-items="center" role="progressbar" label="Loading">
			<view width={24} height={24} radius={12} border-width={3} border-color={BORDER} borders="3" />
		</view>;

	// the round back button (over a product's image) or a nav bar's
	public static function Back(props:{?round:Bool}):View
		return <view:button id="back" role="button" label="Back" focusable width={props.round == true ? 40 : 44} height={props.round == true ? 40 : 44}
			radius={props.round == true ? 20 : 0} background={props.round == true ? BACKGROUND : null} align-items="center" justify="center"
			onPress={() -> Everbloom.back()}>{icon(BACK, 24, TEXT)}</view:button>;
}
