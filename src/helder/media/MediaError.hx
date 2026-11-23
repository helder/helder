package helder.media;

// A file helder.media cannot read: not MP4 or Matroska, cut short, or
// with values out of range. Every malformed input ends in one of these.
class MediaError extends haxe.Exception {}
