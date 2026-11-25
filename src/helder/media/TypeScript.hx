package helder.media;

// helder.media for TypeScript programs (helder.typescript): <Video> in a
// window's markup (its node, VideoNode: play, pause, seek, step and its
// time, duration and playing signals), a Player for audio alone, the
// byte sources a file is read from.
@:typescript("helder/media")
@:typescript.classes(helder.media.Player, helder.media.ByteSource, helder.media.ui.VideoNode, helder.media.FileSource, helder.media.MemorySource)
@:typescript.functions(Video = helder.media.ui.MediaTags.Video)
@:build(helder.typescript.api.Manifest.build())
class TypeScript {}
