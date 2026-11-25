package helder.web;

#if macro
import haxe.macro.Context;
#end
import haxe.macro.Expr;

// The neutral elements (helder.view.Vocabulary's: helder.ui's view, text,
// scroll, image, icon, field, and HTML's names, button, p, h2...:
// single-source components) as the DOM's, for DomRenderer, all at compile
// time: each element its DOM element (HTML's names their own), each
// attribute what it is in a page (slot, variant and size as data-slot,
// data-variant and data-size; tabIndex, readOnly... HTML's attributes;
// ARIA's and data-* as they are; focusable as tabindex; tag (ui's
// Node.find) none; the style properties as inline style, CSS's names),
// each event the DOM's converted to ui's Event (only for the events a
// widget listens to). A name with no DOM form is an error, so that the two
// renderers' vocabularies stay one.
class NeutralMacro {
	#if macro
	// (attributes: their DOM names)
	public static final DATA = ["slot" => "data-slot", "variant" => "data-variant", "size" => "data-size"];
	static final PLAIN = ["role" => "role", "id" => "id", "href" => "href", "for" => "for", "class" => "class", "tabIndex" => "tabindex", "hidden" => "hidden"];
	// (a field's (<field>: an <input>, <textarea>) own attributes; its value
	// Neutral.value, the property; host and focusable ui's only: a page's field is the DOM's own)
	static final FIELD = [
		"placeholder" => "placeholder", "type" => "type", "inputMode" => "inputmode", "autoComplete" => "autocomplete", "maxLength" => "maxlength",
		"rows" => "rows", "readOnly" => "readonly", "spellCheck" => "spellcheck"
	];

	// (its keyboard's, as an input's type, inputmode, enterkeyhint, autocapitalize, autocorrect: Neutral.fieldKind)
	static final KIND = ["keyboard", "enterKeyHint", "autoCapitalize", "autoCorrect"];

	static inline function isField(t:String):Bool
		return t == "field" || t == "textarea";

	// (the style properties CSS has not: helder's own, drawn nodes')
	static final OWN = ["borders", "corners", "ringWidth", "ringColor", "ringOffsetWidth", "ringOffsetColor", "ringInset", "letterSpacingEm", "lineHeightPx",
		"scrollbarTrackColor"];
	// (those whose numbers are lengths, in px)
	static final PX = [
		"width", "height", "minWidth", "maxWidth", "minHeight", "maxHeight", "top", "left", "right", "bottom", "inset", "padding", "paddingTop",
		"paddingRight", "paddingBottom", "paddingLeft", "margin", "marginTop", "marginRight", "marginBottom", "marginLeft", "gap", "rowGap",
		"columnGap", "borderWidth", "borderRadius", "fontSize", "letterSpacing", "wordSpacing", "outlineWidth", "outlineOffset", "flexBasis",
		"textUnderlineOffset", "textDecorationThickness"
	];

	// a style property's CSS property and whether a number is in px (objectFit an image's); null: not one
	public static function css(name:String):Null<{prop:String, px:Bool}> {
		if (name == "objectFit" || name == "objectPosition") return {prop: helder.view.Vocabulary.kebab(name), px: false};
		if (helder.view.Vocabulary.STYLES.indexOf(name) < 0 || OWN.indexOf(name) >= 0) return null;
		var prop = name == "background" ? "background" : name == "lineClamp" ? "-webkit-line-clamp" : helder.view.Vocabulary.kebab(name);
		return {prop: prop, px: PX.indexOf(name) >= 0};
	}

	// (events: the DOM's, and ui's EventType)
	static final EVENTS:Map<String, {dom:String, type:String}> = [
		"onKeyDown" => {dom: "keydown", type: "KeyDown"}, "onKeyUp" => {dom: "keyup", type: "KeyUp"},
		"onPointerDown" => {dom: "pointerdown", type: "PointerDown"}, "onPointerUp" => {dom: "pointerup", type: "PointerUp"},
		"onPointerMove" => {dom: "pointermove", type: "PointerMove"}, "onPointerEnter" => {dom: "pointerenter", type: "PointerEnter"},
		"onPointerLeave" => {dom: "pointerleave", type: "PointerLeave"}, "onPointerCancel" => {dom: "pointercancel", type: "PointerCancel"},
		"onLostPointerCapture" => {dom: "lostpointercapture", type: "LostPointerCapture"}, "onFocus" => {dom: "focus", type: "Focus"},
		"onBlur" => {dom: "blur", type: "Blur"}, "onFocusIn" => {dom: "focusin", type: "FocusIn"}, "onFocusOut" => {dom: "focusout", type: "FocusOut"}
	];

	// the DOM element of a neutral one
	public static function element(tag:Expr):Expr {
		var t = literal(tag);
		// (an icon: an <svg>, its paths its name's)
		if (t == "icon") return macro @:pos(tag.pos) helder.web.Neutral.icon();
		var dom = domName(t, tag.pos);
		// (an image: an <img>, its alternative text none: its own a label's on the element naming it)
		if (t == "image") return macro @:pos(tag.pos) {
			var el = helder.web.DomRenderer.createElement("img");
			(cast el : js.html.Element).setAttribute("alt", "");
			el;
		};
		if (t == "scroll") return macro @:pos(tag.pos) {
			var el = helder.web.DomRenderer.createElement("div");
			(cast el : js.html.Element).style.overflow = "auto";
			el;
		};
		// (a button not a form's submit)
		if (dom == "button") return macro @:pos(tag.pos) {
			var el = helder.web.DomRenderer.createElement("button");
			(cast el : js.html.Element).setAttribute("type", "button");
			el;
		};
		return macro @:pos(tag.pos) helder.web.DomRenderer.createElement($v{dom});
	}

	// (view: div, text: span, scroll: div, field: input, HTML's names their own)
	static function domName(t:String, pos:Position):String {
		switch t {
			case "view" | "scroll": return "div";
			case "text": return "span";
			case "image": return "img";
			case "field": return "input";
			case "glass" | "video" | "webview":
				return Context.error('helder.web: <$t> is ui\'s own, drawn or the system\'s: no DOM element (NeutralMacro)', pos);
			case _:
		}
		if (!helder.view.Vocabulary.TAGS.exists(t)) Context.error('helder.web: no DOM element for the neutral <$t> (NeutralMacro)', pos);
		return t;
	}

	// an attribute set (a value or a signal's at the time)
	public static function property(el:Expr, tag:Expr, name:Expr, v:Expr):Expr {
		// (a mapped name set once: Neutral's setter called with its DOM name)
		var n = literal(name), t = literal(tag);
		var dom = mapped(t, n);
		if (dom != null) return macro @:pos(name.pos) helder.web.Neutral.attr($el, $v{dom}, $v);
		var c = css(n);
		if (c != null) return macro @:pos(name.pos) helder.web.Neutral.css($el, $v{c.prop}, $v, $v{c.px});
		var f = setterFor(t, n, name.pos);
		return f == null ? macro {} : macro @:pos(name.pos) $f($el, $name, $v);
	}

	// the name a bound attribute's setter gets: a mapped one's DOM name or CSS
	// property (its setter Neutral's one for all), else the neutral name
	public static function name(tag:Expr, name:Expr):Expr {
		var n = literal(name), t = literal(tag);
		var dom = mapped(t, n), c = css(n);
		return macro @:pos(name.pos) $v{dom ?? (c != null ? c.prop : n)};
	}

	// (an attribute's DOM name when it is one set as it is: data-*, aria-*, role, id...)
	static function mapped(t:String, n:String):Null<String> {
		if (t == "icon" && n == "mirrored") return "data-mirrored";
		if (t == "icon" && n == "name" || n == "tag") return null;
		if (isField(t) && FIELD.exists(n)) return FIELD[n];
		if (t == "image" && n == "src") return "src";
		if (DATA.exists(n)) return DATA[n];
		if (PLAIN.exists(n)) return PLAIN[n];
		return StringTools.startsWith(n, "data-") || StringTools.startsWith(n, "aria-") ? n : null;
	}

	// the function setting an attribute, (el, name, v): what markup binds a signal with
	public static function setter(tag:Expr, name:Expr):Expr {
		var f = setterFor(literal(tag), literal(name), name.pos);
		return f == null ? macro @:pos(name.pos) function(el:Dynamic, name:String, v:Dynamic) {} : f;
	}

	static function setterFor(tag:String, name:String, pos:Position):Null<Expr> {
		if (tag == "icon" && name == "name") return macro @:pos(pos) helder.web.Neutral.iconName;
		// (ui's own: Node.find's tag, a group's and a peer's markers)
		if (name == "tag" || name == "group" || name == "peer") return null;
		if (isField(tag) && name == "value") return macro @:pos(pos) helder.web.Neutral.value;
		if (isField(tag) && (name == "host" || name == "focusable")) return null;
		if (isField(tag) && KIND.indexOf(name) >= 0) return macro @:pos(pos) helder.web.Neutral.fieldKind;
		// (each kind one function, (el, name, v), name the DOM's (NeutralMacro.name): Neutral)
		if (mapped(tag, name) != null) return macro @:pos(pos) helder.web.Neutral.attr;
		var c = css(name);
		if (c != null) return c.px ? macro @:pos(pos) helder.web.Neutral.cssPx : macro @:pos(pos) helder.web.Neutral.cssValue;
		if (name == "focusable") return macro @:pos(pos) helder.web.Neutral.focusable;
		if (name == "autoFocus") return macro @:pos(pos) helder.web.Neutral.autofocus;
		if (name == "states") return macro @:pos(pos) helder.web.Neutral.states;
		if (name == "disabled") return macro @:pos(pos) helder.web.Neutral.disabled;
		return Context.error('helder.web: <$tag>\'s attribute $name has no DOM form (NeutralMacro)', pos);
	}

	// a listener: the DOM's event as ui's Event; onPress a click (a button's
	// or a link's own, Enter or Space too on another element)
	public static function listen(el:Expr, tag:Expr, name:Expr, h:Expr):Expr {
		var t = literal(tag), n = literal(name);
		if (n == "onPress") {
			var native = ["button", "a"].indexOf(t) >= 0;
			return macro @:pos(name.pos) helder.web.Neutral.press($el, $h, $v{native});
		}
		// (a field's text changed: the DOM's input, its text the value)
		if (n == "onInput" && isField(t)) return macro @:pos(name.pos) helder.web.Neutral.input($el, $h);
		if (n == "onSubmit" && isField(t)) return macro @:pos(name.pos) helder.web.Neutral.submit($el, $h);
		if (!EVENTS.exists(n)) return Context.error('helder.web: <$t>\'s event $n has no DOM form (NeutralMacro)', name.pos);
		var e = EVENTS[n], type = e.type;
		if (e.dom == "keydown" || e.dom == "keyup") return macro @:pos(name.pos) helder.web.Neutral.onKey($el, $v{e.dom}, $h, helder.ui.EventType.$type);
		return macro @:pos(name.pos) helder.web.Neutral.on($el, $v{e.dom}, $h, helder.ui.EventType.$type);
	}

	static function literal(e:Expr):String
		return switch e.expr {
			case EConst(CString(s, _)): s;
			case _: Context.error("helder.web: a neutral element's tag and attribute names are literal", e.pos);
		}
	#end
}
