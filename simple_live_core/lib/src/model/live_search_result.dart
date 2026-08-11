import 'package:simple_live_core/src/model/live_anchor_item.dart';
import 'package:simple_live_core/src/model/live_room_item.dart';

enum SearchContinuation { more, done, unknown }

enum SearchOrigin { native, fallback, derived }

enum SearchFieldSource { native, derived, unavailable }

class LiveSearchMetadata {
  final SearchContinuation continuation;
  final SearchOrigin origin;
  final Map<String, SearchFieldSource> fieldSources;

  const LiveSearchMetadata({
    required this.continuation,
    this.origin = SearchOrigin.native,
    this.fieldSources = const <String, SearchFieldSource>{},
  });

  const LiveSearchMetadata.fromHasMore(bool hasMore)
      : continuation =
            hasMore ? SearchContinuation.more : SearchContinuation.done,
        origin = SearchOrigin.native,
        fieldSources = const <String, SearchFieldSource>{};
}

class LiveSearchRoomResult {
  final List<LiveRoomItem> items;
  final LiveSearchMetadata metadata;

  LiveSearchRoomResult({
    bool? hasMore,
    required this.items,
    LiveSearchMetadata? metadata,
  }) : metadata = metadata ?? LiveSearchMetadata.fromHasMore(hasMore ?? false);

  bool get hasMore => metadata.continuation == SearchContinuation.more;
}

class LiveSearchAnchorResult {
  final List<LiveAnchorItem> items;
  final LiveSearchMetadata metadata;

  LiveSearchAnchorResult({
    bool? hasMore,
    required this.items,
    LiveSearchMetadata? metadata,
  }) : metadata = metadata ?? LiveSearchMetadata.fromHasMore(hasMore ?? false);

  bool get hasMore => metadata.continuation == SearchContinuation.more;
}
