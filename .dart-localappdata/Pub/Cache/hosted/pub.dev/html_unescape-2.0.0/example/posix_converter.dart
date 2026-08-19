// Copyright (c) 2018, Filip Hracek. All rights reserved. Use of this source
// code is governed by a BSD-style license that can be found in the LICENSE
// file.

import 'dart:convert';
import 'dart:io';

import 'package:html_unescape/html_unescape.dart';

Future<void> main() async {
  // Try something like
  //
  //    $ dart example/posix_converter.dart < some_file.html
  await stdin
      .transform(Utf8Decoder())
      .transform(HtmlUnescape())
      .transform(Utf8Encoder())
      .pipe(stdout);
}
