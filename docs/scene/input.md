# Input

```haxe
var actions = new InputMap();
actions.bind("jump", Key(0x20)).bind("jump", Region(0.75, 0.5, 1, 1));   // Space, or the screen's lower right
actions.bind("moveX", KeyAxis(0xFF51, 0xFF53));                         // the arrows
App.run(frame, e -> actions.event(e));
// each simulation step:
actions.step();
if (actions.pressed("jump")) ...;
var x = actions.axis("moveX");
```

Actions are named once and bound to keys, pads and the screen; gameplay
reads the actions, not the devices. The walker's arrow keys, WASD, a
gamepad's stick and the screen's lower right corner are its actions:

<Example id="walker"/>

## On-screen controls

Fingers are actions too, through on-screen controls that are virtual
devices (Unity's on-screen controls): gameplay reads the same actions as
for keys and pads.

```haxe
final move = new VirtualStick({zone: Zone.rect(0, 0.4, 0.5, 1), radius: 60, deadZone: 0.1});   // floating: where the thumb lands
final fire = new VirtualButton({zone: Zone.circle(0.88, 0.8, 40)});                            // radius in points
actions.bind("moveX", Stick(move, 0)).bind("moveX", KeyAxis(0x61, 0x64)).bind("moveX", PadAxis(0, 1));
actions.bind("lookX", TouchDelta(0, Zone.rect(0.5, 0, 1, 1), 0.3)).bind("lookX", PadAxis(2, 1));
actions.bind("fire", Button(fire)).bind("fire", PadButton(7)).bind("grab", Touch(Zone.rect(0, 0, 0.5, 0.4)));
// in the ui, over the scene: the stick drawn where the thumb holds it
<Stick bind={move} left={24} bottom={24}/>
```

`step` reads `helder.os.Pointers` (no events needed): each finger's press
is taken by the first control whose zone it began in (sticks, buttons and
`Touch` zones, then `TouchDelta`'s look zones), if nobody had it: not a
press on a ui node (helder.ui's window marks those the ui's, so a touch
on a HUD button never reaches the game), and kept until it lifts or is
cancelled, wherever it goes (a finger sliding over a button from
elsewhere does not press it; a button's finger sliding off lets it go).
A cancel lets go too: the player stops. `TouchDelta` is the drag over
the step in points times its scale (a look, not clamped); a press and
its release within a step still count. Equal zones are one control.
Nothing is allocated per event or per step (`changed`'s closures and the
key sets' maps are gone). Tests: `src/helder/scene/input/TouchActions.test.hx`
(natively and as wasm32-wasi, the allocation included),
`tests/3d/InputTest.hx`, `<Stick>` drawn in `tests/3d-ui/SurfaceTest.hx`.
