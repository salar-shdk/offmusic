// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'album.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class AlbumAdapter extends TypeAdapter<Album> {
  @override
  final int typeId = 1;

  @override
  Album read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Album(
      id: fields[0] as String,
      title: fields[1] as String,
      artist: fields[2] as String,
      artistId: fields[3] as String,
      thumbnailUrl: fields[4] as String,
      year: fields[5] as int,
      songIds: (fields[6] as List).cast<String>(),
      isLiked: fields[7] as bool,
    );
  }

  @override
  void write(BinaryWriter writer, Album obj) {
    writer
      ..writeByte(8)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.title)
      ..writeByte(2)
      ..write(obj.artist)
      ..writeByte(3)
      ..write(obj.artistId)
      ..writeByte(4)
      ..write(obj.thumbnailUrl)
      ..writeByte(5)
      ..write(obj.year)
      ..writeByte(6)
      ..write(obj.songIds)
      ..writeByte(7)
      ..write(obj.isLiked);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AlbumAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
