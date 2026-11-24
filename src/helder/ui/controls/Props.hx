package helder.ui.controls;

import helder.ui.Svg;
import helder.ui.controls.Variant;
import helder.view.graph.Read;
import helder.view.graph.Signal;

// The controls' props, V the look whose variants and sizes they take
// (Look<V>: Look.base's for Standard's, a look's own for look.Button).
// children: what a button shows (text, or views); label: its name for
// assistive technology (an icon alone's), a checkbox's and a switch's
// text beside it. checked with onChange: the caller's state; neither: the
// control's own.
typedef ButtonProps<V> = {
	?children:Any,
	?label:String,
	?icon:Svg,
	?variant:ButtonVariant<V>,
	?size:ButtonSize<V>,
	?disabled:Read<Bool>,
	?selected:Read<Bool>,
	?onPress:Void->Void,
	?tag:String
}

typedef CheckboxProps<V> = {
	label:String,
	?checked:Read<Bool>,
	?indeterminate:Read<Bool>,
	?onChange:Bool->Void,
	?disabled:Read<Bool>,
	?variant:CheckboxVariant<V>,
	?size:CheckboxSize<V>,
	?tag:String
}

typedef SwitchProps<V> = {
	label:String,
	?checked:Read<Bool>,
	?onChange:Bool->Void,
	?disabled:Read<Bool>,
	?variant:SwitchVariant<V>,
	?size:SwitchSize<V>,
	?tag:String
}

typedef PathSegment = {label:String, ?icon:Svg}

typedef PathBarProps = {
	segments:Read<Array<PathSegment>>,
	onNavigate:Int->Void,
	onSubmit:String->Void,
	?onSeparator:(index:Int, anchor:helder.ui.Node)->Void,
	?editable:Bool,
	?text:Read<String>,
	?editing:Signal<Bool>,
	?size:PathBarSize,
	?tag:String,
	?label:String
}
