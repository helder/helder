package viewer;

import helder.ui.Clock;
import helder.ui.Key;
import helder.ui.Node;
import helder.ui.controls.Look;
import helder.view.*;

// A name edited in place (a tile's, a row's, a sidebar folder's), as
// Finder's: the name selected but its extension, Enter or leaving the field
// commits, Escape gives it up.
class NameField implements Markup {
	public static function field(name:String, commit:String->Void, cancel:Void->Void, center = false):View {
		var text = name, done = false;
		function finish(ok:Bool) {
			if (done) return;
			done = true;
			if (ok) commit(text) else cancel();
		}
		return <field tag="rename" value={name} label="Name" grow={1} min-width={0} padding="0 4" radius={4} background={Look.ref.canvas}
			border-width={1} border-color={Look.ref.accent} color={Look.ref.fg} text-align={center ? "center" : "left"}
			onInput={e -> text = e.text}
			onKeyDown={e -> if (e.key == Key.ENTER || e.key == Key.ESCAPE) {
				finish(e.key == Key.ENTER);
				e.preventDefault();
				e.stop();
			}}
			onBlur={_ -> finish(true)}
			ref={(n:Node) -> Clock.add(_ -> {
				n.focus();
				var dot = name.lastIndexOf(".");
				n.select(0, dot > 0 ? dot : name.length);
				false;
			})}/>;
	}
}
