# Layout and style

Layout is CSS flexbox and grid, and style names are CSS's, in camel as React Native writes them: `padding`, `background`, `borderRadius`, `borderColor`, `fontSize`. If you know CSS, you know where things go. helder lays them out and draws them itself, so a layout is the same on every platform.

<Example id="signup"/>

Views are columns by default. `flexDirection="row"` puts children side by side, `flexGrow` shares the free space, and gaps space them out. Numbers are points.

```tsx
<view flexGrow={1} padding={24} rowGap={14}>
  <text fontSize={28} fontWeight={700}>Inbox</text>
  <view flexDirection='row' alignItems='center' justifyContent='space-between'>
    <text>3 unread</text>
    <button padding='4 10' borderRadius={6} borderWidth={1} borderColor='#e4e4e7'>
      Mark all read
    </button>
  </view>
</view>
```

For a whole app, a `StyleSheet` styles parts by slot and state (hover, focus, checked, a variant), so markup stays short:

```haxe
static final sheet:StyleSheet = {
  rules: [
    {slot: 'button', style: {padding: [6, 12], borderRadius: 6,
      background: Color.rgb(0x18181B), color: Color.rgb(0xFAFAFA)}},
    {slot: 'button', when: ['hover'], style: {background: Color.rgb(0x3F3F46)}},
    {slot: 'button', variant: 'outline',
      style: {background: Color.rgb(0xFFFFFF), borderWidth: 1}}
  ]
};

<button slot='button' variant='outline' onPress={save}>Save</button>
```

## Liquid Glass

`<glass>` is Apple's Liquid Glass: a surface that blurs and lenses what is behind it, its children on top. On iOS and macOS 26 it is the system's own glass, in place in helder's layers; everywhere else, and in screenshots, helder draws it with a shader tuned against the system's.

<Example id="glass"/>

```tsx
const search = <glass flexDirection='row' padding='0 18' height={44} alignItems='center' columnGap={8} interactive>
  <icon name='search'/><text>Search</text>
</glass>
const buttons = <view glassSpacing={12} flexDirection='row' columnGap={6}>
  <glass width={44} height={44}/><glass width={44} height={44}/>
</view>
```

It is a capsule unless given a `borderRadius`; `variant="clear"` is the clearer glass, `tint` a colour it leans to, and a view's `glassSpacing` merges the glass in it that comes near.

## What else

- **Grid:** `display="grid"` with template columns and rows, areas, spans and auto placement.
- **Positioning:** absolute boxes, `z-index`, `order`, auto margins, `aspect-ratio`, and right-to-left layout with `dir="rtl"`.
- **Paint:** gradients, shadows, borders per side, rounded corners, opacity and transforms.
- **Motion:** transitions of any style, springs, and property tracks for lists and shared elements ([Motion](https://helder.build/examples/#motion)).
- **Themes:** the window follows the system's appearance. Set a sheet on `ui.theme` or on a subtree's `node.theme`. Inline styles win over the sheet.
- **Custom nodes:** extend `Node`, implement `hasContent` and `paintContent`, and return the node from a Haxe component. Call `ui.requestFrame()` when its drawing data changes.
- **Images and icons:** use `<icon>` for Lucide icons by name, or `<image>` for an asset or SVG. A constant passed to `Svg.parse` is read at build time ([Assets](../ship/assets.md)).
- Layout is checked against Chromium's, case by case, in helder's tests.

<Reference to="ui"/>
