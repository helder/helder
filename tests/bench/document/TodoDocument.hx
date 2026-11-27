import helder.css.CssTheme;
import helder.css.CssUserAgentTheme;
import helder.dom.Document;
import helder.dom.Element;
import helder.ui.box.DocumentApp;
import helder.ui.UiWindow;
import helder.ui.UiWindow.Surface;
import helder.view.*;

// examples/todo's screen on the CSS engine as an app would have it, in a
// window: its tree built in code (helder.dom, no parser), styled by sheets
// compiled at build time (app.css, the user agent's; todo-app.css, its
// look), so that no CSS, HTML or XML parser is linked, laid out by the
// formatting contexts those sheets can make (DocumentApp). What the engine
// costs an app beside examples/todo (the size lane's engine).
class TodoDocument implements Markup {
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
		root.append(el("text", "title", "todos"));
		var bar = el("view", "bar");
		bar.append(el("field", "input"), el("view", "button", "Add"));
		root.append(bar);
		var list = el("scroll", "list");
		for (i in 0...20) {
			var row = el("view", i % 3 == 0 ? "row done" : "row");
			row.append(el("view", "check"), el("text", "label", 'Task ${i + 1}: water the plants and call back'), el("view", "delete", "Remove"));
			list.append(row);
		}
		root.append(list);
		root.append(el("text", "footer", "20 items left"));
		var node = DocumentApp.node(doc, [CssUserAgentTheme.app(), CssTheme.file("todo-app.css")]);
		UiWindow.run(<Surface title="Todo" width={480} height={560}><view flexGrow={1}>{node}</view></Surface>);
	}
}
