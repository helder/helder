package helder.ui;

import helder.view.RootView;

// A preview host's way into a program (helder.scenario): while on (a
// studio host build's, -D helder.scenarios), main runs once as always but
// UiWindow.run opens no window and does not block: it keeps its root,
// which each scenario renders in a screen of its own, where <Surface>
// gives its props (its size, its children) to surface, the screen being
// mounted, instead of opening a window. helder run and Play are never on
class Hosting {
	public static var on = #if helder.scenarios true #else false #end;
	// what main gave UiWindow.run (null: not yet)
	public static var root:Null<RootView> = null;
	// the screen a <Surface> renders into now (null: none being mounted)
	public static var surface:Null<UiWindow.SurfaceProps->Void> = null;
}
