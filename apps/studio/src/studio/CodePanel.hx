package studio;

import helder.ui.*;
import helder.ui.code.CodeLanguage.CodeLanguages;
import helder.ui.code.CodeModel;
import helder.ui.code.CodeView;
import helder.view.*;
import helder.view.Flow.*;
import helder.view.graph.Graph.*;
import helder.view.graph.Read;
import studio.Theme.c;

// A file the chat's chip named, read only, over the canvas' left part, at
// its line (Conversation.reading); Escape or its close button puts it away
class CodePanel implements Markup {
	public static function view(studio:Studio):View
		return <For each={studio.talk.reading() == null ? [] : [studio.talk.reading()]}>{(r:Read<{file:String, line:Null<Int>}>) ->
			<view tag="code-panel" position="absolute" left={0} top={0} bottom={0} width="55%" min-width={320} background={c("card")} border-width="0 1 0 0"
				border-color={c("hair2")} onClick={e -> e.stop()} onPointerDown={e -> e.stop()}>
				<view direction="row" align-items="center" column-gap={8} height={36} padding="0 8 0 14" shrink={0} border-width="0 0 1 0" border-color={c("hair")}>
					<text tag="code-panel-file" grow={1} min-width={0} max-lines={1} text-overflow="ellipsis" font-family={Theme.CODE} font-size={Theme.SMALL}
						color={c("ink2")}>{label(studio, r())}</text>
					<view:button tag="code-panel-close" slot="button" role="button" label="Close" onPress={() -> studio.talk.reading(null)}>
						<image src={Icons.close} width={Theme.ICON_S} height={Theme.ICON_S}/>
					</view:button>
				</view>
				{code(studio, r())}
			</view>
		}</For>;

	static function label(studio:Studio, r:{file:String, line:Null<Int>}):String
		return Shell.fileLabel(studio, r.file) + (r.line == null ? "" : ':${r.line}');

	// (the file as the studio has it, unsaved edits too, its line shown)
	static function code(studio:Studio, r:{file:String, line:Null<Int>}):Node {
		var text = studio.docs.get(r.file).text;
		var m = new CodeModel(text);
		m.readOnly = true;
		m.language = CodeLanguages.forPath(r.file);
		var v = new CodeView(m);
		v.currentLine = false;
		v.fontFamily = Theme.CODE;
		v.fontSize = Theme.CODE_SIZE;
		v.lineHeight = Theme.CODE_LINE;
		v.style.grow = 1;
		v.style.minHeight = 0;
		if (r.line != null) {
			var at = 0;
			for (_ in 1...r.line) {
				var n = text.indexOf("\n", at);
				if (n < 0) break;
				at = n + 1;
			}
			v.revealRange(at, at);
		}
		return v;
	}
}
