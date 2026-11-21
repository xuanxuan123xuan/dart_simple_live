// GENERATED CODE - manually kept in sync with AutoSwitchItem.

part of 'auto_switch_item.dart';

class AutoSwitchItemAdapter extends TypeAdapter<AutoSwitchItem> {
  @override
  final int typeId = 3;

  @override
  AutoSwitchItem read(BinaryReader reader) {
    final fields = <int, dynamic>{
      for (var i = 0, count = reader.readByte(); i < count; i++)
        reader.readByte(): reader.read(),
    };
    return AutoSwitchItem(
      id: fields[0] as String,
      siteId: fields[1] as String,
      roomId: fields[2] as String,
      userName: fields[3] as String,
      face: fields[4] as String,
      roomCover: fields[5] as String? ?? '',
      liveStatus: fields[6] as int? ?? 0,
      statusCheckedAt: fields[7] as DateTime?,
      sortOrder: fields[8] as int? ?? 0,
    );
  }

  @override
  void write(BinaryWriter writer, AutoSwitchItem obj) {
    writer
      ..writeByte(9)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.siteId)
      ..writeByte(2)
      ..write(obj.roomId)
      ..writeByte(3)
      ..write(obj.userName)
      ..writeByte(4)
      ..write(obj.face)
      ..writeByte(5)
      ..write(obj.roomCover)
      ..writeByte(6)
      ..write(obj.liveStatus)
      ..writeByte(7)
      ..write(obj.statusCheckedAt)
      ..writeByte(8)
      ..write(obj.sortOrder);
  }
}
