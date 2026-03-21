import 'package:hive/hive.dart';

part 'playlist.g.dart';

@HiveType(typeId: 3)
class Playlist extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  String name;

  @HiveField(2)
  String? description;

  @HiveField(3)
  List<String> songIds;

  @HiveField(4)
  final DateTime createdAt;

  @HiveField(5)
  String? customThumbnailUrl;

  Playlist({
    required this.id,
    required this.name,
    this.description,
    required this.songIds,
    required this.createdAt,
    this.customThumbnailUrl,
  });

  int get songCount => songIds.length;
}
