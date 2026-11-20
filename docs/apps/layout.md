# Layout and style

Layout is CSS flexbox and grid, and style names are CSS's: `padding`, `background`, `radius`, `border-color`, `font-size`. If you know CSS, you know where things go. helder lays them out and draws them itself, so a layout is the same on every platform.

<Example id="signup"/>

Views are columns by default. `direction="row"` puts children side by side, `grow` shares the free space, and gaps space them out. Numbers are points.

```tsx
<view grow={1} padding={24} row-gap={14}>
  <text font-size={28} font-weight={700}>Inbox</text>
  <view direction="row" align-items="center" justify="space-between">
    <text>3 unread</text>
    <view:button padding="4 10" radius={6} border-width={1} border-color="#e4e4e7">
      Mark all read
    </view:button>
  </view>
</view>
```

For a whole app, a `StyleSheet` styles parts by slot and state (hover, focus, checked, a variant), so markup stays short:

```haxe
static final sheet:StyleSheet = {
  rules: [
    {slot: "button", style: {padding: [6, 12], radius: 6,
      background: Color.rgb(0x18181B), color: Color.rgb(0xFAFAFA)}},
    {slot: "button", when: ["hover"], style: {background: Color.rgb(0x3F3F46)}},
    {slot: "button", variant: "outline",
      style: {background: Color.rgb(0xFFFFFF), borderWidth: 1}}
  ]
};

<view:button slot="button" variant="outline" onPress={save}>Save</view:button>
```

## What else

- **Grid:** `display="grid"` with template columns and rows, areas, spans and auto placement.
- **Positioning:** absolute boxes, `z-index`, `order`, auto margins, `aspect-ratio`, and right-to-left layout with `dir="rtl"`.
- **Paint:** gradients, shadows, borders per side, rounded corners, opacity and transforms.
- **Motion:** transitions of any style, springs, and property tracks for lists and shared elements ([Motion](https://helder.build/examples/#motion)).
- **Themes:** light and dark, following the system.
- Layout is checked against Chromium's, case by case, in helder's tests.

<Reference to="ui"/>
