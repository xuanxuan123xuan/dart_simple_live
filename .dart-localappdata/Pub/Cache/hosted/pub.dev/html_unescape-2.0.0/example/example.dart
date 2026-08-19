// Copyright (c) 2018, Filip Hracek. All rights reserved. Use of this source
// code is governed by a BSD-style license that can be found in the LICENSE
// file.

import 'package:html_unescape/html_unescape.dart';

void main() {
  var unescape = HtmlUnescape();
  print(unescape.convert('&lt;strong&#62;This &quot;escaped&quot; string '
      'will be printed normally.</strong>'));
}
