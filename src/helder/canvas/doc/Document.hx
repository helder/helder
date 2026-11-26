package helder.canvas.doc;

// Pages of recordings (each its own size): a multi-page PDF, an SVG a page.
// What a PDF says beside its pages: links (to a URI or to an anchor),
// anchors (named destinations), bookmarks (the outline, by level), page
// labels and the document's information (the Info dictionary and XMP
// metadata). Pages by index from 0, places in a page's units (y down from
// its top left, as drawn).
class Document {
	public final pages:Array<Recorder> = [];
	public final links:Array<PageLink> = [];
	public final anchors:Array<PageAnchor> = [];
	public final bookmarks:Array<Bookmark> = [];
	public final labels:Array<PageLabel> = [];

	// (null: left out)
	public var title:Null<String> = null;
	public var author:Null<String> = null;
	public var subject:Null<String> = null;
	// as one string, commas between them
	public var keywords:Null<String> = null;
	// what made the content (an app); producer: what wrote the PDF
	public var creator:Null<String> = null;
	public var producer:Null<String> = "helder.canvas";
	// a BCP 47 tag ("en", "nl-BE"): the catalog's /Lang
	public var lang:Null<String> = null;
	public var created:Null<Date> = null;
	public var modified:Null<Date> = null;

	public function new() {}

	public function newPage(width:Int, height:Int):Recorder {
		var r = new Recorder(width, height);
		pages.push(r);
		return r;
	}

	// a rectangle of a page that opens a URI
	public function link(page:Int, x:Float, y:Float, w:Float, h:Float, uri:String)
		links.push({page: page, x: x, y: y, w: w, h: h, uri: uri, name: null});

	// a rectangle of a page that goes to an anchor
	public function linkTo(page:Int, x:Float, y:Float, w:Float, h:Float, name:String)
		links.push({page: page, x: x, y: y, w: w, h: h, uri: null, name: name});

	// a named place a link goes to (the last one of a name wins)
	public function anchor(name:String, page:Int, x:Float, y:Float)
		anchors.push({name: name, page: page, x: x, y: y});

	// an entry of the outline at a depth (1 the top; a deeper one is the last shallower one's child)
	public function bookmark(title:String, level:Int, page:Int, y:Float)
		bookmarks.push({title: title, level: level, page: page, y: y});

	// the pages from this one on numbered in a style ("decimal", "lower-roman", "upper-roman",
	// "lower-alpha", "upper-alpha"; null: the prefix alone) from start, after a prefix
	public function label(page:Int, ?style:String, prefix = "", start = 1)
		labels.push({page: page, style: style, prefix: prefix, start: start});
}

typedef PageLink = {page:Int, x:Float, y:Float, w:Float, h:Float, uri:Null<String>, name:Null<String>};
typedef PageAnchor = {name:String, page:Int, x:Float, y:Float};
typedef Bookmark = {title:String, level:Int, page:Int, y:Float};
typedef PageLabel = {page:Int, style:Null<String>, prefix:String, start:Int};
