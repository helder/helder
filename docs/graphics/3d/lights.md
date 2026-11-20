# Lights and shadows

The sun, point lights, spot lights and a sky, with shadows that are sharp where they meet their casters and soft further away. Hundreds of lights stay cheap: each pixel is lit only by the lights that reach it. Light bouncing from the sky and the walls comes from environment maps and probes.

<Example id="scene-lights"/>

Lights attach to nodes and shine along them. Shadows are opted in, so a scene without them links none of their code.

```haxe
var sun = world.node("sun");
Light.attach(sun, Light.directional(new Vec3(1, 0.95, 0.85), 2.2));
sun.lookAt(new Vec3(0.35, -0.45, 0.82));     // it shines along its node's -z

var bulb = Light.pointLight(new Vec3(1, 0.3, 0.1), 3, 4);  // colour, power, range
var lamp = Light.attach(world.node("lamp"), bulb);
lamp.castShadows = true;

var shadows = new Shadows(device, 2048).soft(0.25, 16, 0.08);
var renderer = new Renderer(device).use(shadows);
```

## What else

- **Many lights:** clustered lighting for hundreds of point and spot lights ([Lights at night](https://helder.build/examples/#lights)).
- **Shadows:** cascades for the sun, point and spot shadows in one atlas, soft edges that widen with distance.
- **Sky and environment:** an HDR sky prefiltered by helder at load, image-based light and reflections.
- **Indirect light:** light probes, reflection probes, area lights and lightmaps.
- **Hemisphere and rim lights**, and a material's night side for a planet's city lights.

<Reference to="scene"/>
