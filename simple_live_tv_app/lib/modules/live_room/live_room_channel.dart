/// A room entry captured from the list that opened a TV live room.
///
/// The list is intentionally a snapshot.  Changing pages or refreshing a
/// source after navigation must not reorder the rooms while the user is
/// stepping through them with a remote.
class LiveRoomChannel {
  const LiveRoomChannel({
    required this.siteId,
    required this.roomId,
    this.douyinSecUserId,
    this.xiaohongshuHostId,
  });

  final String siteId;
  final String roomId;
  final String? douyinSecUserId;
  final String? xiaohongshuHostId;

  String get key => '${siteId}_$roomId';
}

enum LiveRoomChannelDirection { previous, next }

class LiveRoomChannelResolver {
  const LiveRoomChannelResolver._();

  static int? findCurrentIndex(
    List<LiveRoomChannel> channels, {
    required String siteId,
    required Iterable<String> roomIds,
  }) {
    final candidates = roomIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet();
    if (candidates.isEmpty) return null;
    for (var index = 0; index < channels.length; index++) {
      final channel = channels[index];
      if (channel.siteId == siteId &&
          candidates.contains(channel.roomId.trim())) {
        return index;
      }
    }
    return null;
  }

  static LiveRoomChannel? neighbor(
    List<LiveRoomChannel> channels, {
    required String siteId,
    required Iterable<String> roomIds,
    required LiveRoomChannelDirection direction,
  }) {
    if (channels.isEmpty) return null;
    final index = findCurrentIndex(
      channels,
      siteId: siteId,
      roomIds: roomIds,
    );
    if (index == null) return null;
    final offset =
        direction == LiveRoomChannelDirection.next ? 1 : -1;
    final targetIndex = (index + offset + channels.length) % channels.length;
    return channels[targetIndex];
  }
}
