// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'song.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class SongAdapter extends TypeAdapter<Song> {
  @override
  final int typeId = 0;

  @override
  Song read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Song(
      id: fields[0] as String,
      title: fields[1] as String,
      artist: fields[2] as String,
      artistId: fields[3] as String,
      album: fields[4] as String,
      albumId: fields[5] as String,
      thumbnailUrl: fields[6] as String,
      durationSeconds: fields[7] as int,
      isLiked: fields[8] as bool,
      cachedAudioPath: fields[9] as String?,
      cachedAt: fields[10] as DateTime?,
      streamUrl: fields[11] as String?,
      streamUrlExpiry: fields[12] as DateTime?,
    );
  }

  @override
  void write(BinaryWriter writer, Song obj) {
    writer
      ..writeByte(13)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.title)
      ..writeByte(2)
      ..write(obj.artist)
      ..writeByte(3)
      ..write(obj.artistId)
      ..writeByte(4)
      ..write(obj.album)
      ..writeByte(5)
      ..write(obj.albumId)
      ..writeByte(6)
      ..write(obj.thumbnailUrl)
      ..writeByte(7)
      ..write(obj.durationSeconds)
      ..writeByte(8)
      ..write(obj.isLiked)
      ..writeByte(9)
      ..write(obj.cachedAudioPath)
      ..writeByte(10)
      ..write(obj.cachedAt)
      ..writeByte(11)
      ..write(obj.streamUrl)
      ..writeByte(12)
      ..write(obj.streamUrlExpiry);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SongAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
