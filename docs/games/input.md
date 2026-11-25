# Input and gamepads

Name your game's actions once and bind them to keys, gamepad buttons and sticks, and touch zones on the screen. Gameplay reads the actions, never the devices, so the same code plays with a keyboard, a controller or a thumb.

<Example id="walker"/>

```haxe
var actions = new InputMap();
actions.bind('jump', Key(0x20))                  // Space
  .bind('jump', PadButton(0))                     // A
  .bind('jump', Region(0.75, 0.5, 1, 1));         // the lower right
actions.bind('moveX', KeyAxis(0xFF51, 0xFF53))    // the arrows
  .bind('moveX', PadAxis(0, 1));                  // the left stick
App.run(frame, e -> actions.event(e));

// each simulation step:
actions.step();
if (actions.pressed('jump')) player.jump();
var x = actions.axis('moveX');
```

On phones, on-screen controls are devices too: a floating stick where the thumb lands, buttons, and drag zones for looking around.

```haxe
final move = new VirtualStick({zone: Zone.rect(0, 0.4, 0.5, 1), radius: 60});
actions.bind('moveX', Stick(move, 0));
<Stick bind={move} left={24} bottom={24}/>   // drawn where the thumb holds it
```

## What else

- **Gamepads:** up to four in the standard layout on every platform: macOS, Windows, Linux, iOS, Android and the browser.
- **Pointers:** mice, fingers and pens with pressure, capture and cancellation, in apps and games alike.
- **Keyboards:** physical keys and typed characters apart, keymaps and shortcuts in apps ([Text and input](../apps/text.md)).
- **Touch that knows the UI:** a finger on a HUD button never reaches the game.
- **Haptics** on phones.

<Reference to="scene,os"/>
