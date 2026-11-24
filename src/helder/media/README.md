# helder.media

Video and audio files read in Haxe, the same on every system: MP4 and
QuickTime, Matroska and WebM demuxed into tracks and packets from any byte
source, an index for exact seeking, and the clock a player keeps. Decoded
by the systems' own decoders, nothing bundled: Apple's VideoToolbox and
AudioToolbox now (`helder.media.apple`), helder's own Vorbis everywhere;
the roadmap's **Video** brings MediaCodec, Media Foundation, VAAPI and
WebCodecs. A `Player` plays a file, a `<Video>` shows it in helder.ui.

```haxe
var media = Media.open(new FileSource("clip.mp4"));   // a coroutine (helder.async)
for (t in media.tracks) trace(t.kind, t.codec, t.width, t.height, t.sampleRate, t.config);
var seeks = media.seek(12.5);         // every track: video from the keyframe before, frames to drop
var p;
while ((p = media.next()) != null)    // the file's order, each track's in decode order
  decode(p.track, media.read(p), p.pts, p.key);
```

```haxe
import helder.media.ui.MediaTags.*;
<Video src="clip.mp4" fit="cover" autoplay={true} loop={true} grow={1} ref={v -> video = v}/>
video.seek(12.5); video.step(1); video.time();   // exact seeks, frame steps, signals
```

## Byte sources

A `ByteSource` reads n bytes at an offset, awaited, and knows its size
(-1 while not known). The demuxers read a box or a cluster at a time,
never assume the whole file in memory, and skip what they do not need
(MP4's `mdat` unread at open).

| | |
| --- | --- |
| `FileSource(path)` | a local file, natively (and on wasm32-wasi where the runtime has files: node's WASI); offsets past 2 GiB |
| `MemorySource(bytes)` | bytes in memory |
| `WebSource.url(url)` | the browser: fetch with HTTP Range requests, a part at a time (its size from the first's `Content-Range`); a server that ignores Range sends the file once, kept as a Blob |
| `WebSource.blob(name)` | a Blob's slices: one the page gave (`browser.mjs`'s option `blobs`, `{name: Blob}`, or `host.blob(name, blob)` from the page or another module: a file picked or dropped) |
| `WebSource.opfs(path)` | a file of the origin's private file system |

`WebSource` is the browser's (`imports.mjs`, module `helder_media`, 3 KB).
helder.run's apps have no network: their URLs are their bundled assets,
their Blobs the user's files. A cross-origin URL needs CORS and Range in
`Access-Control-Allow-Headers`.

## Containers

`Media.open` tells them apart by the first bytes (EBML's magic, else an
MP4 box) and keeps the demuxer (`media.demuxer`: `Mp4`, `Matroska`).

**MP4 and QuickTime** (`Mp4`): the top-level boxes walked by their headers,
`moov` and every `moof` read whole at open. `stsd`'s sample entry
(QuickTime's sound descriptions 1 and 2, `wave`), `stts`, `ctts` (signed,
as ffmpeg reads both versions), `stss`, `stsc`, `stsz` or `stz2`, `stco`
or `co64` expanded to each sample's offset, size, DTS, PTS and keyframe
flag; fragments (`mvex`/`trex` defaults, `tfhd`, `tfdt`, `trun`'s flags,
base offsets of the moof or the data before); `sidx`'s references kept
(`Mp4.segments`). PCM is a chunk a packet. Edit lists: an empty edit
first delays the track, the first other one's media time is its start
(a frame before it has a pts below 0, its packets still decoded: AAC's
priming, a cut between keyframes); more edits are not followed. The track
matrix's turn is `rotation`.

**Matroska and WebM** (`Matroska`): the EBML header, then the Segment's
elements up to the first Cluster (SeekHead, Info: TimestampScale and
Duration, Tracks, Cues; those after the clusters through SeekHead).
Clusters are read when their packets are wanted, one at a time, from a
seek's Cue on, or from the first (no Cues: live WebM); packets read meet
up into runs, so nothing is read twice. SimpleBlock and BlockGroup (no
ReferenceBlock: a keyframe; BlockDuration), Xiph, EBML and fixed lacing
(each frame its own offset, and its time from DefaultDuration), clusters
and a Segment of unknown size (up to the next element of the Segment's,
or the next EBML header). Matroska stores presentation times only: dts is
pts. CodecDelay is taken off every pts, as ffmpeg does; it and
SeekPreRoll are the track's `delay` and `preroll` (Opus's pre-skip, the
audio to decode before a seek's target).

## Tracks and packets

`MediaTrack`: `kind` (video, audio, other), `codec` (h264, hevc, vp8, vp9,
av1, aac, mp3, opus, vorbis, flac, alac, pcm, other; `tag` the
container's name), `config` (what ffmpeg calls extradata and the decoders
take: avcC, hvcC, av1C or vpcC's body, AAC's AudioSpecificConfig, OpusHead
(MP4's dOps turned into it), FLAC's STREAMINFO or Matroska's CodecPrivate,
ALAC's box, Vorbis's three headers Xiph-laced), `timescale` (ticks a
second), `duration`, `width`, `height`, `rotation` (degrees clockwise to
show), `sampleRate`, `channels`, `bits` (PCM's).

`Packet`: its track, `offset` and `size` in the source (bytes by
`media.read(p)`), `dts`, `pts` and `duration` in the track's ticks,
`time`, `decodeTime` and `end` in seconds, `key`. A track's packets are
kept as columns (`Samples`), a Packet made as one is asked for.

**Exact seeking**: `media.seek(time)` gives each track a `Seek`: the frame
due at that time (the latest pts at or before it; its `time`), the
keyframe to decode from (`packet`: the latest keyframe before it in
decode order, with a pts not after it) and `drop`, the frames decoded
before it in presentation order (B-frames' and an edit's included), up to
the next keyframe; audio: the packet that holds the time. `next()` goes
on from there. Frame stepping: forward is decoding on, back is a seek to
just before the frame shown (`seek(shown - 1e-9)`), so neither needs the
system's player.

## The clock

`Playback`: where the media is (`time`), `play`, `pause`, `seek`,
`speed(rate)`. Once an audio output is attached (`audio(sampleRate,
latency)`, `Audio.open`'s) its master is the audio heard: the frames
the callback gave (`played(frames)`, on the audio thread: a sequence lock,
nothing allocated) less the output's `latency`, between callbacks on the
monotonic clock and never past what was given (a stalled output stalls
the pictures); without one, the monotonic clock. A play or seek starts
with the next frames the callback gives, the time held until they are
heard. The video side asks `due(times)`: which of its decoded frames
shows now; `wait(t)`: seconds until one is due.

## Decoding

`Decoders.video(track)` and `Decoders.audio(track)`: the system's decoder
of a track, null where there is none (`Decoders.available()`: video
decoders here). Packets go in in decode order; a `VideoFrame` comes out
(its time, size, matrix: 601, 709 or 2020, range, 8 or 10 bits, the
system's image held until `release()`), audio as interleaved 32-bit
floats, two channels (mono doubled, more: the first two), at the track's
rate.

**VideoToolbox** (`apple.VtDecoder`): H.264, HEVC, VP9 and AV1, the
hardware's decoder where `VTIsHardwareDecodeSupported`, else the system's
software one; VP9 and AV1 are the hardware's alone (VP9's from 128 pixels
across, Apple's M1 and later; AV1: M3 and later). The format description
is made from H.264's and HEVC's parameter sets (CoreMedia reads their
colours and range there, not from the atoms), VP9 and AV1 from their vpcC
and av1C (a WebM's VP9 a vpcC of its first keyframe's header). Frames come
as CVPixelBuffers on IOSurfaces Metal reads, NV12 or P010 in the stream's
own range: one format asked for (with none the hardware gives its
compressed ones, with a list it converts to the first). Decoding is
asynchronous; the output callback runs on VideoToolbox's threads, where
nothing may collect: it retains the buffer into a ring in native memory,
`take()` reads it on ours. Frames before an exact seek's target are
decoded without output (`kVTDecodeFrame_DoNotOutputFrame`). Every frame of
tests/media's files is ffmpeg's, plane for plane.

**AudioToolbox** (`apple.AtDecoder`): AAC, MP3, ALAC, FLAC and Opus
through an AudioConverter, the track's config its magic cookie (FLAC's
STREAMINFO's body, its depth a format flag; a packet's frames asked for a
call: its FLAC decoder gives nothing when asked for more). **Vorbis**
(`VorbisDecoder`): helder's own (`helder.os.audio.Vorbis`), its three
headers from Matroska's config, its packets fed one at a time (`feed`).

## Playing

`Player.open(source)`: the first video and audio tracks the system decodes,
decoded a little ahead of the clock (eight frames, half a second of
audio) by a task of the loop, the audio into an output of its own
(`helder.os.audio.Audio` at the decoder's rate: the system resamples)
through a ring of floats; that output is the clock (`Playback`), the
monotonic clock without audio. `update()` each frame gives the frame due
(frames reorder: one is due once three decoded after it have come).
`play`, `pause`, `seek(t, exact)` (exact: the frame due at t, decoded from
its keyframe; else the keyframe, sooner), `step(±1)` (on: the next frame
decoded; back: a seek to just before the one shown), `rate` (the output at
the rate times faster: higher, as tape), `volume`, `muted`, `loop`;
`onLoaded`, `onEnded`, `onError`. Audio after a seek starts 0.1 s before
(a lossy codec's first frames overlap the packet before theirs; Opus's
SeekPreRoll), decoded, not heard; it plays from the packet's time, a
packet that decodes to fewer frames than it lasts lost them at its start
(Apple's Opus decoder drops 120 of its first 960) and Matroska's first
packet, its times whole milliseconds, starts at CodecDelay; it ends at the
track's duration less CodecDelay. Paused, the output plays out what it
holds; playing again starts the clock where the ring is. Ended once heard:
the clock at the audio's last frame.

## Showing

`<Video>` (`ui.MediaTags`, `ui.VideoNode`): a helder.ui box showing a
player's frame as fit says (contain by default), sized as its picture,
upright, where the style gives none; src a path or a ByteSource; its
`time`, `duration` and `playing` signals, `onTime` each frame. While it
plays the animation clock ticks it. Two ways to show it:

- drawn by helder (`ui.VideoTexture`), the default: the frame's planes
  opened as textures (`Device.openShared` of the IOSurface's plane: no
  copy; kept while the decoder's pool reuses them), turned to RGB upright
  in a pass of their own (`ui.VideoShader`: the matrix of the frame's
  coefficients, range and depth; chroma sited left), then drawn as a
  `<Scene>`'s box is: in captures, headless frames and every compositor;
- `layer={true}`, in a window of system layers (helder.ui.draw.CaLayers),
  where the node is a plain rectangle (no radius) and the picture upright:
  the system's `AVSampleBufferDisplayLayer` in a `LayerSlot`
  (`ui.SampleLayer`), each frame enqueued as it falls due with its time
  (tagged with its matrix, BT.709's primaries and sRGB's transfer, as
  helder draws it), its control timebase at the player's clock, clipped
  and moved with its scrollers, under what is drawn over it; let go a
  second after the slot, once CaLayers took it out of the tree. Asked for,
  not the default: on CI's virtual Mac the window server showed its
  colours some 30 levels off helder's (the same pre-converted to BGRA by
  VideoToolbox), to be measured on hardware; a window's capture of
  helder's frame leaves it out, as it does native views.

Audio alone is a Player without a box. TypeScript: `helder/media`'s
`Video`, `VideoNode`, `Player`, `FileSource`, `MemorySource`.

## Limits

A box, element or cluster read whole is at most 256 MB; a track at most 50
million samples; malformed or cut input ends in a `MediaError`, never
another error, a hang, or an allocation of what a header claims. Not yet:
the other systems' decoders (the roadmap's next parts), Ogg's container
(Opus and Vorbis in .ogg or .opus files), HDR's transfers (PQ and HLG
shown as SDR), a rate that keeps the pitch, WebM's DiscardPadding (Opus's
end trimmed to the segment's duration), reading an MP4's fragments lazily
through `sidx` (all are read at open), Matroska's ContentEncodings
(header stripping, encryption) and MP4's encrypted entries (`encv`,
`enca`: their `tag` the original's, the codec other), open GOPs' leading
frames, an MP4 writer.

Tests: `src/helder/media/Media.test.hx` (the test lane, natively and as
wasm32-wasi): tests/media's files (`fixtures.sh`: ffmpeg's H.264 and AAC,
fragmented, a MOV with an edit list, HEVC, a rotated MP4, Opus, FLAC, ALAC
and MP3 in MP4, VP9 and AV1 in MP4 and WebM, VP9 and Opus in WebM, Vorbis
and PCM in Matroska laced by `lace.mjs`, a live WebM) against ffprobe's
reading (`expected.json`, `expect.mjs`): tracks, config bytes, every
packet's times, size, keyframe flag and bytes' CRC-32; exact seeks with
B-frames, an edit list, fragments, Cues, live, lacing; frame stepping back;
every file cut short and with bytes changed. `Playback.test.hx`: the clock
on synthetic audio callbacks. `bun run test audio-web`
(`tests/media/WebSourceTest.hx`, `browser.mjs`): WebSource in Chromium, a
server honouring Range (under half the MP4 sent to open it, seek and read
a frame), one ignoring it, a Blob, OPFS. macOS's system-images lane
(`tests/media/apple/MediaAppleTest.hx`, 1.5 s): every frame of tests/media's
videos and `tests/media/apple`'s (`fixtures.sh`: VP9 4:2:0, HEVC Main 10 in
BT.2020, full-range BT.709 H.264, a chirp in AAC, MP3, FLAC, ALAC, Opus and
Vorbis) through VideoToolbox: their count, each packet's time and planes'
CRC-32 as ffmpeg decodes them (`decoded.json`, `expect.mjs`); every audio
track's frames and samples against ffmpeg's (libopus's: ffmpeg 9's own
Opus decoder is off on these, and reads an MP4's pre-skip in the track's
timescale), trimmed as the player trims; four frames turned to RGB on Metal
against ffmpeg's where the picture is flat (within 2 levels); exact seeks
and steps landing on the frame by time and pixels; a clip played through
CoreAudio's file output: each frame once, within a frame of the clock, the
audio's 8000 frames there. The window lane's `VideoWindow.hx`: a `<Video>`
in a scroller under a popup both ways, seeked, played, paused, scrolled
(drawn: helder's frames read back, `quads.mp4`'s flat colours exact; the
system's layer: rendering, placed and moved with the scroller, cut by its
clip); where the window server's captures have pixels, the drawn colours
there checked and the layer's printed, the captures kept as PNGs (CI's
artifact `video-window-macos`). VideoToolbox's decoding of `quads.mp4`
made at crf 18 or less is not ffmpeg's (its right half's Cr 255, an M4 and
CI's virtual Mac alike): the fixture is crf 23's, and the decoding test
checks it.
