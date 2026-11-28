package helder.ui;

import helder.ui.view.UiView;

typedef NavScreenProps = helder.ui.nav.Bar.NavScreenProps;

// A Stack's screen with its bars (helder.ui.nav.Bar.NavScreen): a title,
// large or not, the back button, bar items, a header, a bottom bar
function NavScreen(props:NavScreenProps):UiView
	return helder.ui.nav.Bar.NavScreen(props);

// a bar's item, 44 points at least (helder.ui.nav.Bar.NavButton)
function NavButton(props:{label:String, ?icon:Svg, ?tag:String, ?disabled:helder.view.graph.Read<Bool>, onPress:Void->Void}):UiView
	return helder.ui.nav.Bar.NavButton(props);
