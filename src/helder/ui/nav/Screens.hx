package helder.ui.nav;

import helder.ui.Node;
import helder.ui.gesture.Gesture;
import helder.ui.gesture.Pan;
import helder.ui.motion.Curve;
import helder.ui.motion.Track;
import helder.ui.nav.Router.Entry;
import helder.ui.view.UiView;
import helder.view.*;
import helder.view.Flow.*;
import helder.view.graph.Graph.*;
import helder.view.graph.Signal;
#if (target.name == "hxmc")
import hxmc.Platform;
#end

// how a Stack's screens come and go: the platform's slide (iOS's and
// macOS's from the right edge over the one below; Android's a short slide
// and a fade), a fade (the desktop's and the web's), or none
enum abstract StackTransition(String) to String {
	var Slide = "slide";
	var Fade = "fade";
	var None = "none";
}

// A router's stack on screen (helder.ui.Stack): each entry mounted once,
// kept below the top (hidden once covered, its state and scroll as they
// were), disposed after its exit. While deep it is the system's back
// (App.onBack, App.backDepth: Android's back, Escape, the browser's
// history: an entry a push); on iOS's slide a drag from the left edge
// pops it as it goes.
class Screens implements Markup {
	// the screen a component is mounted in and its stack (a NavScreen's bar reads it)
	public static final here:helder.view.graph.Context<Null<Here>> = context((null : Null<Here>));

	public static function Stack(props:{router:Router, ?transition:StackTransition}):UiView {
		var s = new StackState(props.router, props.transition ?? platform());
		return <view tag="stack" flexGrow={1} position="relative" overflow="hidden" ref={n -> s.attach(n)}>
			<For each={s.screens}>{r -> row(r.peek(), s)}</For>
			<text position="absolute" width={1} height={1} overflow="hidden" opacity={0} pointerEvents="none" aria-live="polite">{s.said()}</text>
		</view>;
	}

	static function row(s:Screen, stack:StackState):UiView
		return <view tag="screen" position="absolute" left={0} top={0} right={0} bottom={0} instant transform={s.transform(stack.kind)} opacity={s.opacity(stack.kind)}
			visibility={s.hidden() ? "hidden" : "visible"} pointerEvents={s.busy() ? "none" : "auto"} ref={n -> s.node = n}>
			<Provider context={here} value={new Here(stack, s)}>{s.entry.view}</Provider>
			<view position="absolute" left={0} top={0} right={0} bottom={0} pointerEvents="none" background={s.shade(stack.kind)}/>
		</view>;

	// (the platform's: iOS's and macOS's slide, Android's, else a fade)
	static function platform():StackTransition {
		#if (target.name == "hxmc")
		if (Platform.os() == Platform.MACOS || Platform.target() >= 9) return Slide;
		#end
		return Fade;
	}
}

// (how screens move: iOS's slide, Android's, a fade, reduced motion's
// fade, none; a still entry's fade in place)
enum abstract Kind(Int) {
	var Ios;
	var Android;
	var Fading;
	var Reduced;
	var Still;
	var InPlace;
}

// A screen of a stack, as what is mounted in it sees it: its title (a
// NavScreen's, for the back button above it), the screens below it
@:noCompletion class Here {
	public final stack:StackState;
	public final screen:Screen;

	public function new(stack, screen) {
		this.stack = stack;
		this.screen = screen;
	}

	// the screens below it, the nearest first (their titles: the back
	// button's and its long press's menu)
	public function below():Array<Screen> {
		var list = stack.screens(), i = list.indexOf(screen);
		return i <= 0 ? [] : [for (k in 0...i) list[i - 1 - k]].filter(s -> !s.leaving);
	}

	// pops to the screen below it k down (0: the nearest)
	public function back(k = 0) {
		var list = stack.screens(), i = list.indexOf(screen);
		stack.router.backTo(Std.int(Math.max(0, i - 1 - k)));
	}
}

// One screen: its entry, where it is (at: 1 in place, 0 out to the right;
// cover: 1 covered by the one above)
class Screen {
	public final entry:Entry;
	public final at = new Track(1);
	public final cover = new Track(0);
	public final atValue = signalOf(1.0, {ownedWrite: true});
	public final coverValue = signalOf(0.0, {ownedWrite: true});
	public final hidden = signalOf(false, {ownedWrite: true});
	public final busy = signalOf(false, {ownedWrite: true});
	// its title, its NavScreen's (the back button's of the one above)
	public final title = signalOf("", {ownedWrite: true});
	public var node:Null<Node> = null;
	public var leaving = false;

	public function new(entry:Entry)
		this.entry = entry;

	public function transform(kind:Kind):String {
		var a = atValue(), c = coverValue();
		var x = switch kind {
			case Ios: (1 - a) * 100 - c * 30;
			case Android: (1 - a) * 10;
			case Fading: (1 - a) * 8;
			case _: 0.0;
		}
		return x == 0 ? "none" : "translateX(" + x + (kind == Fading ? "px)" : "%)");
	}

	public function opacity(kind:Kind):Float {
		var a = atValue(), c = coverValue();
		return switch kind {
			case Ios: 1;
			case Android: a * (1 - c * 0.1);
			case Fading | Reduced | InPlace: a * (1 - c);
			case Still: c >= 1 ? 0 : 1;
		}
	}

	public function shade(kind:Kind):String {
		var c = coverValue();
		return kind == Ios && c > 0 ? "rgba(0, 0, 0, " + (c * 0.1) + ")" : "transparent";
	}

	// (the tracks sampled at now, written: whether either moves)
	public function sample(now:Float):Bool {
		at.sample(now);
		cover.sample(now);
		show();
		return at.moving() || cover.moving();
	}

	public function show() {
		atValue(at.value);
		coverValue(cover.value);
		var moving = at.moving() || cover.moving();
		hidden(!moving && cover.value >= 1);
		busy(moving);
	}
}

class StackState {
	public final screens = signalOf(([] : Array<Screen>), {ownedWrite: true});
	public final said = signalOf("", {ownedWrite: true});
	// (how this change moves: the stack's, or a still entry's in place)
	public var kind(default, null):Kind;
	var base:Kind;
	@:allow(helder.ui.nav) final router:Router;
	final transition:StackTransition;
	var node:Null<Node> = null;
	var edge:Null<EdgePan> = null;
	var list:Array<Screen> = [];
	var ticking = false;
	// (the screen to focus once it settles)
	var arriving:Null<Screen> = null;
	// (an edge drag under way)
	var dragging = false;
	// (the history's URLs, the page's: a browser's)
	var synced:Array<String> = [];

	public function new(router:Router, transition:StackTransition) {
		this.router = router;
		this.transition = transition;
		base = kind = kindOf();
		#if (target.name == "hxmc")
		var at = helder.os.History.location();
		if (at != null) {
			synced = [at];
			router.open(at);
			helder.os.History.own(popped);
			onCleanup(helder.os.History.release);
		}
		#end
		router.begin();
		renderEffect(() -> router.entries(), es -> sync(es));
		renderEffect(() -> helder.os.Settings.reducedMotion(), _ -> base = kind = kindOf());
		systemBack();
	}

	function kindOf():Kind {
		if (transition == None) return Still;
		if (helder.os.Settings.reducedMotion.peek() || Clock.reducedMotion) return Reduced;
		if (transition == Fade) return Fading;
		#if (target.name == "hxmc")
		if (Platform.target() >= 9) return Android;
		#end
		return Ios;
	}

	public function attach(n:Node) {
		node = n;
		var g = edge = n.addGesture(new EdgePan());
		g.onGesture = swipe;
		g.enabled = swipes() && list.length > 1;
		onCleanup(() -> n.removeGesture(g));
	}

	// (the system's back: Android's, Escape, the browser's while deep)
	function systemBack() {
		#if (target.name == "hxmc")
		// (a static Linux executable, musl's: no window back end links there, so App stays out)
		if (Platform.os() != Platform.LINUX || Platform.target() >= 2) {
			var before = helder.os.App.onBack, depth = helder.os.App.backDepth;
			var pop:Void->Bool = router.back;
			renderEffect(() -> router.depth(), d -> {
				if (d > 0) {
					helder.os.App.onBack = pop;
					helder.os.App.backDepth = d;
				} else if (helder.os.App.onBack == pop) {
					helder.os.App.onBack = before;
					helder.os.App.backDepth = depth;
				}
			});
			onCleanup(() -> if (helder.os.App.onBack == pop) {
				helder.os.App.onBack = before;
				helder.os.App.backDepth = depth;
			});
		}
		#end
	}

	function sync(entries:Array<Entry>) {
		history(entries);
		var old = top();
		var known = [for (s in list) s.entry => s];
		var next = [for (s in list) s];
		for (s in next)
			if (entries.indexOf(s.entry) < 0) s.leaving = true;
		for (e in entries)
			if (!known.exists(e)) next.push(new Screen(e));
		list = next;
		var now = top();
		var pushed = now != null && !known.exists(now.entry);
		var still = now != old && (pushed ? now.entry.still : old != null && old.entry.still);
		kind = still && (base == Ios || base == Android || base == Fading) ? InPlace : base;
		if (old == null || kind == Still) {
			// (the first screens, or none moving: at once)
			for (s in list) {
				s.at.set(1);
				s.cover.set(s == now ? 0 : 1);
			}
			list = list.filter(s -> !s.leaving);
			for (s in list)
				s.show();
			if (old != null && now != old) {
				arriving = now;
				tick();
			}
		} else if (now != old) {
			var curve = curveOf();
			for (s in list)
				if (s != now && s != old) s.cover.set(1);
			if (pushed) {
				now.at.set(0);
				now.at.animate(-1, 1, curve);
				old.cover.animate(-1, 1, curve);
			} else {
				var v = fling;
				now.cover.animate(-1, 0, curve, v == null ? null : -v);
				old.at.animate(-1, 0, curve, v == null ? null : -v);
			}
			// (what leaves out of sight: at once)
			list = list.filter(s -> !s.leaving || s == old);
			for (s in list)
				s.show();
			arriving = now;
			tick();
		}
		fling = null;
		// (a still top: not dragged away from the edge either)
		if (edge != null) edge.enabled = swipes() && entries.length > 1 && !(now?.entry.still ?? false);
		screens(list.copy());
	}

	function top():Null<Screen> {
		var i = list.length;
		while (i-- > 0)
			if (!list[i].leaving) return list[i];
		return null;
	}

	// (iOS's swipe back: its slide's, and under reduced motion a fade that
	// follows the finger as the slide would)
	function swipes():Bool {
		if (base == Ios) return true;
		if (base != Reduced || transition != Slide) return false;
		#if (target.name == "hxmc")
		if (Platform.target() >= 9) return false;
		#end
		return true;
	}

	function curveOf():Curve
		return switch kind {
			case Ios: Curve.spring(0.35, 0);
			case Android: Curve.tween(0.3, [0.05, 0.7, 0.1, 1.0]);
			case Fading: Curve.tween(0.15, Transition.EASE_OUT);
			// (short: the app's own motion carries the change, a viewer's picture flown from its tile)
			case InPlace: Curve.tween(0.16, [0.2, 0.8, 0.2, 1]);
			case _: Curve.tween(0.15, Transition.LINEAR);
		}

	// (the tracks moved each frame until none moves: what left removed, the new top focused)
	function tick() {
		if (ticking) return;
		ticking = true;
		var step = (now:Float) -> {
			var moving = false;
			for (s in list)
				if (s.sample(now)) moving = true;
			if (moving || dragging) return true;
			ticking = false;
			var gone = list.filter(s -> s.leaving);
			if (gone.length > 0) {
				list = list.filter(s -> !s.leaving);
				screens(list.copy());
			}
			if (arriving != null) settle(arriving);
			return false;
		};
		if (node == null) Clock.add(step) else Clock.addFor(node, step);
	}

	// (the new top: its first focusable node focused, its first text announced)
	function settle(s:Screen) {
		arriving = null;
		var n = s.node;
		if (n == null) return;
		var f = first(n, x -> x.focusable);
		if (f != null) f.focus(false);
		var t = first(n, x -> Std.isOfType(x, TextNode) && (cast x : TextNode).text != "");
		said(t == null ? s.entry.path : (cast t : TextNode).text);
	}

	static function first(n:Node, ok:Node->Bool):Null<Node> {
		if (ok(n)) return n;
		for (c in n.children) {
			var f = first(c, ok);
			if (f != null) return f;
		}
		return null;
	}

	// --- iOS's edge swipe

	// (a swipe's speed let go, in widths a second: the pop's)
	var fling:Null<Float> = null;

	function swipe(g:Gesture) {
		var n = node, list = this.list, now = top();
		if (n == null || now == null) return;
		var i = list.indexOf(now);
		var below = i > 0 ? list[i - 1] : null;
		var w = n.width <= 0 ? 1 : n.width;
		switch g.state {
			case Began | Changed if (swipes() && below != null):
				// (after a still entry's change: dragged as the stack's own)
				kind = base;
				dragging = true;
				var k = 1 - Math.max(0, Math.min(1, g.tx / w));
				now.at.set(k);
				below.cover.set(k);
				below.hidden(false);
				now.show();
				below.show();
				tick();
			case Ended if (dragging):
				dragging = false;
				var v = g.vx / w;
				if (g.tx > w * 0.5 || g.vx > 500) {
					fling = v;
					router.back();
				} else {
					now.at.animate(-1, 1, curveOf(), -v);
					if (below != null) below.cover.animate(-1, 1, curveOf(), -v);
				}
			case Cancelled if (dragging):
				dragging = false;
				now.at.animate(-1, 1, curveOf());
				if (below != null) below.cover.animate(-1, 1, curveOf());
			case _:
		}
	}

	// --- the browser's history

	function history(entries:Array<Entry>) {
		#if (target.name == "hxmc")
		if (synced.length == 0) return;
		var urls = [for (e in entries) e.url];
		var k = 0;
		while (k < synced.length && k < urls.length && synced[k] == urls[k])
			k++;
		var keep = k < 1 ? 1 : k;
		if (synced.length > keep) {
			helder.os.History.go(keep - synced.length);
			synced.resize(keep);
		}
		if (synced[keep - 1] != urls[keep - 1]) {
			helder.os.History.replace(urls[keep - 1]);
			synced[keep - 1] = urls[keep - 1];
		}
		for (i in keep...urls.length) {
			helder.os.History.push(urls[i]);
			synced.push(urls[i]);
		}
		#end
	}

	// (the browser's back went steps entries back: as many popped)
	function popped(steps:Int) {
		synced.resize(Std.int(Math.max(1, synced.length - steps)));
		for (_ in 0...steps)
			if (!router.back()) break;
	}
}

// A drag from within 20 points of the left edge, rightward: iOS's swipe
// back (one that starts further in is left to what is under it: a
// horizontal scroller's). It takes its pointer before a scroller would.
class EdgePan extends Pan {
	public static inline var EDGE = 20.0;

	public function new() {
		super(X);
		slop = 4;
	}

	override function added() {
		if (pointers == 1 && node != null && node.localX(fx, fy) > EDGE) {
			fail();
			return;
		}
		super.added();
	}

	override function moved() {
		if (!active && travelX < -slop) {
			fail();
			return;
		}
		super.moved();
	}
}
