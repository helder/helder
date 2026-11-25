package helder.ui.platform.web;

import hxmc.unsafe.*;

// The browser's scroll views (web.Scroll): imports of "hxmc_ui" too.
@:hxmc.c @:hxmc.lib("hxmc_ui") extern class Scrolls {
	// the scrollers' changes (JSON) for the canvas's layer of scroll views
	static function scroll_update(canvas:Int, json:CString):Void;
	// the next scroll of a view into p (its id, its offsets in 1/256 ui points); 0: none
	static function scroll_event(p:Ptr<Int32>):Int;
}
