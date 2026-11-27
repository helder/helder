package helder.css;

import helder.css.CssCounters;
import helder.dom.Element;

// Counting for a program whose sheets set no generated content, list
// items, counters, quotes, strings or bookmarks (DocumentApp): none of
// them made, CssCounters and the counter styles not linked.
class CssNoCounters implements CssCounting {
	public function new() {}

	public function enter(el:Element, ?pseudo:String) {}

	public function exit(el:Element, ?pseudo:String) {}

	public function value(name:String):Int
		return 0;

	public function content(el:Element, ?pseudo:String):Null<Array<CssGeneratedPart>>
		return null;

	public function strings(el:Element, page = 0, pages = 0):Array<{name:String, value:String}>
		return [];

	public function bookmark(el:Element):Null<CssBookmark>
		return null;

	public function resolveTargets(pageOf:Element->Int) {}

	public function marker(el:Element, ?pseudo:String):Null<Array<CssGeneratedPart>>
		return null;

	public function format(v:Int, style:String):String
		return Std.string(v);

	public function listMarker(v:Int, type:String):String
		return "";
}
