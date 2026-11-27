import helder.canvas.Canvas;
import helder.css.CssTheme;
import helder.css.CssUserAgentTheme;
import helder.dom.Document;
import helder.dom.Element;
import helder.ui.box.DocumentView;

// The CSS engine as an app has it (the css lane): a tree built in code
// (helder.dom), styled by sheets compiled at build time (app.css; the
// todo's look, tests/bench/document/todo-app.css), laid out and painted by
// DocumentView on the CPU: no CSS, HTML or XML parser in its symbols. With
// -D css.parse, HTML's cascade (DocumentView.html) has them: the check's control.
class EngineProbe {
	static function main() {
		var doc = new Document();
		inline function el(tag:String, cls:String, ?text:String):Element {
			var e = doc.createElement(tag);
			e.setAttribute("class", cls);
			if (text != null) e.append(doc.createTextNode(text));
			return e;
		}
		var root = el("view", "app");
		doc.append(root);
		var title = el("text", "title", "todos");
		root.append(title);
		var list = el("scroll", "list");
		var row = el("view", "row done");
		row.append(el("view", "check"), el("text", "label", "Task 1"));
		list.append(row);
		root.append(list);
		#if css.parse
		var view = DocumentView.html(doc, {userAgent: CssUserAgentTheme.app(), author: [CssTheme.file("../bench/document/todo-app.css")]});
		#else
		var view = helder.ui.box.DocumentApp.view(doc, [CssUserAgentTheme.app(), CssTheme.file("../bench/document/todo-app.css")]);
		#end
		var canvas = new Canvas(480, 560);
		view.layout(480, 560);
		view.paint(canvas);
		var s = view.styles;
		Sys.println([view.root >= 0 ? "laid out" : "empty", s.computed(title).text("font-size"), s.computed(title).text("color"), s.computed(row).text("display"),
			s.computed(row).text("flex-direction"), s.computed(list).text("overflow-y")].join(" "));
	}
}
