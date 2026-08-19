// Copyright (c) 2018, Filip Hracek. All rights reserved. Use of this source
// code is governed by a BSD-style license that can be found in the LICENSE
// file.

/// Unescapes HTML5-escaped strings.
library html_unescape;

import 'src/base.dart';
import 'src/data/named_chars_all.dart' as data;

/// A [Converter] that takes HTML5-escaped strings (like `&pm;42`)
/// and unescapes them into unicode strings (like `±42`).
///
/// This class has a dictionary of more than 2000 escape sequences,
/// including virtually unused ones such as `&DoubleLongLeftRightArrow;`.
/// Consider using the smaller version from
/// `package:html_unescape/html_unescape_small.dart` if you don't need
/// the converter to be as comprehensive.
class HtmlUnescape extends HtmlUnescapeBase {
  @override
  final int maxKeyLength = data.maxKeyLength;

  @override
  final List<String> keys = data.keys;

  @override
  final List<String> values = data.values;
}
