import 'package:hive/hive.dart';

part 'album.g.dart';

@HiveType(typeId: 1)
class Album extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String title;

  @HiveField(2)
  final String artist;

  @HiveField(3)
  final String artistId;

  @HiveField(4)
  final String thumbnailUrl;

  @HiveField(5)
  final int year;

  @HiveField(6)
  final List<String> songIds;

  @HiveField(7)
  bool isLiked;

  Album({
    required this.id,
    required this.title,
    required this.artist,
    required this.artistId,
    required this.thumbnailUrl,
    required this.year,
    required this.songIds,
    this.isLiked = false,
  });
}
