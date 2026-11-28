package helder.ui.controls;

import haxe.DynamicAccess;
import helder.ui.Style.StyleProps;
import helder.ui.controls.Props;
import helder.ui.controls.Tokens;

// A part's style: a Style's properties, and under a state's name what
// changes while it holds (nested: checked: {hover: ...}). The states are
// the control's (hover, pressed, focus, disabled, checked, mixed,
// selected), placeholder and dark. A part's state follows its control's: a
// knob is "hover" while its switch is (Compile).
@:typescript.type("import('./style').PartStyle") @:typescript.dynamic
typedef PartStyle = StyleProps;

// a control's variants: by axis (variant, size, as the control's props
// name them), each value's parts
typedef VariantParts<P> = {?variant:DynamicAccess<P>, ?size:DynamicAccess<P>}

// the variant and size a control takes when its props give none
typedef Defaults = {?variant:String, ?size:String}

typedef ButtonParts = {?root:PartStyle, ?icon:PartStyle, ?label:PartStyle}
@:typescript.type("import('./style').ButtonRecipe") @:typescript.dynamic
typedef ButtonRecipe = {> ButtonParts, ?variants:VariantParts<ButtonParts>, ?defaults:Defaults}
typedef CheckboxParts = {?root:PartStyle, ?box:PartStyle, ?mark:PartStyle, ?label:PartStyle}
@:typescript.type("import('./style').CheckboxRecipe") @:typescript.dynamic
typedef CheckboxRecipe = {> CheckboxParts, ?variants:VariantParts<CheckboxParts>, ?defaults:Defaults}
typedef SwitchParts = {?root:PartStyle, ?track:PartStyle, ?knob:PartStyle, ?label:PartStyle}
@:typescript.type("import('./style').SwitchRecipe") @:typescript.dynamic
typedef SwitchRecipe = {> SwitchParts, ?variants:VariantParts<SwitchParts>, ?defaults:Defaults}
typedef PathBarParts = {
	?root:PartStyle,
	?segment:PartStyle,
	?segmentIcon:PartStyle,
	?separator:PartStyle,
	?overflow:PartStyle,
	?current:PartStyle,
	?field:PartStyle
}
@:typescript.type("import('./style').PathBarRecipe") @:typescript.dynamic
typedef PathBarRecipe = {> PathBarParts, ?variants:VariantParts<PathBarParts>}

// what Look.with takes (Haxe's: Look.with's macro checks a patch against
// it; "switch" written as such, as a key: the macro's switch_): a density,
// an accent, tokens, a recipe per control (its result merged over the
// look's by part and state, property by property), a control's rendering
// replaced (behaviour and accessibility kept: Toggle, Press), an app's
// own parts (Look.part: a name each, its states its own)
@:typescript.type("import('./style').LookPatch") @:typescript.dynamic
typedef Patch = {
	?density:Tokens.Density,
	?accent:Tokens.Accent,
	?tokens:Tokens,
	?button:Refs->ButtonRecipe,
	?checkbox:Refs->CheckboxRecipe,
	?switch_:Refs->SwitchRecipe,
	?pathbar:Refs->PathBarRecipe,
	?render:Renders,
	?parts:DynamicAccess<Refs->PartStyle>
}

typedef Renders = {
	?button:ButtonProps<Dynamic>->helder.view.View,
	?checkbox:CheckboxProps<Dynamic>->helder.view.View,
	?switch_:SwitchProps<Dynamic>->helder.view.View
}

// (TypeScript's patch, typed: LookMacro.tsPatch)
@:noCompletion @:genericBuild(helder.ui.controls.LookOf.LookMacro.tsPatch())
class TsPatch {}
