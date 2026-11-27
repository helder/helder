package helder.css;

import helder.css.CssCounters;
import helder.dom.Element;

// What the box tree asks of counters and generated content, in tree order
// (CssCounters; CssNoCounters for a program whose sheets set none: no
// generated content, list items, counters, quotes, strings or bookmarks,
// so that it links none of them: DocumentApp chooses).
interface CssCounting {
	function enter(el:Element, ?pseudo:String):Void;
	function exit(el:Element, ?pseudo:String):Void;
	function value(name:String):Int;
	function content(el:Element, ?pseudo:String):Null<Array<CssGeneratedPart>>;
	function strings(el:Element, page:Int = 0, pages:Int = 0):Array<{name:String, value:String}>;
	function bookmark(el:Element):Null<CssBookmark>;
	function resolveTargets(pageOf:Element->Int):Void;
	function marker(el:Element, ?pseudo:String):Null<Array<CssGeneratedPart>>;
	// a number in a counter style (none, symbols(), a name)
	function format(v:Int, style:String):String;
	// a number as a list item's marker in list-style-type's style
	function listMarker(v:Int, type:String):String;
}
