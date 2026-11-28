package helder.ui;

// The text engine a Ui is made with when its host names none: helder.text's
// own lines (DrawText), or the CSS engine's under -D helder.enginetext (the
// switch's step 3, EngineText), until that is the default.
class TextEngines {
	public static function standard():TextEngine
		return #if helder.enginetext new EngineText() #else new helder.ui.draw.DrawText() #end;
}
