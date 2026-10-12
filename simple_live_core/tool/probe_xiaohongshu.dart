import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:simple_live_core/simple_live_core.dart';

/// Read-only live probe; prints no cookies, signatures or media URLs.
Future<void> main(List<String> args) async {
  if (args.length != 1 || XiaohongshuSite.normalizeRoomId(args.first) == null) {
    throw ArgumentError('Pass a numeric Xiaohongshu live room id');
  }
  final site = XiaohongshuSite();
  final room = await site.getRoomDetail(roomId: args.first);
  final qualities = await site.getPlayQualites(detail: room);
  final result = <String, dynamic>{
    'roomId': room.roomId,
    'status': room.resolvedLiveStatus.name,
    'titlePresent': room.title.isNotEmpty,
    'anchorPresent': room.userName.isNotEmpty,
    'coverPresent': room.cover.isNotEmpty,
    'viewerCount': room.online,
    'aspectRatio': XiaohongshuSite.resolveStreamAspectRatio(room.data),
    'qualities': qualities.map((quality) => quality.quality).toList(),
  };
  if (room.resolvedLiveStatus == LiveStatusState.live && qualities.isNotEmpty) {
    final urls = await site.getPlayUrls(detail: room, quality: qualities.first);
    result['lineCount'] = urls.urls.length;
    final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10)));
    for (final protocol in ['m3u8', 'flv']) {
      final candidates =
          urls.urls.where((url) => Uri.parse(url).path.endsWith('.$protocol'));
      if (candidates.isEmpty) continue;
      try {
        if (protocol == 'm3u8') {
          final response = await dio.get<String>(candidates.first,
              options: Options(
                  headers: urls.headers, responseType: ResponseType.plain));
          result['hls'] = {
            'http': response.statusCode,
            'playlist': response.data?.startsWith('#EXTM3U') == true
          };
        } else {
          final response = await dio.get<ResponseBody>(candidates.first,
              options: Options(
                  headers: {...?urls.headers, 'Range': 'bytes=0-15'},
                  responseType: ResponseType.stream));
          final prefix = <int>[];
          await for (final chunk in response.data!.stream) {
            prefix.addAll(chunk.take(3 - prefix.length));
            if (prefix.length >= 3) break;
          }
          result['flv'] = {
            'http': response.statusCode,
            'header': ascii.decode(prefix, allowInvalid: true) == 'FLV'
          };
        }
      } on DioException catch (error) {
        result[protocol] = {
          'http': error.response?.statusCode,
          'error': error.type.name
        };
      }
    }
    dio.close(force: true);
  }
  try {
    final page = await site.getInteractionPage(room.roomId, 0);
    result['unsignedInteraction'] = {'comments': page.comments.length};
  } on CoreError catch (error) {
    result['unsignedInteraction'] = {
      'http': error.statusCode,
      'kind': error.kind.name
    };
  }
  print(jsonEncode(result));
}
