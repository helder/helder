# Assets

Images, fonts, models, sounds and data files are referenced by path, anywhere in your project. The path is checked when you build, the file is bundled only if your app still uses it, it loads the same way on every platform, and under `helder dev` it reloads in place when you save it.

<Example id="gltf-viewer"/>

```ts
import {bytes, loaded} from 'helder/asset'
import icon from './icon.png' with {type: 'image'}

const level = await loaded(bytes('levels/one.bin'))
```

```haxe
import helder.asset.Asset;

// in a coroutine: suspends until loaded
var ship = Asset.model('models/ship.glb').load();

// in the frame loop, without waiting
var icon = Asset.image('ui/icons/sword.png');
if (icon.ready) draw(icon.peek());
```

In markup, a view waits for what it reads inside a `<Loading>` boundary:

```haxe
<Loading fallback={<text>loading</text>}>
  <image src={Asset.image('ui/hero.png')}/>
</Loading>
```

## What else

- **Kinds:** images, fonts (added to the system's for the UI), glTF models with typed names, sounds, bytes, and localized strings.
- **Packed when you build:** models into a fast run-time format, textures compressed for the GPU.
- **Groups:** several assets loaded together behind a loading screen.
- **On the web:** files fetched beside the module, the first ones before your program starts.
- **Small files** can be embedded in the code itself.

<Reference to="asset"/>
