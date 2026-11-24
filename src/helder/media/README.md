# helder.media

Video and audio files read in Haxe, the same on every system: MP4 and
QuickTime, Matroska and WebM demuxed into tracks and packets from any byte
source, an index for exact seeking, and the clock a player keeps. Decoded
by the systems' own decoders, nothing bundled: Apple's VideoToolbox and
AudioToolbox (`helder.media.apple`), the browser's WebCodecs
(`helder.media.web`), Android's MediaCodec (`helder.media.android`),
Windows' Media Foundation (`helder.media.windows`), helder's own Vorbis
where an app links it; the roadmap's **Video** brings VAAPI. A `Player`
plays a file, a `<Video>` shows it in helder.ui.

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
| `WebSource.url(url)` | the browser: fetch with HTTP Range requests, a part at a time (its size from the first's `Content-Range`); a server that ignores Range sends the file once, kept as a Blob; `WebSource.of(url)` at once, opened by its first read (`<Video src>`'s in a browser) |
| `WebSource.blob(name)` | a Blob's slices: one the page gave (`browser.mjs`'s option `blobs`, `{name: Blob}`, or `host.blob(name, blob)` from the page or another module: a file picked or dropped) |
| `WebSource.opfs(path)` | a file of the origin's private file system |

`WebSource` is the browser's (`imports.mjs`, module `helder_media`). A
request asks for 64 KB at least (`WebSource.block`), the last four reads of
up to a megabyte kept: a cluster read whole, then its packets, are one
request, not one a packet. helder.run's apps have no network: their URLs
are their bundled assets, their Blobs the user's files. A cross-origin URL
needs CORS and Range in `Access-Control-Allow-Headers`.

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
shows now (the first after a play or seek even when later ones are due
too: a frame decoded late shows, the rest catch up); `wait(t)`: seconds
until one is due.

## Decoding

`Decoders.video(track)` and `Decoders.audio(track)`: the system's decoder
of a track, null where there is none (`Decoders.available()`: video
decoders here; `Decoders.supported(track)`, awaited: the browser's
answer). Packets go in in decode order; a `VideoFrame` comes out (its
time, size, matrix: 601, 709 or 2020, range, 8 or 10 bits, the system's
image held until `release()`), audio as interleaved 32-bit floats, two
channels (mono doubled, more: the first two), at the track's rate; a
decoder that gives a packet's audio later says which packet it was
(`decoded`).

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

**WebCodecs** (`web.WebVideoDecoder`, `web.WebAudioDecoder`, the glue in
`imports.mjs`): a `VideoDecoder` or `AudioDecoder` of the page's,
configured with the track's codec string (`web.WebCodec`: avcC's, hvcC's,
vpcC's or a WebM's VP9 keyframe's, av1C's profile and level; AAC's object
type; mp3, opus, vorbis, flac, pcm-s16/24/32 and pcm-f32) and description
(the config; MP4's FLAC STREAMINFO made `fLaC` and its block), what plays
decided by `isConfigSupported` (else that track is not played; a clean
`MediaError` when nothing is). Packets go in as Encoded*Chunks timed in
microseconds, configured at the first (a keyframe). A frame stays the
page's `VideoFrame`, never in the module's memory: a handle (`pixels()`
empty: the browser test reads planes in its own glue); frames before
an exact seek's target are closed as they come, the others when the player
lets them go (a decoder's pool is small). Audio comes as `AudioData`,
copied as floats into the player's ring, in order, one for each packet
(Chromium times them anew from 0: a priming packet's at -1024 is given 0).
Colours a stream does not name (H.264's SPS, VP9's vpcC or keyframe, AV1's
sequence header) are configured as BT.601's, as ffmpeg and Apple read them
(a browser's guess is BT.709's). Decoders run in a worker too: nothing but
the `<video>` fallback needs a document.

**MediaCodec** (`android.McVideo`, `android.McAudio`, `android.McCodec`;
libmediandk loaded at run time): an `AMediaCodec` by MIME type, the
system's choice (a device's hardware decoder), else the software one it
ships (`c2.android.*`), in synchronous mode on the program's thread: no
callbacks, so no codec thread touches the heap. Packets wait in a queue
while it has no input buffer free; avcC's and hvcC's NAL lengths become
start codes as they are copied in (csd-0 and csd-1 their parameter sets,
av1C as csd-0; AAC's AudioSpecificConfig, OpusHead with its pre-skip and
preroll, FLAC's `fLaC` header). Video is decoded onto an `AImageReader`'s
surface (`AIMAGE_FORMAT_PRIVATE`, `GPU_SAMPLED_IMAGE`): each frame an
`AImage` on an `AHardwareBuffer`, one rendered to the reader at a time
(its queue keeps the last one queued), found by its time (microseconds);
its colours the dataspace the codec tagged (an H.264 with BT.709's matrix
but no primaries is BT.601's to Android). Audio comes as PCM, floats asked
for, 16 bits where a codec gives those; its outputs come later than their
packets (`decoded`), the end drained (`flush`, `pending`). H.264, HEVC,
VP9 and AV1; AAC, MP3, Opus and FLAC (no ALAC: Android has none).

**Media Foundation** (`windows.MfVideo`, `windows.MfAudio`,
`windows.MfTransform`; mfplat.dll loaded at run time: Windows' N editions
and Server without the feature have none): the system's decoder MFTs
(MFTEnumEx: synchronous, local, its ranking; Store extensions too: HEVC,
VP9, AV1 where installed), driven directly on the program's thread (no
callbacks; COM in the multithreaded apartment or the one it is in).
Packets go in as samples timed in 100 ns units; avcC's and hvcC's NAL
lengths become start codes and their parameter sets go before each
keyframe (av1C's OBUs before AV1's). With a hardware device of
helder.gfx's (`D3D11Backend.decoding`: made with video support) a
D3D11-aware decoder is given an `IMFDXGIDeviceManager` on it (DXVA; the
device's context made safe across threads), its frames NV12 or P010
textures in the decoder's array; else (WARP, `MfVideo.software`) it
decodes into samples of ours in memory, locked while a frame is held.
Colours as the output type names them, else BT.601's video range. Audio:
AAC (HEAACWAVEINFO's tail and the AudioSpecificConfig), MP3, FLAC
(STREAMINFO, forms tried in turn), ALAC (its cookie), Opus where the
system has a decoder, floats where it gives them, else 16 bits; outputs
by time (`decoded`), the end drained. Not Vorbis (helder's).

**AudioToolbox** (`apple.AtDecoder`): AAC, MP3, ALAC, FLAC and Opus
through an AudioConverter, the track's config its magic cookie (FLAC's
STREAMINFO's body, its depth a format flag; a packet's frames asked for a
call: its FLAC decoder gives nothing when asked for more). **Vorbis**
(`VorbisDecoder`): helder's own (`helder.os.audio.Vorbis`), its three
headers from Matroska's config, its packets fed one at a time (`feed`),
linked where an app asks: `VorbisDecoder.link()` before it plays (apps/
viewer does; 77 KB of examples/video on Windows x86-64, 50 KB on macOS
arm64). Without it a Vorbis track is not heard (`player.unheard`: the
track; a browser's WebCodecs decodes it where it can), the video plays
on the monotonic clock. Games' `Sfx` keeps its own.

## Playing

`Player.open(source)`: the first video and audio tracks the system decodes,
decoded a little ahead of the clock (eight frames, half a second of
audio) by a task of the loop, the audio into an output of its own
(`helder.os.audio.Audio` at the decoder's rate: the system resamples)
through a ring of floats; that output is the clock (`Playback`), the
monotonic clock without audio. `update()` each frame gives the frame due
(frames reorder: one is due once three decoded after it have come).
Until a seek's first frame has settled (the start's too) the clock is
held at the seek's time and the output given nothing, so a slow decoder
starts in time with the sound; frames late after it are skipped.
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
the clock at the audio's last frame, or the video's end where it is longer
(the output then plays silence, the clock going on; only then, so that a
clip's last samples are heard before it ends). At the stream's end the
decoders are drained (`flush`: AudioConverter's input over, WebCodecs'
flush, MediaCodec's end of stream; their last frames into the ring up to
the track's end). The ring holds two seconds and at least 65536 frames:
a decoder that gives its frames later is asked for them while a packet's
16384 fit (an 8 kHz track's two seconds would not). A decoder that holds
frames back (WebKit's, Firefox's) is fed on until one settles (at most 24);
a step waits for a flushed decoder's last frames. An audio decoder that
fails (WebKit's Opus, said to decode) is dropped, the video playing on the
monotonic clock. A seek asked for before it loaded is where it starts.

In a browser sound needs a gesture first (autoplay): until one, an
AudioContext gives nothing. Playing muted, the player then lets its
output go after 0.3 s and plays on the monotonic clock, opening it again
when unmuted (a muted video autoplays); with sound the clock waits at the
first frame until the gesture (helder.os's WebAudio resumes on the first
pointer or key). In a worker there is no AudioContext: the pictures play
on the monotonic clock.

Where WebCodecs does not decode the video (older Safari's audio, HEVC,
some of Firefox's), a `WebSource`'s file is played by the page's `<video>`
element (`web.WebElement`): the browser's decoding, sound and clock, its
frame (`requestVideoFrameCallback`'s) drawn as a decoder's is. Weaker: a
seek lands where the browser puts it, a step is a seek by a frame's
duration, nothing decoded ahead, muted until a gesture allows sound, and
the main thread only. A file the demuxers do not read (Ogg) is not tried.

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

In a browser (`VideoTexture`): the page's frame copied into an RGBA
texture on the GPU (Device.writeTextureImage: WebGPU's
`copyExternalImageToTexture`, WebGL2's `texImage2D`; the browser converts
its colours), then turned upright by the same pass (`VideoShader`'s
`turn.z`: RGB already). Later: WebGPU's `importExternalTexture`, no copy,
once the shaders have a binding type for external textures (its texture
lasts a task only: bound in the frame that samples it).

On Windows (`VideoTexture`): the planes opened by D3D11Backend.openShared
as the frame has them: a DXVA frame's NV12 or P010 texture (`d3d11:`,
its slice copied on the GPU out of the decoder's array into a texture of
the picture's size, each plane sampled by its view's format: r8 and rg8,
r16 and rg16), a software decoder's rows (`mem:`, uploaded as the
texture is made); each frame its own handle (the decoder's pool reuses
its textures and memory), the same pass as Apple's. `layer={true}`
(`ui.WinLayer`, in a window of DcLayers): a swap chain for composition
of the picture's size, the content of a visual in the node's slot
(`DcLayers.visualFor`), scaled and centred as fit says; each frame
presented as it falls due on the player's clock, so DWM shows it at its
next composition and helder draws nothing for it. The frame is turned to
RGB on the CPU as VideoShader turns it (a DXVA frame read back by Media
Foundation: the GPU's video processor would save that, later); until a
frame was presented the node draws them.

On Android (`VideoTexture`): the frame's `AHardwareBuffer` imported into
GLES as an EGLImage (`Device.openShared` of `ahb:`, GLBackend: an external
texture, no copy), kept while the reader's pool reuses it; the same pass
samples it (`samplerExternalOES`, the GLSL patched), the driver converting
its YUV as the buffer is tagged, the picture its crop's share of the
buffer (`turn.y`, `turn.w`). `layer={true}` (`ui.SurfaceLayer`, API 34):
MediaCodec renders straight onto the Surface of a SurfaceControl of its
own (Java's: the NDK has no Surface of an ASurfaceControl), its native
handle (`ASurfaceControl_fromJava`) under the node's slot (ScLayers),
scaled as fit says; each frame released to it as it falls due on the
player's clock (`releaseOutputBufferAtTime`). Until a frame was rendered
onto it the node draws them (`showing`), and one made while paused seeks
to where the player is, the frame due decoded again onto it. Where the
window's frames are not split onto layers (no scroller: ScLayers'
single), and until the layers showed a frame, it is drawn by helder. SurfaceFlinger converts the
frame as the codec tagged it: SMPTE 170M's transfer onto the sRGB display
(the emulator's grey 128 shows as 141), which MediaCodec sets on each
buffer, so it cannot be tagged sRGB's as Apple's are.

Audio alone is a Player without a box. TypeScript: `helder/media`'s
`Video`, `VideoNode`, `Player`, `FileSource`, `MemorySource`.

## Limits

A box, element or cluster read whole is at most 256 MB; a track at most 50
million samples; malformed or cut input ends in a `MediaError`, never
another error, a hang, or an allocation of what a header claims. Not yet:
Linux's decoders (the roadmap's next part), Ogg's container
(Opus and Vorbis in .ogg or .opus files), HDR's transfers (PQ and HLG
shown as SDR), a rate that keeps the pitch, WebM's DiscardPadding (Opus's
end trimmed to the segment's duration), reading an MP4's fragments lazily
through `sidx` (all are read at open), Matroska's ContentEncodings
(header stripping, encryption) and MP4's encrypted entries (`encv`,
`enca`: their `tag` the original's, the codec other), open GOPs' leading
frames, an MP4 writer. In browsers: HEVC where the system has no decoder
(Chromium's on Linux, Firefox), H.264 and AAC in Playwright's Linux
Chromium (no proprietary codecs), ALAC, HDR (PQ is the browser's mapping
to SDR), `importExternalTexture` (a copy on the GPU for now); Firefox's software decoders give RGB frames (BGRX, BT.709 for
unnamed colours), WebKit's are full range (its AV1's display width is
wrong). On Android: ALAC; 10-bit video on the emulator's software HEVC
decoder (its Codec2 configuration fails); the system's layer before API 34
(drawn there) and its colours as SurfaceFlinger converts them; the
emulator's host decoders (`c2.goldfish.*`, the system's choice there) make
full range video range.

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
artifact `video-window-macos`). Apple's decoding of `quads.mp4` made at
crf 18 or less is not ffmpeg's (its right half's Cr 255, not the source's;
an M4 and CI's virtual Mac alike; AVAssetReader, Apple's demuxer and
decoder without helder, gives the same bytes as helder): the fixture is
crf 23's, which every decoder decodes alike, and the decoding test checks
it. `bun run test audio-web` (`tests/media/web/MediaWebTest.hx`,
`browser.mjs`, about 9 s in Chromium): decoded.json's videos through
WebCodecs, every frame's time and planes' CRC-32 as ffmpeg's (where the
browser gives planes as decoded); the audio tracks' frames and samples;
frames in RGB on WebGPU and WebGL2 against ffmpeg's where flat
(decoded.json's and `rgb.json`'s VP9 and AV1, `expect.mjs`: within 8
levels, a mean under one; Chromium's exact); exact seeks and steps; a clip
played through the AudioWorklet (each frame once, within a frame of the
clock, ended, its audio's frames); a clip by URL (`long.webm`,
`fixtures.sh`: 4 s, a second a cluster) all by Range, less than the file
sent before its first frame showed, and sought before it loaded; a page
with no gesture (muted plays, with sound waits); the `<video>` fallback
played, sought, drawn. Firefox and WebKit too where Playwright has them
(CI: Chromium only), their own conversions printed, not failed;
`WebCodec.test.hx`: the codec strings and unnamed colours natively.

The android job (`tests/media/android/android.sh`, about 20 s on the
emulator): `MediaAndroidTest.hx`, decoded.json's videos through
MediaCodec read as YUV_420_888 (`McVideo.readable`): count, each frame's
time, planes' CRC-32 as ffmpeg's, where the system's decoder differs (the
emulator's goldfish ones) said and c2.android's checked; the audio tracks'
frames and samples (#93's tolerances); frames in RGB through the
AHardwareBuffer's EGLImage against ffmpeg's where flat (a mean under 1.5,
at most 8; where the system tags them otherwise than ffmpeg reads them,
said); exact seeks and steps; a clip played through AAudio (each frame
once, within a frame of the clock, its 8000 frames). Codecs the device
lacks are skipped with a line, H.264 and AAC never. `VideoStill.hx`: a
`<Video>` of `quads.mp4` in a scroller, drawn, on its system layer, and
with the layer asked for once paused (`late`, as a slow device's layers
start), played until six frames were shown, sought and paused, the frame
at 0.2 shown for ten frames; `still.mjs` reads the screencap's quadrants
against the source as the still was shown (said by VideoStill): drawn
within 8 levels (the emulator's 1), the layer within 16 (the emulator's 13).

On Windows (CI's desktop-windows job: no GPU, Media Foundation's
software decoders and WARP): the system-images lane's
`tests/media/windows/MediaWindowsTest.hx`, decoded.json's videos through
Media Foundation, count, each frame's time and planes' CRC-32 as
ffmpeg's; the audio tracks' frames and samples (#93's tolerances);
frames in RGB by helder's pass on Direct3D 11 and by WinLayer's
conversion against ffmpeg's where flat (a mean under 1 level, at most 8);
exact seeks and steps; a clip played (WASAPI's clock, the monotonic
clock where the machine has no output, said: CI's runner), each frame
once within a frame of it. HEVC, VP9 and AV1 (Store extensions), Opus
and what else the system lacks are skipped with a line, H.264 and AAC
never. The window lane's `WinVideoStill.hx`: a `<Video>` of `quads.mp4`
in a scroller, drawn and on its layer, played until six frames were
shown, sought and paused, the window's pixels (PrintWindow) read at the
quadrants' centres: within 8 levels of the source both ways. Limits on
Windows: hardware's decoder untested by CI (no GPU there), the
asynchronous hardware MFTs not used (Microsoft's synchronous ones use
DXVA), the layer's conversion on the CPU, ALAC and FLAC as the system's
decoders take their configs.
