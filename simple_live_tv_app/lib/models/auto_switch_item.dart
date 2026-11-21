import 'package:hive/hive.dart';

part 'auto_switch_item.g.dart';

@HiveType(typeId: 3)
class AutoSwitchItem {
  AutoSwitchItem({
    required this.id,
    required this.siteId,
    required this.roomId,
    required this.userName,
    required this.face,
    this.roomCover = '',
    this.liveStatus = 0,
    this.statusCheckedAt,
    this.sortOrder = 0,
  });

  @HiveField(0)
  String id;
  @HiveField(1)
  String siteId;
  @HiveField(2)
  String roomId;
  @HiveField(3)
  String userName;
  @HiveField(4)
  String face;
  @HiveField(5)
  String roomCover;
  @HiveField(6)
  int liveStatus;
  @HiveField(7)
  DateTime? statusCheckedAt;
  @HiveField(8)
  int sortOrder;
}
