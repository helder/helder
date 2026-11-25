package helder.ui.menu;

import helder.os.Rect;
import helder.ui.Key;
import helder.ui.Node;
import helder.ui.Popup;
import helder.ui.SafeArea;
import helder.ui.Ui;
import helder.ui.actions.Actions;
import helder.ui.menu.Menu;
import helder.ui.view.UiView;
import helder.view.*;
import helder.view.Flow.*;
import helder.view.graph.Graph.*;

// One choice of a touch menu: its label, checked (a mark), disabled,
// destructive (red: Move to Trash), a line above it (a group's start),
// what choosing it does
typedef Choice = {label:String, ?checked:Bool, ?disabled:Bool, ?destructive:Bool, ?separated:Bool, run:Void->Void};

// A menu for touch, iOS's and Android's long press menus: a column of
// choices 44 points high (slot touch-menu, touch-menu-item: data-selected
// checked, data-disabled; touch-menu-item-danger), in a modal popup over
// the window. With a preview (a view at where its node is, lifted: slot
// touch-menu-preview) the menu goes under it, or above it where there is
// no room, the preview moved up to fit; blur puts a glass over what is
// behind (slot touch-menu-backdrop: a dimmed, blurred window). A press
// outside, Escape or a choice closes it. The platform's own menu
// (UIContextMenuInteraction) is not used: helder draws it everywhere.
class TouchMenu implements Markup {
	public static inline var ROW = 44.0;
	public static inline var WIDTH = 250.0;
	// (between the preview and the menu, and the window's edges)
	static inline var GAP = 12.0;
	static inline var EDGE = 8.0;

	// the model's items as choices (Menus.resolve's: labels, enabled and
	// checked as the handler that would take each says), each dispatched
	// from from; a submenu's items inline, a line above them; destructive:
	// the actions drawn red
	public static function choices(ui:Ui, items:Array<MenuItem>, ?from:Node, ?destructive:Action->Bool):Array<Choice> {
		var actions:Array<Action> = [];
		var out:Array<Choice> = [];
		function add(list:Array<helder.ui.platform.PlatformMenuItem>, line:Bool) {
			for (it in list) {
				if (it.separator == true) {
					line = true;
					continue;
				}
				if (it.items != null) {
					add(it.items, true);
					line = true;
					continue;
				}
				var a = actions[it.id];
				out.push({
					label: it.label,
					checked: it.checked == true,
					disabled: it.disabled == true,
					destructive: destructive != null && destructive(a),
					separated: line && out.length > 0,
					run: () -> ui.dispatchAction(a, from != null && from.ui == ui ? from : null)
				});
				line = false;
			}
		}
		add(Menus.resolve(ui, items, from, actions), false);
		return out;
	}

	// opens the menu for what is at rect (window points): its preview there
	// when given; onClose once it is gone. The popup (ui.close(p) closes it
	// too, onClose not called)
	public static function open(ui:Ui, choices:Array<Choice>, rect:Rect, ?preview:Any, blur = true,
			?theme:helder.ui.StyleSheet, ?onClose:Void->Void):Popup {
		var p = new Popup("touch-menu-layer");
		p.modal = true;
		p.style.background = helder.gfx.Color.TRANSPARENT;
		if (theme != null) p.theme = theme;
		var dispose:Null<Void->Void> = null;
		function close() {
			if (p.ui != null) ui.close(p);
			if (dispose != null) dispose();
			dispose = null;
			if (onClose != null) onClose();
		}
		p.onDismiss = close;
		var at = place(ui, choices, rect, preview != null);
		var picked = (c:Choice) -> {
			close();
			c.run();
		};
		dispose = Render.render(<Layer at={at} choices={choices} preview={preview} blur={blur} onPick={picked} onClose={close}/>, p);
		ui.open(p);
		return p;
	}

	// (where the preview and the menu go)
	static function place(ui:Ui, choices:Array<Choice>, r:Rect, lifted:Bool):Placed {
		var safe = SafeArea.insets.peek();
		var top = safe.top + EDGE, bottom = ui.height - safe.bottom - EDGE;
		var mh = 0.0;
		for (c in choices)
			mh += ROW + (c.separated == true ? 8 : 0);
		var mw = Math.min(WIDTH, ui.width - 2 * EDGE);
		var ph = lifted ? Math.min(r.height, Math.max(0, bottom - top - mh - GAP)) : 0.0;
		var pw = lifted && r.height > 0 ? r.width * ph / r.height : 0.0;
		var py = r.y, my = 0.0;
		if (lifted) {
			// (under the preview, which moves up to make room; above it where it is low)
			py = Math.max(top, Math.min(r.y, bottom - mh - GAP - ph));
			my = py + ph + GAP;
		} else {
			my = r.y + r.height + EDGE + mh <= bottom ? r.y + r.height + EDGE : Math.max(top, r.y - EDGE - mh);
		}
		var px = r.x + (r.width - pw) / 2;
		// (lined up with the preview's nearer edge)
		var cx = r.x + r.width / 2;
		var mx = cx < ui.width / 2 ? r.x : r.x + r.width - mw;
		mx = Math.max(EDGE, Math.min(mx, ui.width - EDGE - mw));
		return {px: px, py: py, pw: pw, ph: ph, mx: mx, my: my, mw: mw};
	}

	static function Layer(props:{at:Placed, choices:Array<Choice>, preview:Null<Any>, blur:Bool, onPick:Choice->Void, onClose:Void->Void}):UiView {
		var a = props.at;
		return <view tag="touch-menu-layer" position="absolute" left={0} top={0} right={0} bottom={0} onKeyDown={e -> if (e.key == Key.ESCAPE) props.onClose()}>
			{props.blur ? <glass slot="touch-menu-backdrop" position="absolute" left={0} top={0} right={0} bottom={0} radius={0} tint="#00000040" transition="fade"
				onClick={_ -> props.onClose()}/> : <view tag="touch-menu-backdrop" position="absolute" left={0} top={0} right={0} bottom={0}
				onClick={_ -> props.onClose()}/>}
			{props.preview != null ? <view slot="touch-menu-preview" position="absolute" left={a.px} top={a.py} width={a.pw} height={a.ph} overflow="hidden"
				transition="fade scale" onClick={_ -> props.onClose()}>{props.preview}</view> : null}
			<view slot="touch-menu" tag="touch-menu" role="menu" position="absolute" left={a.mx} top={a.my} width={a.mw} overflow="hidden" transition="fade scale">
				{[for (c in props.choices) <Item choice={c} onPick={props.onPick}/>]}
			</view>
		</view>;
	}

	static function Item(props:{choice:Choice, onPick:Choice->Void}):UiView {
		var c = props.choice;
		return <view:button slot={c.destructive == true ? "touch-menu-item-danger" : "touch-menu-item"} tag={"menu-" + c.label} role="menuitem"
			label={c.label} focusable={c.disabled != true} data-selected={c.checked == true}
			data-disabled={c.disabled == true} margin-top={c.separated == true ? 8 : 0}
			onPress={() -> if (c.disabled != true) props.onPick(c)}>
			<text grow={1}>{c.label}</text>
			{c.checked == true ? <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"
				width={18} height={18}><path d="M20 6 9 17l-5-5"/></svg> : null}
		</view:button>;
	}
}

// (a touch menu's places: the preview's box, the menu's top left and width)
private typedef Placed = {px:Float, py:Float, pw:Float, ph:Float, mx:Float, my:Float, mw:Float};
