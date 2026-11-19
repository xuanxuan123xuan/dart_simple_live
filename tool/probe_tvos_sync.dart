import 'dart:async';
import 'dart:convert';
import 'dart:io';

// Sends the same envelopes and HTTP requests as the Dart clients, using
// synthetic data only. Run against a receiver displaying its sync screen.
Future<void> main(List<String> args) async {
  if (args.length < 2 ||
      !['lan', 'remote'].contains(args.first) ||
      (args.first == 'remote' && args.length != 3)) {
    stderr.writeln('Usage: dart tool/probe_tvos_sync.dart lan http://TV:23234');
    stderr.writeln(
      '       dart tool/probe_tvos_sync.dart remote wss://SERVER/sync ROOM',
    );
    exitCode = 64;
    return;
  }
  final endpoint = Uri.parse(args[1]);
  if (args.first == 'lan') {
    await probeLAN(endpoint);
  } else {
    await probeRemote(endpoint, args[2]);
  }
}

final sampleHistory = {
  'id': 'douyu_17',
  'siteId': 'douyu',
  'roomId': '17',
  'userName': 'Dart sync probe',
  'updateTime': '2026-11-19 01:15:03.123456Z',
};

Map<String, int> chunk(int index) => {
  'chunkIndex': index,
  'chunkTotal': 2,
  'itemStart': index - 1,
  'itemEnd': index,
  'itemTotal': 2,
};

Future<void> probeLAN(Uri endpoint) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 4);
  final udp = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
  final udpReady = Completer<Map<String, dynamic>>();
  final subscription = udp.listen((event) {
    if (event != RawSocketEvent.read) return;
    final reply = udp.receive();
    if (reply == null) return;
    final data = jsonDecode(utf8.decode(reply.data));
    if (data is Map<String, dynamic> &&
        data['type'] == 'tv' &&
        !udpReady.isCompleted) {
      udpReady.complete(data);
    }
  });
  try {
    final addresses = await InternetAddress.lookup(
      endpoint.host,
      type: InternetAddressType.IPv4,
    );
    udp.send(
      utf8.encode(jsonEncode({'id': 'dart-probe', 'type': 'hello'})),
      addresses.first,
      23235,
    );
    await udpReady.future.timeout(const Duration(seconds: 5));
    print('UDP hello → TV discovery response');

    Future<Map<String, dynamic>> request(
      String path, {
      Object? data,
      Map<String, String>? query,
    }) async {
      final url = endpoint.resolve(path).replace(queryParameters: query);
      final request = await client.openUrl(data == null ? 'GET' : 'POST', url);
      if (data != null) {
        final body = utf8.encode(jsonEncode(data));
        request.headers.contentType = ContentType.json;
        request.contentLength = body.length;
        request.add(body);
      }
      final reply = await request.close().timeout(const Duration(seconds: 20));
      final value = await utf8.decoder.bind(reply).join();
      if (reply.statusCode != 200) throw StateError('HTTP ${reply.statusCode}');
      return jsonDecode(value) as Map<String, dynamic>;
    }

    final info = await request('/info');
    if (info['type'] != 'tv' || info['port'] != 23234)
      throw StateError('Unexpected device info');
    print('GET /info → TV on HTTP 23234');
    for (var index = 1; index <= 2; index++) {
      final response = await request(
        '/sync/blocked_word',
        data: ['dart-probe-$index'],
        query: {
          'overlay': '0',
          for (final entry in chunk(index).entries) entry.key: '${entry.value}',
        },
      );
      if (response['status'] != true) throw StateError('Chunk $index rejected');
      print('POST /sync/blocked_word chunk $index → ${response['message']}');
    }
    final profile = await request(
      '/sync/profile',
      data: {
        'schema': 'simple_live_profile',
        'schemaVersion': 4,
        'histories': [sampleHistory],
      },
    );
    if (profile['status'] != true) throw StateError('Profile rejected');
    print('POST /sync/profile → ${profile['message']}');
  } finally {
    await subscription.cancel();
    udp.close();
    client.close(force: true);
  }
}

Future<void> probeRemote(Uri endpoint, String room) async {
  final socket = await WebSocket.connect(
    endpoint.toString(),
  ).timeout(const Duration(seconds: 10));
  final frames = StreamIterator(socket);
  var requestId = 0;
  try {
    Future<void> request(
      String type,
      Map<String, Object?> payload,
      String success,
    ) async {
      final id = '${++requestId}';
      socket.add(
        jsonEncode({
          'type': type,
          'requestId': id,
          'roomId': room,
          'payload': payload,
        }),
      );
      while (await frames.moveNext().timeout(const Duration(seconds: 12))) {
        final frame =
            jsonDecode(frames.current as String) as Map<String, dynamic>;
        if (frame['requestId'] != id) continue;
        if (frame['type'] != success)
          throw StateError('Unexpected response to $type: ${frame['type']}');
        print('$type → $success');
        return;
      }
      throw StateError('Disconnected');
    }

    await request('joinRoom', {
      'app': 'Simple Live',
      'platform': 'macos',
      'version': '1.8.0',
    }, 'roomJoined');
    for (var index = 1; index <= 2; index++) {
      await request('sendHistory', {
        'overlay': false,
        'content': jsonEncode([
          {
            ...sampleHistory,
            'roomId': '${16 + index}',
            'id': 'douyu_${16 + index}',
          },
        ]),
        ...chunk(index),
      }, 'ack');
    }
  } finally {
    await frames.cancel();
    await socket.close();
  }
}
