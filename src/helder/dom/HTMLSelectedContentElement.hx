package helder.dom;

// HTML's selectedcontent element: a copy of its select's selected option's
// children (HTML 4.10.17).
@:allow(helder.dom)
class HTMLSelectedContentElement extends Element {
	var disabled = false;
	var cachedSelect:Null<HTMLSelectElement> = null;

	function new(doc:Document, prefix:Null<String>) {
		super(doc, "selectedcontent", Namespaces.HTML, prefix);
		doc.selects++;
	}

	// recalculate its disabledness: the nearest select, if no other select, option or selectedcontent is between
	function recalculate():Null<HTMLSelectElement> {
		var nearest:Null<HTMLSelectElement> = null;
		disabled = false;
		var a = parentElement;
		while (a != null) {
			if (a.isHTML(Tags.SELECT)) {
				if (nearest == null) nearest = cast a else {
					disabled = true;
					break;
				}
			} else if (a.isHTML(Tags.OPTION) || Std.isOfType(a, HTMLSelectedContentElement)) {
				disabled = true;
				break;
			}
			a = a.parentElement;
		}
		cachedSelect = nearest;
		return nearest;
	}

	override function insertionSteps() {
		var select = recalculate();
		if (!get_isConnected() || disabled || select == null || select.multiple()) return;
		select.queueUpdate();
	}

	override function postConnection() {
		var s = cachedSelect;
		if (s != null && s.pending) s.updateSelectedContent();
	}

	override function removingSteps()
		recalculate();

	override function movingSteps() {
		var old = cachedSelect, wasDisabled = disabled;
		var select = recalculate();
		if (disabled || select == null || select.multiple()) return;
		if (!wasDisabled && select == old) return;
		select.queueUpdate();
	}

	// clone an option into it (null: clear it)
	function show(option:Null<HTMLOptionElement>) {
		if (option == null) {
			Node.replaceAll(null, this);
			return;
		}
		var fragment = new DocumentFragment(option.doc);
		var c = option.firstChild;
		while (c != null) {
			Node.insert(Node.clone(c, c.doc, true, null), fragment, null);
			c = c.nextSibling;
		}
		var removed = [], n = fragment.firstChild;
		while (n != null) {
			if (n.nodeType == Node.ELEMENT_NODE) {
				var e:Element = cast n;
				var inert = e.ns == Element.HTML && (e.tag == Tags.SCRIPT || e.tag == Tags.FRAME || e.tag == Tags.IFRAME || e.tag == Tags.EMBED || e.tag == Tags.OBJECT);
				if (inert || e.ns == Element.SVG && e.localName == "script") removed.push(e);
			}
			n = Node.following(n, fragment);
		}
		for (e in removed)
			if (e.parentNode != null) Node.remove(e);
		Node.replaceAll(fragment, this);
	}
}
