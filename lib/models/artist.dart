import 'package:hive/hive.dart';

part 'artist.g.dart';

@HiveType(typeId: 2)
class Artist extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String name;

  @HiveField(2)
  final String thumbnailUrl;

  @HiveField(3)
  final String? description;

  @HiveField(4)
  bool isLiked;

  Artist({
    required this.id,
    required this.name,
    required this.thumbnailUrl,
    this.description,
    this.isLiked = false,
  });
}
