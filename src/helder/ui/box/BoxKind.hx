package helder.ui.box;

// What a box is, by its display (Display 3) and what it holds.
enum abstract BoxKind(Int) {
	// a block-level block container (block, list-item, flow-root; anonymous blocks)
	var Block;
	// an inline box (display: inline, its contents in its parent's lines)
	var Inline;
	// an inline-level block container (inline-block): atomic in its line
	var InlineBlock;
	// a flex, grid or table container, or a table's part (block- or inline-level by its display)
	var Container;
	var Text;
	// a replaced element (img): its image at its intrinsic or specified size
	var InlineReplaced;
	var BlockReplaced;
	// <br>: a forced line break
	var Break;
	// a table's wrapper box (CSS 2.1 §17.4): its captions and the table box; block- or
	// inline-level by the table's display, its margins the table's
	var TableWrapper;

	public function toString():String
		return switch (cast this : BoxKind) {
			case Block: "Block";
			case Inline: "Inline";
			case InlineBlock: "InlineBlock";
			case Container: "Container";
			case Text: "Text";
			case InlineReplaced: "InlineReplaced";
			case BlockReplaced: "BlockReplaced";
			case Break: "Break";
			case TableWrapper: "TableWrapper";
		}
}
