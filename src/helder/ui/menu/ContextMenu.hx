package helder.ui.menu;

import helder.ui.Node;
import helder.ui.actions.Actions;
import helder.os.PointerType;
import helder.ui.SizeClass;
import helder.ui.gesture.LongPress;
import helder.ui.menu.Menu;
import helder.ui.menu.TouchMenu;

// A node's context menu for touch and the mouse: a long press (half a
// second, LongPress; the mouse's left button held still too, in a Compact
// window only: a phone's layout, where it stands for the finger; on a
// desktop's a held click stays a click) lifts its preview (a view of the caller's: the
// node's look again, a larger thumbnail; none: the menu alone) over the
// blurred window, the menu under it (TouchMenu), with the platform's tap
// of haptics (helder.os.Haptics: iOS's, Android's, a browser's
// vibration); a right click is the desktop's menu at the pointer
// (Menus.popup: the platform's own where it has one). Items are
// helder.ui.menu's model, made when it opens, dispatched from the node;
// destructive says which are drawn red.
//
//   <view ref={n -> ContextMenu.attach(n, () -> [Item("Open", Open), Item("Delete", Delete)], () -> <Tile file={f}/>)}/>
class ContextMenu {
	// attaches it (detached when the owner is disposed, or by what it returns)
	public static function attach(n:Node, items:Void->Array<MenuItem>, ?preview:Void->Any, ?destructive:Action->Bool, ?onOpen:Void->Void):Void->Void {
		var press = n.addGesture(new MenuPress());
		var down = n.onPointerDown;
		var open:Null<Popup> = null;
		press.onGesture = g -> {
			if (g.state != Began || n.ui == null || open != null) return;
			#if (target.name == "hxmc")
			helder.os.Haptics.tap();
			#end
			if (onOpen != null) onOpen();
			var ui = n.ui;
			open = TouchMenu.open(ui, TouchMenu.choices(ui, items(), n, destructive), n.windowBounds(), preview == null ? null : preview(), true, n.sheet(),
				() -> open = null);
		};
		n.onPointerDown = e -> {
			if (down != null) down(e);
			if (e.defaultPrevented || e.button != 3 || n.ui == null) return;
			if (onOpen != null) onOpen();
			Menus.popup(n.ui, items(), e.x, e.y, n);
		};
		function detach() {
			n.removeGesture(press);
			if (open != null && open.ui != null) open.ui.close(open);
			open = null;
		}
		if (helder.view.graph.Owner.current != null) helder.view.graph.Graph.onCleanup(detach);
		return detach;
	}
}

// (a long press, the mouse's too in a Compact window: on a wider one a
// click held still over a sidebar's row opened the phone's menu over a
// window-wide glass)
private class MenuPress extends LongPress {
	public function new() {
		super();
		mouse = true;
	}

	override function wants(type:PointerType, button:Int):Bool {
		if (!super.wants(type, button)) return false;
		var ui = node?.ui;
		return type != Mouse || ui != null && SizeClass.of(ui.width) == Compact;
	}
}
