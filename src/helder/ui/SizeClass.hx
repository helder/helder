package helder.ui;

import helder.view.graph.Signal;

// How much room a screen has, by its width in points (UI pixels), as
// iOS's and Android's window size classes: Compact under 600 (a phone, a
// narrow browser tab), Medium to 1024 (a tablet upright, a foldable, split
// view, a narrow desktop window), Expanded from 1024 (a tablet on its side,
// a desktop). current is the current screen's (ScreenContext.sizeClass: its
// surface's, the Ui made last in it as it resizes, a window's, a story's),
// a signal: markup that reads it follows it.
//
//   <Switch>
//     <Match when={SizeClass.current() == Compact}><PhoneShell/></Match>
//     <Match when={true}><DesktopShell/></Match>
//   </Switch>
@:typescript
enum abstract SizeClass(String) to String {
	var Compact = "compact";
	var Medium = "medium";
	var Expanded = "expanded";

	public static inline var MEDIUM = 600.0;
	public static inline var EXPANDED = 1024.0;

	// the current screen's
	public static var current(get, never):Signal<SizeClass>;

	static inline function get_current():Signal<SizeClass>
		return ScreenContext.current.sizeClass;

	// the class of a width in points
	public static function of(width:Float):SizeClass
		return width < MEDIUM ? Compact : width < EXPANDED ? Medium : Expanded;
}
