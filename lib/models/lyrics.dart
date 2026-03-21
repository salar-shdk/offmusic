class LyricLine {
  final Duration timestamp;
  final String text;

  const LyricLine({required this.timestamp, required this.text});
}

class Lyrics {
  final String songId;
  final List<LyricLine> lines;
  final bool isSynced;
  final String? plainText;

  const Lyrics({
    required this.songId,
    required this.lines,
    required this.isSynced,
    this.plainText,
  });

  bool get isEmpty => lines.isEmpty && (plainText == null || plainText!.isEmpty);

  int currentLineIndex(Duration position) {
    if (lines.isEmpty) return -1;
    int idx = 0;
    for (int i = 0; i < lines.length; i++) {
      if (lines[i].timestamp <= position) {
        idx = i;
      } else {
        break;
      }
    }
    return idx;
  }

  static Lyrics parseLrc(String songId, String lrc) {
    final lines = <LyricLine>[];
    final regex = RegExp(r'\[(\d+):(\d+)\.(\d+)\](.*)');
    for (final line in lrc.split('\n')) {
      final match = regex.firstMatch(line);
      if (match != null) {
        final minutes = int.parse(match.group(1)!);
        final seconds = int.parse(match.group(2)!);
        final centiseconds = int.parse(match.group(3)!.padRight(2, '0').substring(0, 2));
        final text = match.group(4)!.trim();
        if (text.isNotEmpty) {
          lines.add(LyricLine(
            timestamp: Duration(
              minutes: minutes,
              seconds: seconds,
              milliseconds: centiseconds * 10,
            ),
            text: text,
          ));
        }
      }
    }
    return Lyrics(
      songId: songId,
      lines: lines,
      isSynced: lines.isNotEmpty,
      plainText: lrc,
    );
  }
}
