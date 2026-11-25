package helder.ui;

typedef SheetProps = helder.ui.nav.Sheets.SheetProps;
typedef Detent = helder.ui.nav.Sheets.Detent;

// A bottom sheet with detents, or a popover from its anchor on a wider
// screen (helder.ui.nav.Sheets.Sheet)
function Sheet(props:SheetProps):Any
	return helder.ui.nav.Sheets.Sheet(props);
