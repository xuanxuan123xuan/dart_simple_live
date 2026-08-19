import 'dart:io';

import 'package:brotli/brotli.dart';

void main() {
  final output = brotli.decodeToString(File('./brotli.br').readAsBytesSync());
  print(output);
}
