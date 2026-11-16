# Rewind Regiment

*Lose the battle. Rewind. Change one thing.*

Plastic toy soldiers fight by themselves on a play tray. You watch. When it
goes wrong, drag the timeline (a graph of who was ahead) back to where it
turned, and give **one order**: send a squad somewhere, or set off a toy:
roll the marble, tip the dominoes, start the train, pop the
jack-in-the-box, push the block tower, fling the eraser off the ruler, spin
the top. Drag a squad to where it should go (or tap it, then tap where);
time slows to a quarter while one is chosen, and a dotted path and a flag
show where each squad was sent. The battle plays out anew from there.
Rewound all the way to the start, the squads can be put elsewhere again, as
before the battle (`Sim.replace`: not an order, the run after it kept as the
ghost). Played on from a moment rewound to, the orders after it are undone
(`Sim.resume`): the toys they set off are ready again, to use later or not.
Badges and tags push each other apart and are tied to what they name by a
line; a touch on one is that squad or toy. The run before your change
stays on the timeline as a dashed line, and the card at the end says how it
went before. A win with one order is three medals.

```sh
bun run helder examples/rewind-regiment                    # this machine
bun run helder examples/rewind-regiment --target web       # a page
bun run helder share examples/rewind-regiment              # helder.run, for a week
```

## Pieces

| File | What |
|---|---|
| `Sim.hx` | The battle, nothing drawn: helder.physics stepped at 60 Hz plus the soldiers' own state in arrays; a keyframe (`PhysicsWorld.snapshot` and the arrays) every 10 steps, so any step is a keyframe and at most 9 steps away; orders; the props; the timeline's graph and ghost. Deterministic: the same orders give the same battle. |
| `Levels.hx` | Seventeen levels in six rooms (Bedroom, Kitchen, Study, Playroom, Garden, Attic): squads (kind, rows × columns, where), props (blue's to use once each; red's fire by themselves, with a countdown shown), a hint. |
| `Solve.hx` | Checks the levels natively: each must be lost with no orders, then every single order (each squad and prop, at moments through the battle, to a grid of places) is played out and the wins counted. `none` prints the default outcomes only (all levels in two seconds); `quick` samples half the orders at four moments. |
| `Rooms.hx` | Where each battle is fought, only looks: a rug in the bedroom, a baking tray with parchment on a gingham tablecloth, a leather blotter on a desk, a foam puzzle mat, a sandbox in the grass, an old card table in the attic; each room's things strewn about it anew for every level (teddy, toy chest, books, blocks, crayons, marbles, cars, dice, mugs, fruit, notebooks, pencils, bricks, stacking rings, flower pots, buckets, cartons, a trunk), and beside each prop more of its kind (spare marbles, a domino box, loose blocks), so the toys you can use are among others. Merged into one mesh a material; textures drawn in code. |
| `Toys.hx` | The models, built in code: army men (grunt charging with a bayonet, kneeling rifleman, kneeling bazooka man) on their oval bases, a wind-up tin tank, a jeep, a helicopter and its rotor, a wind-up robot with glowing eyes, books, dominoes with pips, a tin locomotive and wagons on track, a jack-in-the-box with its clown on a spring, letter blocks, a ruler on a pencil with an eraser, a spinning top, swirl marbles. One plastic material, tinted per instance by side. |
| `Game.hx` | The scene: the tray (felt mat, painted rim, the room's floor drawn in code: planks or tiles), the units in one instanced draw per kind, the props, dust puffs, confetti, a camera fitted to the screen (from behind blue when tall, from the side when wide) that keeps the whole tray in view and jolts a little on blasts, a tilt-shift lens; touches, the paths shown for orders, and the timeline. |
| `RewindRegiment.hx` | The window and HUD in ui's markup, dressed as a toy box: the title (the first battle playing behind it) on an olive crate lid, the campaign (a crate a room, dog tags for the levels, medals), the briefing on kraft paper, the tug-of-war bar, squad badges and prop tags where they stand, the order paths and flags, the timeline graph (SVG), the stamped report at the end. Black Ops One and Oswald (OFL). |
| `Sounds.hx` | Every sound synthesised: clacks, pops, topples, booms, the marble's roll, domino tocks, the train's whistle, the jack's boing, the timeline's whir, a fanfare and a sag. |
| `TiltShift.hx` | Little Skies' lens. |

## The rules

- **Grunts** charge and stab. **Riflemen** stand and shoot foam pellets at range, and are the only ones who can hit helicopters. **Bazookas** lob rockets over the lines; they burst where they land. **Tin tanks** are slow, take a lot, and ram. **Jeeps** are fast and run soldiers over. **Helicopters** fly over the melee and drop bombs. Wind-up **robots** plod forward and swing at everyone around them.
- Each side's props hurt only the other side. The jack-in-the-box knocks over everyone near it, so its timing is the puzzle.
- When a side is gone, the last three quarters of a second play in slow motion.
- Dominoes stand along a winding row and trains run on winding track (`bend`, `wave`: each prop's path, `Prop.along`).
- A won battle replays its busiest moments (what fell, burst or was set off, weighted) slowly, close and letterboxed, before the card; a touch skips it.

## The levels, checked

`Solve.exe quick` (one in two single orders, at four moments) on the levels as they are now:

| # | Level | No orders | Single orders that win | By |
|---|---|---|---|---|
| 1 | First Skirmish | lost 0 v 9 | 8.8% | marble |
| 2 | Domino Alley | lost 1 v 3 (time) | 6.2% | marble, dominoes |
| 3 | Sharpshooters | lost 0 v 4 | 8.5% | marble, jack |
| 4 | Last Train Home | lost 0 v 5 | 13.8% | tower, train, squad C |
| 5 | Tin Giant | lost 0 v 11 | 5.4% | catapult, squads A and C |
| 6 | Air Raid | lost 0 v 21 | 6.2% | tower, marble, squad C |
| 7 | Jeep Rush | lost 0 v 5 | 7.6% | catapult, squad B, train, jack |
| 8 | Pincer | lost 0 v 14 | 3.0% | squads A and B, dominoes |
| 9 | Rolling Thunder | lost 0 v 6 | 5.7% | catapult, squads B and D |
| 10 | The Grand Melee | lost 2 v 4 (time) | 3.1% | top, marble, dominoes |
| 11 | Rocket Range | lost 0 v 4 | 9.9% | top, marble, catapult, squads |
| 12 | Spin Cycle | lost 0 v 3 | 12.3% | top, squads A and C |
| 13 | Tin Men | lost 0 v 8 | 5.4% | marble, squad C, dominoes |
| 14 | Garden Party | lost 0 v 3 | 5.6% | catapult, squad C |
| 15 | Lawn Wars | lost 0 v 4 | 6.3% | squads A, C and D, top, tower |
| 16 | Air and Iron | lost 0 v 3 | 16.5% | top, tower, catapult, squads |
| 17 | Final Offensive | lost 0 v 2 | 10.6% | squads A, B, C, top, marble |

A player picks moments and places more finely than this grid, so there are
more ways through than it counts. The battles are chaotic: a small change to
a level can flip its default outcome, so run `Solve.exe none` after every
change.

## For checking

`RR_LEVEL=n` opens level n, `RR_FIGHT=1` starts it, `RR_ORDER=who,x,z,seconds`
gives an order at the start (who: a squad's index, or 100 + a prop's), and
`RR_CLOSE=x,y,z,tx,ty,tz` holds the camera there. Combined with `helder run
--headless --snap`, these make any moment's frame.
