import 'dart:io';
import 'dart:convert';
import 'package:path/path.dart' as path;
import 'dart:async';

// TODO: use https://www.w3.org/TR/html51/entities.json instead?
Future<void> main() async {
  const url = 'https://raw.githubusercontent.com/unbescape/unbescape/master/'
      'src/main/java/org/unbescape/html/Html5EscapeSymbolsInitializer.java';
  print('Downloading unbescape source file at $url.');

  final client = HttpClient();
  var req = await client.getUrl(Uri.parse(url));
  var response = await req.close();
  client.close();
  final contents = await response
      .cast<List<int>>()
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .toList();
  var refLines =
      contents.where((line) => line.contains('html5References.addReference'));
  var map = <String, String>{};
  refLines.forEach((line) {
    var csv = line
        .replaceAll('html5References.addReference(', '')
        .replaceAll(');', '');
    var values = csv.split(', ');
    var key = values.last.substring(1, values.last.length - 1);
    var ord = int.parse(values.first);
    if (ord >= 119964) {
      // This is UTF-16 territory. Ignore that.
      return;
    }
    var str = String.fromCharCode(ord);
    map[key] = str;
  });

  await writeMapToFile(map, 'named_chars_all.dart');

  var smallerMap = Map<String, String>.from(map);
  for (var key in map.keys) {
    var ord = map[key]!.runes.first;
    if (ord > 255) {
      smallerMap.remove(key);
    }
  }
  await writeMapToFile(smallerMap, 'named_chars_basic.dart');

  print('Done');
}

Future writeMapToFile(Map<String, String> map, String filename) async {
  final jsonCodec = JsonEncoder.withIndent('  ');

  var keysList = map.keys.toList();
  keysList.sort((a, b) => b.length.compareTo(a.length));
  var keysListLiteral = jsonCodec.convert(keysList);

  var maxKeyLength = keysList.first.length;

  var valuesList =
      List<String?>.generate(keysList.length, (index) => map[keysList[index]]);
  var valuesListLiteral = jsonCodec.convert(valuesList);
  valuesListLiteral = valuesListLiteral.replaceAll(r'"$"', r'"\$"');

  var scriptDir = path.dirname(Platform.script.path);
  var outputPath = path.join(scriptDir, '../lib/src/data/$filename');
  print(outputPath);
  var output = File(outputPath);
  output = await output.create();
  var sink = output.openWrite();
  sink.writeln('// This is auto-generated from tool/generate_map.dart.');
  sink.writeln('library html_unescape.${filename.split('.').first};');

  sink.write('const List<String> keys = <String>');
  sink.write(keysListLiteral);
  sink.writeln(';');

  sink.writeln('const int maxKeyLength = $maxKeyLength;');

  sink.write('const List<String> values = <String>');
  sink.write(valuesListLiteral);
  sink.writeln(';');
  await sink.close();
}
