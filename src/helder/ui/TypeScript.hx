package helder.ui;

// helder.ui for TypeScript programs (helder.typescript): windows and their
// markup (see helder/view), the events handlers are given, the keys. Each
// class is the Haxe class `__haxe` names. The neutral elements (view, text,
// view:button...) take any attribute, their handlers given ui's events.
// Its widgets, controls and code editor are whole packages: a class added
// to them is the program's too.
@:typescript("helder/ui")
@:typescript.classes(helder.ui.draw.UiWindow, helder.ui.Event, helder.ui.Key, helder.ui.VirtualScroll, helder.ui.Selection, helder.ui.GridScroll, helder.ui.Clock, helder.ui.platform.WebViewEvent, helder.ui.platform.WebContent, helder.ui.platform.WebResponse)
@:typescript.classes(helder.ui.Node, helder.ui.TextNode, helder.ui.view.UiFlow, helder.ui.SafeArea, helder.ui.nav.Router)
@:typescript.packages(helder.ui.widgets, helder.ui.controls, helder.ui.code)
// (an icon or a drawing: made by Icons.parse and Icons.svg, given to <image src>)
@:typescript.types(helder.canvas.Svg, helder.ui.view.UiFlow.VirtualListProps, helder.ui.nav.Router.RouteParams, helder.ui.nav.Screens.StackTransition,
	helder.ui.SizeClass, helder.ui.nav.Sheets.Detent, helder.ui.nav.Bar.NavScreenProps, helder.ui.nav.Sheets.SheetProps)
@:typescript.functions(tone = helder.ui.controls.Look.tone, Surface = helder.ui.draw.UiWindow.Surface, VirtualList = helder.ui.view.UiFlow.VirtualList, VirtualGrid = helder.ui.view.UiFlow.VirtualGrid, Stack = helder.ui.nav.Screens.Stack,
	NavScreen = helder.ui.nav.Bar.NavScreen, NavButton = helder.ui.nav.Bar.NavButton, Sheet = helder.ui.nav.Sheets.Sheet)
@:typescript.jsx(neutral)
@:build(helder.typescript.api.Manifest.build())
class TypeScript {}
