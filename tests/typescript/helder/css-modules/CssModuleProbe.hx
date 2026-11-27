import helder.css.CssCascade;
import helder.css.CssModule;
import helder.dom.Dom;

class CssModuleProbe {
	@:typescript public static function measure(html:String):String {
		var doc = Dom.parse(html);
		var div = doc.getElementsByTagName("div").item(0);
		var style = CssCascade.themed(doc, []).computed(div);
		return [style.text("width"), style.text("font-weight"), Std.string(CssModule.sheets().length)].join(" ");
	}
}
