package helder.css;

// Named strings' and running elements' values on a page (GCPM 3 §1.2,
// §2.2), for the paged host: the assignments in document order, page by
// page; a margin box asks for a name's value as string() or element()
// says. first: the page's first assignment, else the entry value (the
// last one before the page); start: the first assignment when its
// element starts the page, else the entry value; last: the page's last,
// else the entry value; first-except: none on a page with an assignment,
// else the entry value.
//
//   var strings = new CssRunning<String>();
//   strings.page();                                // page 1
//   strings.assign("title", "Chapter 1", true);   // at the page's start
//   strings.value("title", "first");              // "Chapter 1"
class CssRunning<T> {
	final entry = new Map<String, T>();
	final assigned = new Map<String, Array<T>>();
	final starts = new Map<String, Bool>();

	public function new() {}

	// The next page: what was assigned so far is its entry value.
	public function page() {
		for (name => list in assigned) if (list.length > 0) entry.set(name, list[list.length - 1]);
		assigned.clear();
		starts.clear();
	}

	// An assignment on the current page, in document order; atStart: its
	// element is the first thing on the page.
	public function assign(name:String, value:T, atStart = false) {
		var list = assigned.get(name);
		if (list == null) {
			assigned.set(name, list = []);
			starts.set(name, atStart);
		}
		list.push(value);
	}

	// The name's value on the current page; null when there is none (an
	// empty string's or no element's place).
	public function value(name:String, which = "first"):Null<T> {
		var list = assigned.get(name);
		var here = list != null && list.length > 0;
		return switch which {
			case "first": here ? list[0] : entry.get(name);
			case "start": here && starts.get(name) ? list[0] : entry.get(name);
			case "last": here ? list[list.length - 1] : entry.get(name);
			case "first-except": here ? null : entry.get(name);
			case _: null;
		}
	}
}
