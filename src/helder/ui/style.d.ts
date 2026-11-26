// StyleProps for TypeScript programs: each property as markup's attribute
// writes it (`'row'`, `'0 12'`, `'#3b82f6'`, `'scale(0.97)'`) or as a
// number, parsed once where helder takes the style (helder.ui.Styles). Its
// names are helder.ui.StyleProps' (the typescript lane checks they match).
// Then the looks' recipes (helder.ui.controls.Recipe), their patches, and
// the variants a patch adds to its look (Look.with's types).
import type {View} from 'helder/view';
import type {Color, Refs, Tokens, ButtonProps, CheckboxProps, SwitchProps} from './index';

// a length: points, or a string as CSS writes one ('50%', 'auto', '12px')
export type Length = number | string;

export type StyleProps = {
	display?: 'flex' | 'none' | 'grid' | 'block';
	position?: 'relative' | 'absolute' | 'sticky';
	flexDirection?: 'column' | 'row' | 'column-reverse' | 'row-reverse';
	flexWrap?: boolean | 'wrap' | 'nowrap';
	justifyContent?: 'start' | 'end' | 'center' | 'space-between' | 'space-around' | 'space-evenly' | 'normal';
	alignItems?: 'auto' | 'start' | 'end' | 'center' | 'stretch' | 'baseline';
	alignSelf?: 'auto' | 'start' | 'end' | 'center' | 'stretch' | 'baseline';
	alignContent?: 'start' | 'end' | 'center' | 'stretch' | 'space-between' | 'space-around' | 'space-evenly' | 'normal';
	flexGrow?: number;
	flexShrink?: number;
	flexBasis?: Length;
	width?: Length;
	height?: Length;
	minWidth?: Length;
	minHeight?: Length;
	maxWidth?: Length;
	maxHeight?: Length;
	aspectRatio?: number;
	padding?: number | string | number[];
	margin?: number | string | number[];
	paddingTop?: number;
	paddingRight?: number;
	paddingBottom?: number;
	paddingLeft?: number;
	marginTop?: number;
	marginRight?: number;
	marginBottom?: number;
	marginLeft?: number;
	borderWidth?: number | string | number[];
	borders?: number | string | number[];
	rowGap?: number;
	columnGap?: number;
	left?: Length;
	top?: Length;
	right?: Length;
	bottom?: Length;
	overflow?: 'visible' | 'hidden' | 'scroll';
	overflowX?: 'visible' | 'hidden' | 'scroll';
	overflowY?: 'visible' | 'hidden' | 'scroll';
	background?: Color;
	letterSpacing?: number;
	letterSpacingEm?: number;
	wordSpacing?: number;
	textDecoration?: 'none' | 'underline' | 'overline' | 'line-through' | (string & {});
	textShadow?: string;
	textDecorationColor?: Color;
	textDecorationThickness?: Length;
	textUnderlineOffset?: Length;
	backgroundImage?: string;
	transform?: string;
	transformOrigin?: string | Length[];
	borderColor?: Color;
	borderRadius?: number | string | number[];
	corners?: number | string | number[];
	opacity?: number;
	cursor?: 'auto' | 'default' | 'pointer' | 'text' | 'crosshair' | 'move' | 'not-allowed' | 'ew-resize' | 'ns-resize' | 'grab' | 'grabbing';
	boxShadow?: string;
	transition?: string;
	outlineStyle?: 'auto' | 'solid' | 'none' | 'dashed' | 'dotted';
	borderStyle?: 'solid' | 'dashed' | 'dotted';
	userSelect?: 'auto' | 'none' | 'text' | 'all';
	fieldSizing?: 'fixed' | 'content';
	scrollbarWidth?: 'auto' | 'thin' | 'none';
	breakBefore?: 'auto' | 'avoid' | 'avoid-page' | 'page' | 'left' | 'right' | 'avoid-column' | 'column';
	breakAfter?: 'auto' | 'avoid' | 'avoid-page' | 'page' | 'left' | 'right' | 'avoid-column' | 'column';
	breakInside?: 'auto' | 'avoid' | 'avoid-page' | 'page' | 'left' | 'right' | 'avoid-column' | 'column';
	page?: string;
	scrollbarColor?: Color;
	scrollbarTrackColor?: Color;
	ringWidth?: number;
	ringColor?: Color;
	ringOffsetWidth?: number;
	ringOffsetColor?: Color;
	ringInset?: boolean;
	outlineWidth?: number;
	outlineOffset?: number;
	outlineColor?: Color;
	color?: Color;
	fontFamily?: string;
	fontSize?: number;
	fontWeight?: number;
	fontStyle?: 'normal' | 'italic';
	lineHeight?: number | string;
	lineHeightPx?: number;
	textAlign?: 'left' | 'center' | 'right' | 'justify';
	direction?: 'ltr' | 'rtl';
	visibility?: 'visible' | 'hidden';
	pointerEvents?: 'auto' | 'none';
	textWrap?: 'wrap' | 'no-wrap' | 'balance';
	gap?: number;
	inset?: Length;
	flex?: number;
	overflowWrap?: 'normal' | 'break-word' | 'anywhere';
	wordBreak?: 'normal' | 'break-all' | 'keep-all';
	fontFeatureSettings?: string;
	fontVariantNumeric?: string;
	textTransform?: 'none' | 'uppercase' | 'lowercase' | 'capitalize';
	textOverflow?: 'clip' | 'ellipsis' | 'middle';
	order?: number;
	zIndex?: number;
	lineClamp?: number;
	gridTemplateColumns?: string;
	gridTemplateRows?: string;
	gridAutoColumns?: string;
	gridAutoRows?: string;
	gridAutoFlow?: 'row' | 'column' | 'row-dense' | 'column-dense';
	gridColumn?: string | number;
	gridRow?: string | number;
	gridArea?: string;
	gridTemplateAreas?: string;
	justifyItems?: 'auto' | 'start' | 'end' | 'center' | 'stretch' | 'baseline';
	justifySelf?: 'auto' | 'start' | 'end' | 'center' | 'stretch' | 'baseline';
};

// a control's states, and dark, under which a part's style changes
export type State = 'hover' | 'pressed' | 'focus' | 'focusWithin' | 'disabled' | 'checked' | 'mixed' | 'selected' | 'open' | 'invalid' | 'readonly' | 'dark';

export type PartStyle = StyleProps & {[S in State]?: PartStyle};

export type Parts<P extends string> = {[K in P]?: PartStyle};

// a control's parts' styles, each variant's and size's, its defaults
export type Recipe<P extends string> = Parts<P> & {
	variants?: {variant?: Record<string, Parts<P>>; size?: Record<string, Parts<P>>};
	defaults?: {variant?: string; size?: string};
};

export type ButtonRecipe = Recipe<'root' | 'icon' | 'label'>;
export type CheckboxRecipe = Recipe<'root' | 'box' | 'mark' | 'label'>;
export type SwitchRecipe = Recipe<'root' | 'track' | 'knob' | 'label'>;
export type PathBarRecipe = Recipe<'root' | 'segment' | 'segmentIcon' | 'separator' | 'overflow' | 'current' | 'field'>;

export type Accent = 'blue' | 'violet' | 'teal' | 'green' | 'amber' | 'orange' | 'red' | 'pink' | 'graphite';

// what Look.with takes: a density, an accent, tokens, a recipe per control
// (merged over the look's by part and state), a control's rendering
// replaced (behaviour and accessibility kept: Toggle, Press), an app's own parts
export type LookPatch = {
	density?: 'comfortable' | 'compact';
	accent?: Accent;
	tokens?: Tokens;
	button?: (t: Refs) => ButtonRecipe;
	checkbox?: (t: Refs) => CheckboxRecipe;
	switch?: (t: Refs) => SwitchRecipe;
	pathbar?: (t: Refs) => PathBarRecipe;
	render?: {button?: (props: ButtonProps<any>) => View; checkbox?: (props: CheckboxProps<any>) => View; switch?: (props: SwitchProps<any>) => View};
	parts?: Record<string, (t: Refs) => PartStyle>;
};

type Names<R> = R extends Record<string, unknown> ? {[K in keyof R]: true} : {};
type Added<P, C extends string, A extends 'variant' | 'size'> = P extends {[k in C]: (t: any) => {variants?: {[a in A]?: infer R}}} ? Names<R> : {};

// the variants a patch adds, by control and axis (a look's V: Look<V>)
export type PatchVariants<P> = {
	button_variant: Added<P, 'button', 'variant'>;
	button_size: Added<P, 'button', 'size'>;
	checkbox_variant: Added<P, 'checkbox', 'variant'>;
	checkbox_size: Added<P, 'checkbox', 'size'>;
	switch_variant: Added<P, 'switch', 'variant'>;
	switch_size: Added<P, 'switch', 'size'>;
};

// a control's variant or size: the names its look's V gives the axis
export type Axis<V, K extends string> = V extends {[k in K]: infer A} ? keyof A & string : string;
