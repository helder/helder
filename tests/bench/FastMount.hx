import helder.ui.fast.FastTags.*;
import helder.view.*;

// (the bench's todo on fast nodes: TodoFast's markup in a <Fast> under parent)
class FastMount implements Markup {
	public static function todo(app:TodoFast, parent:helder.ui.Node):helder.ui.fast.Tree {
		var tree:Null<helder.ui.fast.Tree> = null;
		Render.render(<Fast ref={t -> tree = t}>{app.view()}</Fast>, parent);
		return tree;
	}

	public static function mail(app:MailFast, parent:helder.ui.Node):helder.ui.fast.Tree {
		var tree:Null<helder.ui.fast.Tree> = null;
		Render.render(<Fast theme={MailFast.theme} actions={[]} ref={t -> tree = t}>{app.view()}</Fast>, parent);
		return tree;
	}
}
