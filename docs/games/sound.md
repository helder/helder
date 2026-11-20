# Sound

Play effects and stream music on every platform through the system's own audio: CoreAudio, WASAPI, ALSA, AAudio, RemoteIO and WebAudio. Effects mix on a few voices, music streams from Ogg Vorbis and crossfades, and nothing is allocated on the audio thread.

<Example id="tone"/>

```haxe
var sfx = Sfx.open();
// a WAV or Ogg Vorbis file, decoded up front
var hit = sfx.add(Sound.decode(hitBytes).mono(Sfx.RATE));
sfx.play(hit, 0.8, 1.0, -0.3);            // gain, rate, pan
sfx.music(musicBytes, 1.5, 0.6, true);    // streamed, a 1.5 s fade, looped
```

For synthesis, open an output and fill its buffers yourself:

```haxe
var format = {sampleRate: 48000, channels: 2, frames: 512};
var out = Audio.open(format, (buffer, frames) -> {
  for (i in 0...frames) {
    var v = 0.25 * Math.sin(phase);
    buffer[i * 2] = v;
    buffer[i * 2 + 1] = v;
    phase += step;
  }
});
out.start();
```

## What else

- **Effects:** loops, live gain and pan, playback rate.
- **Music:** Ogg Vorbis decoded in helder's own code, streamed packet by packet, crossfaded between tracks.
- **Phones:** audio pauses and resumes with the app, follows headphones being unplugged, and respects calls and alarms.
- **Browsers** start audio after the first click or key press, so sounds start after one.
- **Coming:** 3D audio, buses and effects.

<Reference to="os"/>
