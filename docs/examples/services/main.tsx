// title: Locale and settings
// summary: One amount, date and count formatted for four languages by the platform, and the device's settings as signals
// tags: typescript, ui, os, locale, docs
// demo: canvas 480x300
import { memo, signal } from "helder/view";
import { Surface, UiWindow } from "helder/ui";
import { Format, Plural, Settings } from "helder/os";

const tags = ["en-US", "de-DE", "fr-FR", "ja-JP"];
const picked = signal(0);
const locale = memo(() => tags[picked()]);
const when = new Date(2026, 10, 20, 18, 30);

function Row(props: { label: string; value: () => string }) {
  return <view direction="row" justify="space-between" padding="9 0" border-color="#e7e5ea" borders="0 0 1 0">
    <text color="#6b6670">{props.label}</text>
    <text font-weight={600}>{props.value()}</text>
  </view>;
}

function Tag(props: { index: number }) {
  const on = () => picked() === props.index;
  return <view:button grow={1} role="radio" checked={on()} focusable cursor="pointer" height={32} radius={7}
    align-items="center" justify="center" background={on() ? "#222127" : "#ecebef"} color={on() ? "#ffffff" : "#222127"}
    onPress={() => picked(props.index)}>{tags[props.index]}</view:button>;
}

UiWindow.run(
  <Surface title="Locale and settings" width={480} height={300}>
    <view grow={1} padding={22} row-gap={12} background="#faf9fb" color="#222127" font-size={14}>
      <view direction="row" column-gap={6} role="radiogroup" label="Language">
        {tags.map((_, k) => <Tag index={k} />)}
      </view>
      <view>
        <Row label="Amount" value={() => Format.number(1234.5, { currency: "EUR", locale: locale() })} />
        <Row label="Share" value={() => Format.number(0.42, { percent: true, locale: locale() })} />
        <Row label="Date" value={() => Format.date(when, { date: "long", time: "short", locale: locale() })} />
        <Row label="Plural of 1.5" value={() => Plural.category(locale(), 1.5)} />
      </view>
      <text font-size={12} color="#6b6670">
        {"This device: " + (Settings.dark() ? "dark" : "light") + (Settings.reducedMotion() ? ", reduced motion" : "") + ", text ×" + Settings.textScale()}
      </text>
    </view>
  </Surface>
);
