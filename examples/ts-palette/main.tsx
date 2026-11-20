// title: Palette study
// summary: Pick a palette and see the swatches and their color values update together
// tags: typescript, ui, view, signals
// demo: canvas 480x288
import { memo, signal } from "helder/view";
import { Surface, UiWindow } from "helder/ui";

const palettes = [
  { name: "Dusk", paper: "#e8deff", color: "#8964d2", ink: "#302340" },
  { name: "Clay", paper: "#f9dccb", color: "#d98564", ink: "#512e30" },
  { name: "Tide", paper: "#d9eeee", color: "#4b9daa", ink: "#193e50" },
];

const selected = signal(0);
const palette = memo(() => palettes[selected()]);

function Choice(props: { name: string; index: number }) {
  const active = () => selected() === props.index;
  return <view:button grow={1} role="radio" checked={active()} focusable cursor="pointer"
    align-items="center" justify="center" height={38} radius={7}
    background={active() ? "#222127" : "#ebe9ed"}
    color={active() ? "#ffffff" : "#222127"} onPress={() => selected(props.index)}>
    {props.name}
  </view:button>;
}

function Swatch(props: { fill: () => string; ink: string; grow: number }) {
  return <view grow={props.grow} min-width={0} padding={10} justify="end"
    radius={9} background={props.fill()}>
    <text font-size={12} font-weight={700} color={props.ink}>{props.fill()}</text>
  </view>;
}

UiWindow.run(
  <Surface title="Palette study" width={480} height={288}>
    <view grow={1} padding={24} row-gap={17} background="#faf9fb" color="#222127">
      <view direction="row" align-items="center" justify="space-between" column-gap={8}>
        <text font-size={24} font-weight={700}>Palette study</text>
        <text font-size={14} color="#5d5664">{palette().name}</text>
      </view>
      <view direction="row" grow={1} column-gap={6}>
        <Swatch fill={() => palette().paper} ink="#222127" grow={2} />
        <Swatch fill={() => palette().color} ink="#141219" grow={1} />
        <Swatch fill={() => palette().ink} ink="#ffffff" grow={1} />
      </view>
      <view direction="row" column-gap={6} role="radiogroup" label="Palette">
        {palettes.map((item, index) => <Choice name={item.name} index={index} />)}
      </view>
    </view>
  </Surface>
);
