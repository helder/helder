package helder.ui.nav;

import helder.ui.Node;
import helder.ui.Popup;
import helder.ui.SafeArea;
import helder.ui.SizeClass;
import helder.ui.controls.Look;
import helder.ui.gesture.Gesture;
import helder.ui.gesture.Pan;
import helder.ui.motion.Curve;
import helder.ui.motion.Track;
import helder.ui.view.UiView;
import helder.view.*;
import helder.view.Flow.Mountable;
import helder.view.graph.Graph;
import helder.view.graph.Graph.*;
import helder.view.graph.Read;
import helder.view.graph.Signal;

// where a sheet rests: about half the window's height (Medium), or all of
// it but a strip at the top (Large)
enum abstract Detent(String) to String {
	var Medium = "medium";
	var Large = "large";
}

typedef SheetProps = {
	open:Read<Bool>,
	?onDismiss:Void->Void,
	?detents:Array<Detent>,
	?detent:Signal<Detent>,
	?anchor:Void->Null<Node>,
	?popover:Bool,
	?label:String,
	?tag:String,
	?children:Any
}

// A bottom sheet, iOS's and Android's: a panel from the bottom edge over a
// scrim, resting at its detents (Medium, Large; the first to begin with,
// detent the one it is at, written as it is dragged), a grabber at its
// top, dragged between them and down to dismiss (onDismiss: by distance
// or by speed; a press on the scrim and Escape too), its bottom inside
// the safe area. A drag on content that scrolls is the content's until it
// is at its top. Under reduced motion it fades instead of sliding. With
// an anchor on a screen wider than Compact (SizeClass), unless popover is
// false, it is a popover from that node instead. Its content is rendered
// each time it opens. Slots: sheet-scrim, sheet, sheet-grabber,
// sheet-popover (the look's parts).
class Sheets implements Markup {
	public static inline var TOP = 10.0;
	public static inline var POPOVER = 360.0;

	public static function Sheet(props:SheetProps):Any
		return new SheetMount(props);

	@:noCompletion public static function Panel(props:{s:SheetState, children:Any}):UiView {
		var s = props.s;
		return <view tag={s.props.tag ?? "sheet-layer"} position="absolute" left={0} top={0} right={0} bottom={0}
			onKeyDown={e -> if (e.key == Key.ESCAPE) s.dismiss(0)}>
			<view slot="sheet-scrim" tag="sheet-scrim" position="absolute" left={0} top={0} right={0} bottom={0} opacity={s.scrim()}
				onClick={_ -> s.dismiss(0)}/>
			<view slot="sheet" tag="sheet" role="dialog" label={s.props.label} modal position="absolute" left={0} right={0} bottom={0}
				height={s.full()} transform={"translateY(" + s.offset() + "px)"} opacity={s.alpha()} padding-bottom="env(safe-area-inset-bottom)"
				ref={(n:Node) -> s.attach(n)}>
				<view slot="sheet-grabber" tag="sheet-grabber" role="button" label="Resize" focusable onPress={() -> s.cycle()}/>
				<view grow={1} min-height={0}>{props.children}</view>
			</view>
		</view>;
	}

	@:noCompletion public static function Floating(props:{s:SheetState, children:Any}):UiView
		return <view slot="sheet-popover" tag={props.s.props.tag ?? "sheet-popover"} role="dialog" label={props.s.props.label} width={POPOVER}
			max-height={props.s.full()} onKeyDown={e -> if (e.key == Key.ESCAPE) props.s.dismiss(0)}>{props.children}</view>;
}

// A sheet's place: its height shown (the detent's, as dragged), the scrim
// and its opacity following it
@:noCompletion class SheetState {
	public final props:SheetProps;
	// the panel's full height, how far down it is moved, its opacity, the scrim's
	public final full = signalOf(0.0, {ownedWrite: true});
	public final offset = signalOf(0.0, {ownedWrite: true});
	public final alpha = signalOf(1.0, {ownedWrite: true});
	public final scrim = signalOf(0.0, {ownedWrite: true});
	public final detents:Array<Detent>;
	public final at:Signal<Detent>;
	// (how far down: 0 at Large, full off the screen)
	final y = new Track(0);
	final fade = new Track(0);
	var height = 0.0;
	var tall = 0.0;
	var node:Null<Node> = null;
	var ticking = false;
	var closing = false;
	@:allow(helder.ui.nav.SheetMount) var onGone:Null<Void->Void> = null;

	public function new(props:SheetProps) {
		this.props = props;
		detents = props.detents == null || props.detents.length == 0 ? [Large] : props.detents;
		at = props.detent ?? Graph.signal(detents[0]);
	}

	public function attach(n:Node) {
		node = n;
		var pan = n.addGesture(new SheetPan(n));
		pan.onGesture = drag;
	}

	// (opened in a window height h tall: from below, to its first detent)
	public function show(h:Float) {
		height = h;
		closing = false;
		tall = h - SafeArea.insets.peek().top - Sheets.TOP;
		full(tall);
		y.set(tall);
		fade.set(reduced() ? 0 : 1);
		var d = detents.indexOf(at.peek()) < 0 ? detents[0] : at.peek();
		at(d);
		to(d, null);
	}

	// the height left above a detent's top (Large 0)
	function rest(d:Detent):Float
		return d == Large ? 0 : tall - Math.round(height * 0.5);

	function to(d:Detent, v:Null<Float>) {
		if (reduced()) {
			y.set(rest(d));
			fade.animate(-1, 1, Curve.tween(0.15, Transition.EASE_OUT));
		} else
			y.animate(-1, rest(d), Curve.spring(0.35, 0), v);
		tick();
	}

	// asked to close (onDismiss); v its speed down
	public function dismiss(v:Float) {
		if (props.onDismiss != null) props.onDismiss();
	}

	// (closed: off the bottom, then gone)
	public function hide() {
		closing = true;
		if (reduced()) fade.animate(-1, 0, Curve.tween(0.15, Transition.EASE_OUT)) else y.animate(-1, tall, Curve.spring(0.3, 0));
		tick();
	}

	// (the grabber pressed: the next detent)
	public function cycle() {
		var i = detents.indexOf(at.peek());
		if (i < 0) i = 0;
		var d = detents[(i + 1) % detents.length];
		at(d);
		to(d, null);
	}

	function reduced():Bool
		return helder.os.Settings.reducedMotion.peek() || Clock.reducedMotion;

	function show_() {
		offset(Math.max(0, y.value));
		alpha(fade.value);
		// (the scrim: full above Medium's top, none at the bottom)
		var f = tall, m = detents.indexOf(Medium) >= 0 ? rest(Medium) : 0;
		var k = f <= m ? 0 : 1 - (y.value - m) / (f - m);
		scrim(Math.max(0, Math.min(1, k)) * fade.value);
	}

	function tick() {
		show_();
		if (ticking) return;
		ticking = true;
		var step = (now:Float) -> {
			y.sample(now);
			fade.sample(now);
			show_();
			if (y.moving() || fade.moving() || dragging) return true;
			ticking = false;
			if (closing && onGone != null) onGone();
			return false;
		};
		if (node == null) Clock.add(step) else Clock.addFor(node, step);
	}

	var dragging = false;

	function drag(g:Gesture) {
		switch g.state {
			case Began | Changed:
				dragging = true;
				// (above Large: resisting, a third as far)
				var v = y.value + g.dy;
				y.set(v < 0 ? y.value + g.dy / 3 : v);
				tick();
			case Ended | Cancelled:
				dragging = false;
				var f = tall, v = g.vy;
				// (where it would come to rest: its place and its speed's reach)
				var aim = y.value + v * 0.2;
				var low = rest(detents[0]);
				for (d in detents)
					low = Math.max(low, rest(d));
				if (g.state == Ended && (aim > low + (f - low) / 2 || v > 1000)) {
					dismiss(v);
					return;
				}
				var best = detents[0], gap = Math.POSITIVE_INFINITY;
				for (d in detents) {
					var dist = Math.abs(rest(d) - aim);
					if (dist < gap) {
						gap = dist;
						best = d;
					}
				}
				at(best);
				to(best, v);
			case _:
		}
	}
}

// A sheet's drag: vertical; one that starts on content that scrolls is the
// content's unless it is at its top and the drag goes down
private class SheetPan extends Pan {
	final panel:Node;
	var inner:Null<Node> = null;

	public function new(panel:Node) {
		super(Y);
		this.panel = panel;
	}

	override function added() {
		if (pointers == 1) {
			inner = null;
			var u = panel.ui;
			var n = u == null ? null : @:privateAccess u.hit(fx, fy);
			while (n != null && n != panel) {
				if (n.style.overflow == Scroll && n.contentHeight > n.height + 1) inner = n;
				n = n.parent;
			}
		}
		super.added();
	}

	override function moved() {
		if (!active && inner != null && (inner.scrollY > 0 || travelY < 0)) {
			fail();
			return;
		}
		super.moved();
	}
}

// Sheet: a hidden marker where the markup puts it; the sheet's popup
// opened in its Ui while open is true, closed once it has slid away
@:renderer(helder.ui.view.NodeRenderer)
class SheetMount implements Mountable<Node> implements Markup {
	final props:SheetProps;

	public function new(props)
		this.props = props;

	public function mount(parent:Node, before:Null<Node>):Array<Node> {
		var marker = new Node("sheet");
		marker.style.display = None;
		var i = before == null ? parent.children.length : parent.indexOf(before);
		parent.insert(marker, i < 0 ? parent.children.length : i);
		var s = new SheetState(props), own = Graph.use(Look.context) == null;
		var p:Null<Popup> = null, dispose:Null<Void->Void> = null;
		function gone() {
			if (p != null && p.ui != null) p.ui.close(p);
			if (dispose != null) dispose();
			p = null;
			dispose = null;
		}
		s.onGone = gone;
		var home = Graph.getOwner();
		function open() {
			var u = marker.ui;
			if (u == null) return;
			if (p != null) gone();
			var anchor = props.anchor == null ? null : props.anchor();
			var floating = anchor != null && props.popover != false && SizeClass.current.peek() != Compact;
			var q = p = new Popup(floating ? "sheet-popover-layer" : "sheet-layer");
			q.theme = own ? Look.base.sheet() : marker.sheet();
			if (floating) {
				q.anchor = anchor;
				q.placement = Below;
				q.gap = 8;
				q.onDismiss = () -> s.dismiss(0);
				s.full(u.height * 0.8);
				Graph.runWithOwner(home, () -> dispose = Render.render(<Sheets.Floating s={s}>{props.children}</Sheets.Floating>, q));
			} else {
				q.modal = true;
				q.style.background = helder.gfx.Color.TRANSPARENT;
				q.onDismiss = () -> s.dismiss(0);
				Graph.runWithOwner(home, () -> dispose = Render.render(<Sheets.Panel s={s}>{props.children}</Sheets.Panel>, q));
				s.show(u.height);
			}
			u.open(q);
		}
		function close() {
			if (p == null) return;
			if (p.tag == "sheet-popover-layer") gone() else s.hide();
		}
		var on:Read<Bool> = Read.of(props.open);
		Graph.onSettled(() -> Graph.runWithOwner(home, () -> Graph.renderEffect(() -> on() == true, (v:Bool) -> v ? open() : close())));
		Graph.onCleanup(gone);
		return [marker];
	}
}
