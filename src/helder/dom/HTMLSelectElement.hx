package helder.dom;

using StringTools;

// HTML's select element, for its options' selectedness and its
// selectedcontent (HTML 4.10.7).
@:allow(helder.dom)
class HTMLSelectElement extends Element {
	var pending = false;

	function new(doc:Document, prefix:Null<String>) {
		super(doc, "select", Namespaces.HTML, prefix);
		doc.selects++;
	}

	inline function multiple():Bool
		return byNamespace(null, "multiple") != null;

	function displaySize():Int {
		var size = getAttributeNS(null, "size");
		if (size != null) {
			var m = ~/^[\t\n\x0C\r ]*\+?([0-9]+)/;
			if (m.match(size)) return Std.parseInt(m.matched(1));
		}
		return multiple() ? 4 : 1;
	}

	// the list of options
	function options():Array<HTMLOptionElement> {
		var out:Array<HTMLOptionElement> = [];
		var n = firstChild;
		while (n != null) {
			var skip = false;
			if (n.nodeType == Node.ELEMENT_NODE) {
				var e:Element = cast n;
				if (e.isHTML(Tags.OPTION)) out.push(cast e);
				if (e.ns == Element.HTML) switch e.tag {
					case Tags.SELECT | Tags.HR | Tags.OPTION: skip = true;
					case Tags.OPTGROUP:
						var p = e.parentElement;
						while (p != null && p != this) {
							if (p.isHTML(Tags.OPTGROUP)) skip = true;
							p = p.parentElement;
						}
					case _: if (e.localName == "datalist") skip = true;
				}
			}
			n = skip ? Node.skip(n, this) : Node.following(n, this);
		}
		return out;
	}

	// the selectedness setting algorithm: true when an option's selectedness changed
	function selectednessSetting():Bool {
		if (multiple()) return false;
		var changed = false;
		var firstEnabled:Null<HTMLOptionElement> = null, lastSelected:Null<HTMLOptionElement> = null;
		for (o in options()) {
			if (o.selectedness) {
				if (lastSelected != null) {
					lastSelected.selectedness = false;
					changed = true;
				}
				lastSelected = o;
			}
			if (firstEnabled == null && !o.disabled()) firstEnabled = o;
		}
		if (lastSelected == null && firstEnabled != null && displaySize() == 1) {
			firstEnabled.selectedness = true;
			changed = true;
		}
		return changed;
	}

	function resetSelectedness(changed:Bool) {
		if (selectednessSetting()) changed = true;
		if (changed) updateSelectedContent();
	}

	function selectedContents():Array<HTMLSelectedContentElement> {
		var out:Array<HTMLSelectedContentElement> = [];
		var n = firstChild;
		while (n != null) {
			if (n.nodeType == Node.ELEMENT_NODE && Std.isOfType(n, HTMLSelectedContentElement)) out.push(cast n);
			n = Node.following(n, this);
		}
		return out;
	}

	// queue an update of the descendant selectedcontent elements (the microtask: Document.checkpoint)
	function queueUpdate() {
		if (pending || selectedContents().length == 0) return;
		pending = true;
		doc.microtasks.push(this);
	}

	// update a select's descendant selectedcontent elements
	function updateSelectedContent() {
		pending = false;
		if (multiple()) return;
		var selected:Null<HTMLOptionElement> = null;
		for (o in options())
			if (o.selectedness) {
				selected = o;
				break;
			}
		for (c in selectedContents())
			if (!c.disabled) c.show(selected);
	}

	override function attributeChangeSteps(localName:String, old:Null<String>, value:Null<String>, namespace:Null<String>) {
		if (namespace != null) return;
		if (localName == "size") resetSelectedness(false);
		if (localName != "multiple" || old != null && value != null) return;
		if (value == null) {
			var first = true;
			for (o in options())
				if (o.selectedness) {
					if (!first) o.selectedness = false;
					first = false;
				}
		}
		resetSelectedness(true);
	}
}
