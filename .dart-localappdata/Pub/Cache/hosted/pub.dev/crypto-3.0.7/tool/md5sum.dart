// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:crypto/crypto.dart';

void main(List<String> args) {
  for (var arg in args) {
    var data = File(arg).readAsBytesSync();
    var stopwatch = Stopwatch()..start();
    var hash = md5.convert(data);
    stopwatch.stop();
    print('Hashed to ${hash.toString()} in '
        '${stopwatch.elapsedMilliseconds} ms');
  }
}
