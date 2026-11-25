package helder.ui;

import helder.ui.view.UiView;

typedef StackTransition = helder.ui.nav.Screens.StackTransition;

// A router's screens, a stack (helder.ui.nav.Screens.Stack): <Stack router={nav}/>,
// its transition the platform's unless given (Slide, Fade, None)
function Stack(props:{router:helder.ui.nav.Router, ?transition:StackTransition}):UiView
	return helder.ui.nav.Screens.Stack({router: props.router, transition: props.transition});
