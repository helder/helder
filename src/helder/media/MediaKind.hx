package helder.media;

enum abstract MediaKind(String) to String {
	var Video = "video";
	var Audio = "audio";
	// subtitles, timed metadata, chapters' text
	var Other = "other";
}
