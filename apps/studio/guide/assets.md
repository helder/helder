# Assets

Files of the project by path (`helder/asset`): found beside the program's
file or under the project, checked when it builds, bundled with it.

```tsx file=badge.tsx
import { image, font } from "helder/asset";

const logo = image("assets/logo.png");
// (a font's faces are added once it loads: name its family in font-family)
font("assets/Title.ttf");

export function Badge() {
	return <view direction="row" align-items="center" column-gap={10} padding={12}>
		<image src={logo} width={48} height={48}/>
		<text font-family="Hanken Grotesk" font-size={20}>Pond</text>
	</view>;
}
```

```ts file=sound.ts
import { Player, FileSource } from "helder/media";

// a sound file (WAV, MP3, AAC, Ogg) played: from the project's folder
export function playHit() {
	const p = Player.open(new FileSource("assets/hit.wav"));
	p.onLoaded = () => p.play();
	p.onEnded = () => p.close();
}
```

- Images: PNG, JPEG, GIF, WebP; `<image src={...} width height fit="contain"/>`.
- In a design file: `<image src="assets/logo.png" width={48} height={48}/>`
  (a path from the design file's folder).
- Make an asset by writing it (`project.patch {path, text}` for SVG or
  text formats); binary files are the user's to add.
