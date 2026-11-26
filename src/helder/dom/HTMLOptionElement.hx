package helder.dom;

// HTML's option element, for its selectedness: a select's selectedcontent
// shows the selected option's children (HTML 4.10.10).
@:allow(helder.dom)
class HTMLOptionElement extends Element {
	var selectedness = false;
	var dirtiness = false;
	var cachedSelect:Null<HTMLSelectElement> = null;

	function new(doc:Document, prefix:Null<String>) {
		super(doc, "option", Namespaces.HTML, prefix);
		doc.selects++;
	}

	// (when created: selected if it has a selected attribute)
	override function attributesSet()
		if (byNamespace(null, "selected") != null) selectedness = true;

	// disabled: its own attribute, or its optgroup's
	function disabled():Bool {
		if (byNamespace(null, "disabled") != null) return true;
		var a = parentElement;
		while (a != null) {
			if (a.ns == Element.HTML) switch a.tag {
				case Tags.SELECT | Tags.HR | Tags.OPTION: return false;
				case Tags.OPTGROUP: return a.byNamespace(null, "disabled") != null;
				case _: if (a.localName == "datalist") return false;
			}
			a = a.parentElement;
		}
		return false;
	}

	// the nearest ancestor select
	function nearestSelect():Null<HTMLSelectElement> {
		var optgroup = false;
		var a = parentElement;
		while (a != null) {
			if (a.ns == Element.HTML) switch a.tag {
				case Tags.HR | Tags.OPTION: return null;
				case Tags.OPTGROUP:
					if (optgroup) return null;
					optgroup = true;
				case Tags.SELECT: return cast a;
				case _: if (a.localName == "datalist") return null;
			}
			a = a.parentElement;
		}
		return null;
	}

	// update an option's nearest ancestor select: the selects to update
	function updateSelect():Array<HTMLSelectElement> {
		var old = cachedSelect, now = nearestSelect();
		cachedSelect = now;
		if (old == now) return [];
		var out = [];
		for (s in [old, now])
			if (s != null && (s.selectednessSetting() || selectedness)) out.push(s);
		return out;
	}

	override function insertionSteps() {
		var selects = updateSelect();
		if (!get_isConnected()) return;
		for (s in selects)
			s.queueUpdate();
	}

	override function postConnection() {
		var s = cachedSelect;
		if (s != null && s.pending) s.updateSelectedContent();
	}

	override function removingSteps()
		for (s in updateSelect())
			s.queueUpdate();

	override function movingSteps()
		removingSteps();

	override function attributeChangeSteps(localName:String, old:Null<String>, value:Null<String>, namespace:Null<String>) {
		if (namespace != null || localName != "selected" && localName != "disabled") return;
		if (old != null && value != null) return;
		var changed = false;
		if (localName == "selected" && !dirtiness) {
			if (old == null && !selectedness) {
				selectedness = true;
				changed = true;
			}
			if (value == null && selectedness) {
				selectedness = false;
				changed = true;
			}
		}
		if (cachedSelect != null) cachedSelect.resetSelectedness(changed);
	}

	override function childrenParsed() {
		var s = cachedSelect;
		if (s != null && selectedness) s.updateSelectedContent();
	}
}
