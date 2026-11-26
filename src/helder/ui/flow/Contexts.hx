package helder.ui.flow;

import helder.ui.box.BoxStyle;

// The formatting contexts a program lays out with, by inner display. One
// it has not (flex, grid and table are not in this slice yet) lays out as
// flow, noted as pending.
class Contexts {
	public final flow:FormattingContext;
	public var flex:Null<FormattingContext> = null;
	public var grid:Null<FormattingContext> = null;
	public var table:Null<FormattingContext> = null;

	public function new(flow:FormattingContext)
		this.flow = flow;

	public static function all():Contexts
		return new Contexts(new BlockFlow());

	public function of(inner:Int, note:String->Void):FormattingContext {
		var c = switch inner {
			case BoxStyle.FLEX: flex;
			case BoxStyle.GRID: grid;
			case BoxStyle.TABLE | BoxStyle.TABLE_PART: table;
			case _: return flow;
		}
		if (c != null) return c;
		note(switch inner {
			case BoxStyle.FLEX: "flex: not in the slice yet, laid out as flow";
			case BoxStyle.GRID: "grid: not in the slice yet, laid out as flow";
			case _: "tables: not in the slice yet, laid out as flow";
		});
		return flow;
	}
}
