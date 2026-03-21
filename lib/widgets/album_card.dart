import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/album.dart';

class AlbumCard extends StatelessWidget {
  final Album album;
  final VoidCallback onTap;
  final double width;

  const AlbumCard({
    super.key,
    required this.album,
    required this.onTap,
    this.width = 140,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: CachedNetworkImage(
                imageUrl: album.thumbnailUrl,
                width: width,
                height: width,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => Container(
                  width: width,
                  height: width,
                  color: Colors.white10,
                  child: const Icon(Icons.album_rounded,
                      size: 48, color: Colors.white24),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              album.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(
              album.artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}
