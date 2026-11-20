# Effects and post

Draw in HDR and finish the frame like a film: bloom, tone mapping and grading, ambient occlusion, depth of field, reflections, god rays and fog. Each effect is a field you set; an effect you never set is not linked into your app.

<Example id="scene-post"/>

```haxe
var post = new PostProcess(device);
post.bloom = 0.05;                     // what is bright blooms, no threshold
post.toneMap = Aces;                   // or AgX
post.ao = new Ssao({radius: 0.5, intensity: 1, samples: 8, halfRes: true});
post.dof = Dof.focus({distance: 6, aperture: 0.02});
post.taa = new Taa();
renderer.post = post;
renderer.fog = new Fog(new Vec3(0.05, 0.07, 0.12), 0.03);  // colour, density
```

In a `<Scene>`, effects are attributes and can be toggled with signals.

## What else

- **Antialiasing:** FXAA, SMAA or temporal (TAA).
- **Screen space:** reflections on polished floors, ambient occlusion, outlines around selected nodes.
- **Camera:** depth of field and tilt-shift, motion blur for the camera and each object.
- **Colour:** saturation, contrast, lift and gain, vignette, grain, and a LUT made from an image or from code.
- **Fog:** exponential, thinner with height, covering the sky and particles too.

<Reference to="scene"/>
