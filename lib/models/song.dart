import 'package:hive/hive.dart';

part 'song.g.dart';

@HiveType(typeId: 0)
class Song extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String title;

  @HiveField(2)
  final String artist;

  @HiveField(3)
  final String artistId;

  @HiveField(4)
  final String album;

  @HiveField(5)
  final String albumId;

  @HiveField(6)
  final String thumbnailUrl;

  @HiveField(7)
  final int durationSeconds;

  @HiveField(8)
  bool isLiked;

  @HiveField(9)
  String? cachedAudioPath;

  @HiveField(10)
  DateTime? cachedAt;

  @HiveField(11)
  String? streamUrl;

  @HiveField(12)
  DateTime? streamUrlExpiry;

  // Not persisted — populated from search results only.
  final String? playCount;

  Song({
    required this.id,
    required this.title,
    required this.artist,
    required this.artistId,
    required this.album,
    required this.albumId,
    required this.thumbnailUrl,
    required this.durationSeconds,
    this.isLiked = false,
    this.cachedAudioPath,
    this.cachedAt,
    this.streamUrl,
    this.streamUrlExpiry,
    this.playCount,
  });

  bool get isAvailableOffline => cachedAudioPath != null;

  bool get isStreamUrlValid =>
      streamUrl != null &&
      streamUrlExpiry != null &&
      streamUrlExpiry!.isAfter(DateTime.now());

  String get duration {
    final m = durationSeconds ~/ 60;
    final s = durationSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  Song copyWith({
    bool? isLiked,
    String? cachedAudioPath,
    DateTime? cachedAt,
    String? streamUrl,
    DateTime? streamUrlExpiry,
  }) {
    return Song(
      id: id,
      title: title,
      artist: artist,
      artistId: artistId,
      album: album,
      albumId: albumId,
      thumbnailUrl: thumbnailUrl,
      durationSeconds: durationSeconds,
      isLiked: isLiked ?? this.isLiked,
      cachedAudioPath: cachedAudioPath ?? this.cachedAudioPath,
      cachedAt: cachedAt ?? this.cachedAt,
      streamUrl: streamUrl ?? this.streamUrl,
      streamUrlExpiry: streamUrlExpiry ?? this.streamUrlExpiry,
      playCount: playCount,
    );
  }
}
