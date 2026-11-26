package helder.ui;

// helder.ui for TypeScript programs (helder.typescript): windows and their
// markup (see helder/view), the events handlers are given, the keys. Each
// class is the Haxe class `__haxe` names. The neutral elements (view, text,
// button...) take any attribute, their handlers given ui's events.
@:typescript("helder/ui")
@:typescript.classes(helder.ui.UiWindow, helder.ui.Event, helder.ui.Key, helder.ui.VirtualScroll, helder.ui.Selection, helder.ui.GridScroll, helder.ui.Clock, helder.ui.platform.WebViewEvent, helder.ui.platform.WebContent, helder.ui.platform.WebResponse)
@:typescript.classes(helder.ui.Edges, helder.ui.Node, helder.ui.TextNode, helder.ui.view.UiFlow, helder.ui.SafeArea, helder.ui.nav.Router)
@:typescript.classes(helder.ui.widgets.Controls, helder.ui.widgets.DataGrid,
	helder.ui.widgets.EditableText, helder.ui.widgets.GridColumn,
	helder.ui.widgets.GridTheme, helder.ui.widgets.Icons, helder.ui.widgets.Pager,
	helder.ui.widgets.TextArea, helder.ui.widgets.TextField, helder.ui.widgets.Theme,
	helder.ui.widgets.WindowButtons)
@:typescript.classes(helder.ui.controls.Eased, helder.ui.controls.Look,
	helder.ui.controls.Press, helder.ui.controls.Standard, helder.ui.controls.Toggle)
@:typescript.classes(helder.ui.code.CodeAction.CodeActions, helder.ui.code.CodeCompletion,
	helder.ui.code.CodeEditor, helder.ui.code.CodeLanguage,
	helder.ui.code.CodeLanguage.SyntaxLanguage,
	helder.ui.code.CodeLanguage.CodeLanguages, helder.ui.code.CodeModel.Sel,
	helder.ui.code.CodeModel.Decoration, helder.ui.code.CodeModel.CodeDiagnostic,
	helder.ui.code.CodeModel, helder.ui.code.CodeTheme, helder.ui.code.CodeView,
	helder.ui.code.Rope, helder.ui.code.SqlLanguage)
@:typescript.internal(UiFlow, Controls, Pager, WindowButtons, Standard, GridTheme,
	Eased, Press, Sel, Decoration, CodeModel, Rope)
// (an icon or a drawing: made by Icons.parse and Icons.svg, given to <image src>)
@:typescript.types(helder.gfx.Color, helder.ui.EventType, helder.ui.TextAlign, helder.ui.ImageFit, helder.ui.PointerEvents, helder.ui.actions.ActionState, helder.ui.Placement, helder.ui.menu.Menu.MenuItem, helder.canvas.Svg, helder.ui.view.UiFlow.VirtualListProps, helder.ui.nav.Router.RouteParams, helder.ui.nav.Screens.StackTransition,
	helder.ui.SizeClass, helder.ui.nav.Sheets.Detent, helder.ui.nav.Bar.NavScreenProps, helder.ui.nav.Sheets.SheetProps)
@:typescript.functions(tone = helder.ui.controls.Look.tone, Surface = helder.ui.UiWindow.Surface, VirtualList = helder.ui.view.UiFlow.VirtualList, VirtualGrid = helder.ui.view.UiFlow.VirtualGrid, Stack = helder.ui.nav.Screens.Stack,
	NavScreen = helder.ui.nav.Bar.NavScreen, NavButton = helder.ui.nav.Bar.NavButton, Sheet = helder.ui.nav.Sheets.Sheet)
@:typescript.functions(pager = helder.ui.widgets.Pager.create,
	windowControlsSide = helder.ui.widgets.WindowButtons.side)
@:typescript.jsx(neutral)
@:build(helder.typescript.api.Manifest.build())
class TypeScript {}
