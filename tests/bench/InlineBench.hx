import helder.dom.Dom;
import helder.dom.Element;
import helder.text.TextLayout;
import helder.ui.flow.InlineBasicStyle;
import helder.ui.flow.InlineConstraints;
import helder.ui.flow.InlineContent;
import helder.ui.flow.InlineFonts;
import helder.ui.flow.InlineLayout;
import helder.ui.flow.InlineShaper;
import sys.io.File;

// helder.ui.flow's inline layout on the text of every <p> of a page (bench
// inline: the HTML Standard), natively, in Inter at 16px: each paragraph's
// content built (white space, bidi, opportunities, shaping) and laid out at
// 700px, with the shaped-word cache empty (cold) and full (warm), then laid
// out again at 500px (no shaping); against TextLayout on the same texts
// (made at 700px, wrapped again at 500px). The least of runs, as ms per MB
// of text (UTF-16 units).
//
//   bin/bench/InlineBench <page.html> <runs>
class InlineBench {
	static function main() {
		var args = Sys.args();
		var runs = Std.parseInt(args[1]) ?? 5;
		helder.text.SystemFonts.get().add(File.getBytes("src/helder/text/fonts/Inter.ttf"));
		var doc = Dom.parse(File.getContent(args[0]));
		var texts = [for (p in paragraphs(doc.documentElement)) p.textContent];
		texts = [for (t in texts) if (StringTools.trim(t) != "") t];
		var units = 0;
		for (t in texts)
			units += t.length;
		var style = new InlineBasicStyle();
		style.families = ["Inter"];
		var fonts = InlineFonts.shared.set(InlineFonts.shared.idOf(style));
		var wide = new InlineConstraints(700), narrow = new InlineConstraints(500);
		var best = {cold: 1e9, warm: 1e9, relayout: 1e9, textLayout: 1e9, textWrap: 1e9};
		var lines = 0, textLines = 0;
		var contents:Array<InlineContent> = [], layouts = [for (_ in texts) new InlineLayout()];
		for (_ in 0...runs) {
			InlineShaper.shared.clear();
			for (pass in 0...2) {
				var t0 = haxe.Timer.stamp();
				contents.resize(0);
				lines = 0;
				for (i in 0...texts.length) {
					var c = new InlineContent(style);
					c.addText(texts[i], style);
					c.finish();
					contents.push(c);
					lines += layouts[i].layout(c, wide).lines;
				}
				var t = haxe.Timer.stamp() - t0;
				if (pass == 0) best.cold = Math.min(best.cold, t) else best.warm = Math.min(best.warm, t);
			}
			var t1 = haxe.Timer.stamp();
			for (i in 0...texts.length)
				layouts[i].layout(contents[i], narrow);
			best.relayout = Math.min(best.relayout, haxe.Timer.stamp() - t1);
			var t2 = haxe.Timer.stamp();
			var made = [for (t in texts) new TextLayout(t, fonts, 1.2, 700)];
			var t3 = haxe.Timer.stamp();
			textLines = 0;
			for (l in made) {
				l.wrap(500);
				textLines += l.lines.length;
			}
			var t4 = haxe.Timer.stamp();
			best.textLayout = Math.min(best.textLayout, t3 - t2);
			best.textWrap = Math.min(best.textWrap, t4 - t3);
		}
		var mb = units / 1e6;
		inline function perMb(s:Float)
			return Math.round(s * 1e3 / mb * 10) / 10;
		Sys.println(haxe.Json.stringify({
			paragraphs: texts.length,
			mb: Math.round(mb * 1000) / 1000,
			lines700: lines,
			inlineCold: perMb(best.cold),
			inlineWarm: perMb(best.warm),
			inlineRelayout500: perMb(best.relayout),
			textLayout700: perMb(best.textLayout),
			textLayoutWrap500: perMb(best.textWrap),
			textLayoutLines500: textLines
		}));
	}

	static function paragraphs(root:Element):Array<Element> {
		var out = [], stack = [root];
		while (stack.length > 0) {
			var e = stack.pop();
			if (e.localName == "p") out.push(e);
			var c = e.lastElementChild;
			while (c != null) {
				stack.push(c);
				c = c.previousElementSibling;
			}
		}
		return out;
	}
}
