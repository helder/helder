package helder.view;

// Markup's words, one table for every language and renderer: the elements
// (helder's own, and HTML's names that mean something, each made as one of
// helder's), their attributes and events, the node a ref gets, and a hint
// for every spelling that is not one of them. Plan checks a literal's
// elements against it (Haxe's macro, TypeScript's lowering), NodeRenderer
// a name known only when it runs (a spread, a studio design), helder.web
// realises the elements as a page's, helder.typescript declares them.
// Attributes are camel, as React Native writes them: style properties
// CSS's names (flexGrow, borderRadius), the others HTML's (tabIndex,
// readOnly) or helder's own (dragRegion); ARIA's and data-* as HTML spells
// them. Plain Haxe: no macro API.
class Vocabulary {
	// helder's own elements
	public static final PRIMITIVES = ["view", "text", "scroll", "image", "icon", "field", "glass", "video", "webview"];

	static final primitives = [for (p in PRIMITIVES) p => true];

	// HTML's names, each made as a primitive (its base), what it is to
	// assistive technology (role, a heading's level) the element's own
	public static final TAGS:Map<String, Tag> = [
		"button" => {base: "view", role: "Button"},
		"nav" => {base: "view", role: "Navigation"},
		"main" => {base: "view", role: "Main"},
		"section" => {base: "view", role: "Region"},
		"header" => {base: "view", role: "Banner"},
		"footer" => {base: "view", role: "ContentInfo"},
		"article" => {base: "view", role: "Article"},
		"aside" => {base: "view", role: "Complementary"},
		"form" => {base: "view", role: "Form"},
		"ul" => {base: "view", role: "List"},
		"ol" => {base: "view", role: "List"},
		"li" => {base: "view", role: "ListItem"},
		"fieldset" => {base: "view", role: "Group"},
		"p" => {base: "text"},
		"h1" => {base: "text", role: "Heading", level: 1},
		"h2" => {base: "text", role: "Heading", level: 2},
		"h3" => {base: "text", role: "Heading", level: 3},
		"h4" => {base: "text", role: "Heading", level: 4},
		"h5" => {base: "text", role: "Heading", level: 5},
		"h6" => {base: "text", role: "Heading", level: 6},
		"label" => {base: "text", role: "Label"},
		"legend" => {base: "text"},
		"a" => {base: "text", role: "Link"},
		"strong" => {base: "text"},
		"em" => {base: "text"},
		"code" => {base: "text"},
		"textarea" => {base: "field"}
	];

	// the style properties: CSS's names in camel where CSS has the property,
	// helder's own else (ring*, corners, borders, lineHeightPx...); Style's
	// fields, which AttrMacro checks this against
	public static final STYLES = [
		"display", "flexDirection", "flexWrap", "alignItems", "alignSelf", "justifyContent", "alignContent", "flexGrow", "flexShrink",
		"flexBasis", "gap", "rowGap", "columnGap", "width", "height", "minWidth", "minHeight", "maxWidth", "maxHeight", "padding", "margin",
		"borderWidth", "borderColor", "borderStyle", "borderRadius", "background", "shadows", "outline", "opacity", "overflow", "position",
		"top", "right", "bottom", "left", "zIndex", "color", "fontSize", "fontWeight", "fontFamily", "fontStyle", "lineHeight", "letterSpacing",
		"textAlign", "textWrap", "textOverflow", "lineClamp", "textDecoration", "cursor", "pointerEvents", "direction", "fontVariantNumeric",
		"aspectRatio", "scrollbarWidth", "justifyItems", "justifySelf", "gridTemplateColumns", "gridTemplateRows", "gridTemplateAreas",
		"gridAutoColumns", "gridAutoRows", "gridAutoFlow", "gridColumn", "gridRow", "gridArea", "visibility", "userSelect", "textTransform",
		"wordSpacing", "overflowWrap", "wordBreak", "hyphens", "fontFeatureSettings", "order", "textDecorationColor", "textDecorationThickness",
		"textUnderlineOffset", "fieldSizing", "outlineStyle", "scrollbarColor", "scrollbarTrackColor", "textShadow", "transform",
		"transformOrigin", "transition", "backgroundImage", "backgroundColor", "flex", "inset"
	];

	// the attributes every element takes, besides the style properties,
	// ARIA's (aria-*), data-*, key, ref and style
	public static final COMMON = [
		"id", "class", "role", "hidden", "disabled", "required", "tabIndex", "autoFocus", "focusable", "selectable", "body",
		"host", "group", "peer", "theme", "tag", "states", "keyContext", "actions", "trackFocus", "dragRegion", "dragData", "panAxis", "panMinPointers",
		"motion", "motionLayout", "motionOpacity", "motionColor", "motionTransform", "motionRadius", "motionPresence", "lead", "trail", "instant",
		"matched", "ride", "lang"
	];

	// the attributes of some elements: by primitive (each element made as it
	// takes them) or by tag
	public static final OWN:Map<String, Array<String>> = [
		"view" => ["glassSpacing"],
		"text" => ["text"],
		"image" => ["src", "objectFit", "objectPosition", "mirrored"],
		"icon" => ["name", "mirrored"],
		"field" => [
			"value", "placeholder", "type", "readOnly", "maxLength", "spellCheck", "inputMode", "autoComplete", "keyboard", "enterKeyHint",
			"autoCapitalize", "autoCorrect"
		],
		"textarea" => ["rows"],
		"webview" => ["src", "html", "content", "inspectable", "zoom", "transparent", "backGesture"],
		"glass" => ["tint", "interactive"],
		"video" => ["src", "objectFit", "autoPlay", "loop", "muted", "volume", "playbackRate", "layer"],
		"a" => ["href"],
		"label" => ["for"]
	];

	// ARIA's attributes that are the node's Semantics (another aria-* is a
	// theme's data only, as data-* is)
	public static final ARIA = [
		"aria-label", "aria-description", "aria-checked", "aria-pressed", "aria-selected", "aria-expanded", "aria-hidden", "aria-disabled",
		"aria-level", "aria-valuenow", "aria-valuemin", "aria-valuemax", "aria-valuetext", "aria-live", "aria-multiselectable", "aria-current",
		"aria-invalid", "aria-required", "aria-modal", "aria-posinset", "aria-setsize"
	];

	// the events every element has (helder.ui.view.NodeEvents), and some elements' own
	public static final EVENTS = [
		"onPress", "onPointerDown", "onPointerUp", "onPointerMove", "onPointerEnter", "onPointerLeave", "onPointerCancel", "onLostPointerCapture",
		"onWheel", "onKeyDown", "onKeyUp", "onTextInput", "onComposition", "onInput", "onFocus", "onBlur", "onFocusIn", "onFocusOut", "onDragStart",
		"onDragOver", "onDragLeave", "onDrop", "onDragEnd", "onResize", "onTap", "onLongPress", "onPan", "onPinch", "onScale"
	];

	// (by primitive, or by tag over it: a text area has no Enter of its own)
	static final events = [for (e in EVENTS) e => true];

	public static final OWN_EVENTS:Map<String, Array<String>> = [
		"field" => ["onSubmit"],
		"textarea" => [],
		"webview" => ["onMessage", "onNavigate", "onUrlChange", "onLoad", "onTitle", "onProgress", "onLoadError", "onConsole", "onCrash"],
		"video" => ["onLoaded", "onEnded", "onError", "onTime"]
	];

	// (the structure typing an element's own events, beside NodeEvents: its package's)
	public static final EVENT_TYPES:Map<String, String> = ["video" => "helder.media.ui.VideoEvents"];

	// the node an element's ref gets where ui renders it (a neutral
	// literal's, for every renderer: helder.ui.Part)
	public static final NODES:Map<String, String> = [
		"view" => "helder.ui.Node", "scroll" => "helder.ui.Node", "text" => "helder.ui.TextNode", "image" => "helder.ui.ImageNode",
		"icon" => "helder.ui.ImageNode", "field" => "helder.ui.controls.TextField", "textarea" => "helder.ui.controls.TextArea",
		"glass" => "helder.ui.Glass", "webview" => "helder.ui.platform.WebView", "video" => "helder.media.ui.VideoNode"
	];

	public static inline final PART = "helder.ui.Part";

	// written as HTML writes them, given React's names: a warning, and set
	public static final REACT:Map<String, String> = ["htmlFor" => "for", "className" => "class"];

	// helder's old names, and what they are now
	static final RENAMED:Map<String, String> = [
		// (the style properties CSS has)
		"direction" => "flexDirection", "wrap" => "flexWrap", "justify" => "justifyContent", "grow" => "flexGrow", "shrink" => "flexShrink",
		"basis" => "flexBasis", "radius" => "borderRadius", "shadow" => "boxShadow", "italic" => "fontStyle", "dir" => "direction",
		"maxLines" => "lineClamp", "fit" => "objectFit", "backgroundColor" => "background",
		// (HTML's, in camel)
		"autofocus" => "autoFocus", "readonly" => "readOnly", "maxlength" => "maxLength", "spellcheck" => "spellCheck",
		"inputmode" => "inputMode", "autocomplete" => "autoComplete", "enterkey" => "enterKeyHint", "autocapitalize" => "autoCapitalize",
		"autocorrect" => "autoCorrect", "tabindex" => "tabIndex", "autoplay" => "autoPlay", "rate" => "playbackRate", "spacing" => "glassSpacing",
		// (assistive technology's: ARIA's)
		"label" => "aria-label", "description" => "aria-description", "checked" => "aria-checked", "pressed" => "aria-pressed",
		"selected" => "aria-selected", "expanded" => "aria-expanded", "level" => "aria-level", "live" => "aria-live",
		"multiselectable" => "aria-multiselectable", "current" => "aria-current", "invalid" => "aria-invalid", "modal" => "aria-modal",
		"valueNow" => "aria-valuenow", "valueMin" => "aria-valuemin", "valueMax" => "aria-valuemax", "valueText" => "aria-valuetext",
		"posInSet" => "aria-posinset", "setSize" => "aria-setsize"
	];

	// the tags that are not helder's, and what they are
	static final TAG_HINTS:Map<String, String> = [
		"div" => "view", "span" => "text", "img" => "image", "input" => "field", "b" => "strong", "i" => "em", "glass-group" => "view glassSpacing={n}"
	];

	// a tag's primitive (a primitive's itself); null: not one of markup's elements
	public static function base(tag:String):Null<String> {
		if (primitives.exists(tag)) return tag;
		var t = TAGS.get(tag);
		return t == null ? null : t.base;
	}

	// whether tag is one of markup's elements
	public static inline function isElement(tag:String):Bool
		return base(tag) != null;

	// the error for a tag none of ui's elements is (null: it is one); web: the
	// element may be a page's own (an agnostic literal's)
	public static function tag(name:String, web = false):Null<String> {
		if (isElement(name)) return null;
		var colon = name.indexOf(":");
		if (colon > 0 && ["view", "text", "field"].indexOf(name.substr(0, colon)) >= 0) {
			var own = name.substr(colon + 1);
			var meant = isElement(own) ? own : TAG_HINTS.exists(own) ? TAG_HINTS[own] : name.substr(0, colon);
			return "markup: <" + name + "> is <" + meant + "> (HTML's names, no prefix)";
		}
		if (web) return null;
		var hint = TAG_HINTS.get(name);
		if (name == "glass-group") return "markup: <glass-group spacing={n}> is <view glassSpacing={n}>: any view groups its glass";
		if (hint != null) return "markup: <" + name + "> is no ui element; did you mean <" + hint + ">?";
		return "markup: <" + name + "> is web-only (a page's, helder.web's DomRenderer): ui's elements are " + PRIMITIVES.join(", ") + " and "
			+ sorted([for (k in TAGS.keys()) k]).join(", ");
	}

	// whether tag takes the attribute name (a map's lookup: the names every
	// element takes, then the tag's own, each made once)
	public static function takes(tag:String, name:String):Bool {
		if (everyone().exists(name)) return true;
		if (StringTools.startsWith(name, "data-") || StringTools.startsWith(name, "aria-")) return true;
		var o = owns.get(tag);
		if (o == null) owns.set(tag, o = [for (n in own(tag)) n => true]);
		return o.exists(name);
	}

	static var every:Null<Map<String, Bool>> = null;
	static final owns = new Map<String, Map<String, Bool>>();

	static function everyone():Map<String, Bool> {
		if (every != null) return every;
		var m = new Map<String, Bool>();
		for (n in STYLES.concat(COMMON))
			m.set(n, true);
		return every = m;
	}

	// (an element's own attributes: its primitive's, then its tag's)
	static function own(tag:String):Array<String> {
		var b = base(tag), out = [];
		if (b != null && OWN.exists(b)) out = out.concat(OWN[b]);
		if (tag != b && OWN.exists(tag)) out = out.concat(OWN[tag]);
		// (a text area is a field)
		return out;
	}

	// the error for an attribute tag does not take (null: it takes it)
	public static function attribute(tag:String, name:String):Null<String> {
		if (REACT.exists(name) || takes(tag, name)) return null;
		var renamed = RENAMED.get(name);
		if (renamed != null && takes(tag, renamed)) return "markup: " + name + " is " + renamed + " (" + why(renamed) + ")";
		var camel = camel(name);
		if (camel != name) {
			var meant = takes(tag, camel) ? camel : RENAMED.get(camel);
			if (meant != null && takes(tag, meant)) return "markup: " + name + " is written " + meant + " (camel, as CSS's and HTML's are in JavaScript)";
		}
		var lower = name.toLowerCase();
		if (lower != name && RENAMED.exists(lower) && takes(tag, RENAMED[lower])) return "markup: " + name + " is " + RENAMED[lower] + " (" + why(RENAMED[lower]) + ")";
		var whose = [for (t in sorted([for (k in OWN.keys()) k])) if (OWN[t].indexOf(name) >= 0 || RENAMED.exists(name) && OWN[t].indexOf(RENAMED[name]) >= 0) t];
		if (whose.length > 0)
			return "markup: <" + tag + "> has no attribute " + name + " (" + [for (w in whose) "<" + w + ">'s"].join(", ") + ")";
		var meant = nearest(name, STYLES.concat(COMMON).concat(own(tag)).concat(ARIA));
		return "markup: <" + tag + "> has no attribute " + name + (meant == null ? "" : "; did you mean " + meant + "?");
	}

	// (what a new name is)
	static function why(name:String):String
		return StringTools.startsWith(name, "aria-") ? "HTML's ARIA attribute" : STYLES.indexOf(name) >= 0 || StringTools.startsWith(name, "object") ? "CSS's name, in camel" : "HTML's name, in camel";

	// the warning for a name React writes (htmlFor, className), null for another
	public static function react(name:String):Null<String>
		return REACT.exists(name) ? "markup: " + name + " is " + REACT[name] + " in helder's markup (as HTML writes it)" : null;

	// the name an attribute is set by (React's names as HTML's)
	public static function canonical(name:String):String
		return REACT.exists(name) ? REACT[name] : name;

	// a static value the old name direction took: flexDirection's
	// the error for a static value an attribute does not take as written: the
	// old flex direction, a boolean's "true" or "false" (null: it takes it)
	public static function value(name:String, value:String):Null<String> {
		if (name == "direction" && ["row", "column", "row-reverse", "column-reverse"].indexOf(value) >= 0)
			return "markup: direction=\"" + value + "\" is flexDirection's (direction is the text's, ltr or rtl, as CSS's)";
		if ((value == "true" || value == "false") && booleans.exists(name))
			return "markup: " + name + "=\"" + value + "\" is " + name + "={" + value + "} (a boolean; " + name + " alone is true)";
		return null;
	}

	// the attributes that are booleans (a flag alone true, {false} false)
	public static final BOOLEANS = [
		"hidden", "disabled", "required", "autoFocus", "focusable", "selectable", "body", "dragRegion", "instant", "mirrored", "readOnly",
		"spellCheck", "autoCorrect", "inspectable", "zoom", "transparent", "backGesture", "interactive", "autoPlay", "loop", "muted", "layer"
	];

	static final booleans = [for (b in BOOLEANS) b => true];

	// helder's own elements that are neutral in every literal: those no
	// page's element is named as (video is HTML's too: helder's only where
	// ui's names are, a page's own elsewhere)
	public static function anywhere(tag:String):Bool
		return primitives.exists(tag) && tag != "video";

	// the error for an event tag does not have (null: it has it)
	public static function event(tag:String, name:String):Null<String> {
		if (events.exists(name) || ownEvents(tag).indexOf(name) >= 0) return null;
		if (name == "onClick") return "markup: onClick is a page's; a ui element's press (a click, Enter or Space) is onPress";
		if (name == "onActivate") return "markup: onActivate is onPress";
		var whose = [for (t in sorted([for (k in OWN_EVENTS.keys()) k])) if (OWN_EVENTS[t].indexOf(name) >= 0) t];
		if (whose.length > 0) return "markup: <" + tag + "> has no event " + name + " (" + [for (w in whose) "<" + w + ">'s"].join(", ") + ")";
		var meant = nearest(name, EVENTS.concat(ownEvents(tag)));
		return "markup: <" + tag + "> has no event " + name + (meant == null ? "" : "; did you mean " + meant + "?");
	}

	public static function ownEvents(tag:String):Array<String> {
		if (OWN_EVENTS.exists(tag)) return OWN_EVENTS[tag];
		var b = base(tag);
		return b != null && OWN_EVENTS.exists(b) ? OWN_EVENTS[b] : [];
	}

	// the node tag's ref gets where ui renders it
	public static function node(tag:String):String
		return NODES.exists(tag) ? NODES[tag] : NODES.get(base(tag) ?? "view") ?? "helder.ui.Node";

	public static function camel(n:String):String {
		if (n.indexOf("-") < 0) return n;
		var parts = n.split("-");
		return parts[0] + [for (p in parts.slice(1)) p.charAt(0).toUpperCase() + p.substr(1)].join("");
	}

	public static function kebab(name:String):String
		return ~/([A-Z])/g.map(name, r -> "-" + r.matched(1).toLowerCase());

	// (the nearest of names by Levenshtein's distance, under 4; null: none)
	public static function nearest(name:String, names:Array<String>):Null<String> {
		var best = 4, meant:Null<String> = null;
		for (n in names) {
			var d = distance(name.toLowerCase(), n.toLowerCase());
			if (d < best) {
				best = d;
				meant = n;
			}
		}
		return meant;
	}

	static function distance(a:String, b:String):Int {
		var prev = [for (j in 0...b.length + 1) j];
		for (i in 1...a.length + 1) {
			var cur = [i];
			for (j in 1...b.length + 1)
				cur.push(Std.int(Math.min(Math.min(cur[j - 1] + 1, prev[j] + 1), prev[j - 1] + (a.charCodeAt(i - 1) == b.charCodeAt(j - 1) ? 0 : 1))));
			prev = cur;
		}
		return prev[b.length];
	}

	static function sorted(a:Array<String>):Array<String> {
		a.sort(Reflect.compare);
		return a;
	}
}

// (role: helder.ui.access.Role's name)
typedef Tag = {base:String, ?role:String, ?level:Int};
