import helder.css.CssSheet;
import helder.css.CssUserAgentTheme;
import helder.dom.Dom;
import helder.ui.box.DocumentNode;
import helder.ui.UiWindow;
import helder.ui.UiWindow.Surface;
import helder.view.*;

// examples/todo's screen as DOM and CSS (DocumentBench's mirror: its markup
// and :hover rules, the arguments' files) in a window through the engine:
// what bench document builds beside examples/todo to weigh both.
class TodoDocument implements Markup {
	static function main() {
		var args = #if sys Sys.args() #else [] #end;
		var html = args.length > 0 ? sys.io.File.getContent(args[0]) : "<root/>";
		var css = args.length > 1 ? sys.io.File.getContent(args[1]) : "";
		var node = new DocumentNode(Dom.parseXml(html), {userAgent: CssUserAgentTheme.app(), author: [CssSheet.parse(css, Author)]});
		UiWindow.run(<Surface title="Todo" width={480} height={560}><view flexGrow={1}>{node}</view></Surface>);
	}
}
