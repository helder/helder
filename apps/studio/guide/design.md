# Design

A design file (`*.helder`) is markup the studio draws itself, at once,
with nothing built: the fastest way to show the user a screen, a
comparison or the options of a question. Each `<Frame>` is a frame on the
canvas, titled with its name; a `<Group>` is a titled region of frames
side by side. Its markup is helder's views, as in TSX.

```helder file=sketches.helder
<Design>
	<Group title="Which start screen?" canvas:at="0 900">
		<Frame name="Dawn" width={240} height={420} background="#f6d6b8" align-items="center" justify="center" row-gap={10}>
			<text font-size={28} font-weight={700} color="#7a3b1d">Pond</text>
			<text font-size={13} color="#9a5a3a">Press space to cast</text>
		</Frame>
		<Frame name="Dusk" width={240} height={420} background="#2b3a55" align-items="center" justify="center" row-gap={10}>
			<text font-size={28} font-weight={700} color="#f2c65a">Pond</text>
			<text font-size={13} color="#e8e2d0">Press space to cast</text>
		</Frame>
	</Group>
	<Frame name="Settings" width={390} height={844} background="#f8fafc" padding={24} row-gap={12}>
		<text font-size={22} font-weight={700}>Settings</text>
		<view direction="row" justify="space-between" padding="12 0" border-width="0 0 1 0" border-color="#e4e4e7">
			<text>Sound</text>
			<text color="#71717a">On</text>
		</view>
	</Frame>
</Design>
```

- A frame's id is `<file>#<name>` (`sketches.helder#Dusk`): use it in
  `studio.ask` options (`frame`) and links (`studio:frame/sketches.helder#Dusk`).
- A group: `studio:group/sketches.helder#Which start screen?`. Groups don't nest.
- `canvas:at="x y"` places a frame or a group; without it, after the one before.
- Frames take any view markup: `<view>`, `<text>`, `<image src="assets/x.png"/>`.
- A design file is for showing; the app is code. Once the user picked,
  write the code and remove sketches that are done.
