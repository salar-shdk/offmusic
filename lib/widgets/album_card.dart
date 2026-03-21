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
    // When width is the default (fixed), wrap in SizedBox.
    // When used in a GridView without explicit width, fill available space.
    Widget card = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AspectRatio(
          aspectRatio: 1,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: CachedNetworkImage(
              imageUrl: album.thumbnailUrl,
              fit: BoxFit.cover,
              errorWidget: (_, __, ___) => Container(
                color: Colors.white10,
                child: const Icon(Icons.album_rounded,
                    size: 48, color: Colors.white24),
              ),
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
    );

    return GestureDetector(
      onTap: onTap,
      child: SizedBox(width: width, child: card),
    );
  }
}
