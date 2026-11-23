# helder.media

Video and audio files read in Haxe, the same on every system: MP4 and
QuickTime, Matroska and WebM demuxed into tracks and packets from any byte
source, an index for exact seeking, and the clock a player keeps. No
decoding: the systems' decoders take the packets (the roadmap's **Video**:
VideoToolbox and AVFoundation, WebCodecs, MediaCodec, Media Foundation,
VAAPI), nothing bundled.

```haxe
var media = Media.open(new FileSource("clip.mp4"));   // a coroutine (helder.async)
for (t in media.tracks) trace(t.kind, t.codec, t.width, t.height, t.sampleRate, t.config);
var seeks = media.seek(12.5);         // every track: video from the keyframe before, frames to drop
var p;
while ((p = media.next()) != null)    // the file's order, each track's in decode order
  decode(p.track, media.read(p), p.pts, p.key);
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

Audio stays the systems' to decode, but helder has its own Vorbis
(`helder.os.audio.Vorbis`, for games): Vorbis in WebM may decode with it
later (its config is the three headers it reads); not wired here.

## Limits

A box, element or cluster read whole is at most 256 MB; a track at most 50
million samples; malformed or cut input ends in a `MediaError`, never
another error, a hang, or an allocation of what a header claims. Not yet:
reading an MP4's fragments lazily through `sidx` (all are read at open),
Matroska's ContentEncodings (header stripping, encryption) and MP4's
encrypted entries (`encv`, `enca`: their `tag` the original's, the codec
other), open GOPs' leading frames, an MP4 writer.

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
a frame), one ignoring it, a Blob, OPFS.
