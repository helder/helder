package helder.ui;

// The text engine a Ui is made with when its host names none: the CSS
// engine's (EngineText), or helder.text's own lines (DrawText) under
// -D helder.drawtext, until they go.
class TextEngines {
	public static function standard():TextEngine
		return #if helder.drawtext new helder.ui.draw.DrawText() #else new EngineText() #end;
}
