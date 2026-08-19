// Copyright (c) 2018, Filip Hracek. All rights reserved. Use of this source
// code is governed by a BSD-style license that can be found in the LICENSE
// file.

/// Unescapes HTML5-escaped strings. This version doesn't support all runes
/// to decrease code size and increase performance.
library html_unescape.small;

import 'src/base.dart';
import 'src/data/named_chars_basic.dart' as data;

/// A [Converter] that takes HTML5-escaped strings (like `&pm;42`)
/// and unescapes them into unicode strings (like `±42`).
///
/// This class has a dictionary of about 270 escape sequences — the ones
/// most often encountered in regular documents. Consider using the bigger
/// version from `package:html_unescape/html_unescape.dart` if you need
/// the converter to be as comprehensive as possible.
class HtmlUnescape extends HtmlUnescapeBase {
  @override
  final int maxKeyLength = data.maxKeyLength;

  @override
  final List<String> keys = data.keys;

  @override
  final List<String> values = data.values;
}
