import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/artist.dart';

class ArtistCard extends StatelessWidget {
  final Artist artist;
  final VoidCallback onTap;
  final double size;

  const ArtistCard({
    super.key,
    required this.artist,
    required this.onTap,
    this.size = 100,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          ClipOval(
            child: CachedNetworkImage(
              imageUrl: artist.thumbnailUrl,
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorWidget: (_, __, ___) => Container(
                width: size,
                height: size,
                color: Colors.white10,
                child: const Icon(Icons.person_rounded,
                    size: 48, color: Colors.white24),
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: size + 20,
            child: Text(
              artist.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
        ],
      ),
    );
  }
}
