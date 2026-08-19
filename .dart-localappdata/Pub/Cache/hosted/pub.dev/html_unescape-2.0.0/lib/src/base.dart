// Copyright (c) 2018, Filip Hracek. All rights reserved. Use of this source
// code is governed by a BSD-style license that can be found in the LICENSE
// file.
library html_unescape.base;

import 'dart:convert';
import 'dart:math';

// Character constants.
const int _hashCodeUnit = 35; // #
const int _minDecimalEscapeLength = 4; // x
const int _minHexadecimalEscapeLength = 5; // &#0;
const int _xCodeUnit = 120; // &#x0;

/// An abstract class that converts from HTML5-escaped strings
/// to unicode strings using [keys] and [values].
abstract class HtmlUnescapeBase extends Converter<String, String> {
  late int _chunkLength;

  /// Constructs a new converter.
  HtmlUnescapeBase() {
    _chunkLength = max(maxKeyLength, _minHexadecimalEscapeLength);
  }

  /// A list of keys (such as `&nbsp;`) recognized by this converter.
  List<String> get keys;

  /// The length of the longest key in [keys]. Used to optimize parsing.
  int get maxKeyLength;

  /// The list of values (such as `±`). This list has the same length as
  /// [keys], and strings in it correspond to the strings in [keys]
  /// at the same index.
  List<String> get values;

  /// Converts from HTML-escaped [data] to unescaped string.
  @override
  String convert(String data) {
    // Return early if possible.
    if (!data.contains('&')) return data;

    final buf = StringBuffer();
    var offset = 0;

    while (true) {
      final nextAmp = data.indexOf('&', offset);
      if (nextAmp == -1) {
        // Rest of string.
        buf.write(data.substring(offset));
        break;
      }
      buf.write(data.substring(offset, nextAmp));
      offset = nextAmp;

      var chunk =
          data.substring(offset, min(data.length, offset + _chunkLength));

      // Try &#123; and &#xff;
      if (chunk.length > _minDecimalEscapeLength &&
          chunk.codeUnitAt(1) == _hashCodeUnit) {
        final nextSemicolon = chunk.indexOf(';');
        if (nextSemicolon != -1) {
          var hex = chunk.codeUnitAt(2) == _xCodeUnit;
          var str = chunk.substring(hex ? 3 : 2, nextSemicolon);
          final ord = int.tryParse(str, radix: hex ? 16 : 10) ?? -1;
          if (ord != -1) {
            buf.write(String.fromCharCode(ord));
            offset += nextSemicolon + 1;
            continue;
          }
        }
      }

      // Try &nbsp;
      var replaced = false;
      for (var i = 0; i < keys.length; i++) {
        var key = keys[i];
        if (chunk.startsWith(key)) {
          var replacement = values[i];
          buf.write(replacement);
          offset += key.length;
          replaced = true;
          break;
        }
      }
      if (!replaced) {
        buf.write('&');
        offset += 1;
      }
    }

    return buf.toString();
  }

  @override
  StringConversionSink startChunkedConversion(Sink<String> sink) {
    if (sink is! StringConversionSink) {
      sink = StringConversionSink.from(sink);
    }
    return _HtmlUnescapeSink(sink, this);
  }
}

class _HtmlUnescapeSink extends StringConversionSinkBase {
  final StringConversionSink _sink;
  final HtmlUnescapeBase _unescape;

  /// The carry-over from the previous chunk.
  ///
  /// If the previous slice ended with ampersand too close to end,
  /// then the next slice may continue the reference.
  String? _carry;

  _HtmlUnescapeSink(this._sink, this._unescape);

  @override
  void addSlice(String chunk, int start, int end, bool isLast) {
    end = RangeError.checkValidRange(start, end, chunk.length);
    // If the chunk is empty, it's probably because it's the last one.
    // Handle that here, so we know the range is non-empty below.
    if (start >= end) {
      if (isLast) close();
      return;
    }
    if (_carry != null) {
      chunk = _carry! + chunk.substring(start, end);
      start = 0;
      end = chunk.length;
      _carry = null;
    }
    _convert(chunk, start, end, isLast);
    if (isLast) close();
  }

  @override
  void close() {
    if (_carry != null) {
      _sink.add(_unescape.convert(_carry!));
      _carry = null;
    }
    _sink.close();
  }

  void _convert(String chunk, int start, int end, bool isLast) {
    var nextAmp = chunk.indexOf('&', start);
    if (nextAmp == -1 || nextAmp > end) {
      _sink.add(chunk.substring(start, end));
      _carry = null;
      return;
    }

    while (nextAmp + _unescape.maxKeyLength <= end) {
      var lastAmp = chunk.lastIndexOf('&', end);
      final subEnd = lastAmp != -1 ? lastAmp : nextAmp + _unescape.maxKeyLength;
      var result = _unescape.convert(chunk.substring(start, subEnd));
      _sink.add(result);
      start = subEnd;
      nextAmp = chunk.indexOf('&', start);
      if (nextAmp == -1 || nextAmp > end) {
        _sink.add(chunk.substring(start, end));
        _carry = null;
        return;
      }
    }

    if (nextAmp + _unescape.maxKeyLength > end && isLast) {
      var result = _unescape.convert(chunk.substring(start, end));
      _sink.add(result);
      _carry = null;
      return;
    }

    var nextCarry = chunk.substring(start, end);
    if (_carry == null) {
      _carry = nextCarry;
    } else {
      _carry = _carry! + nextCarry;
    }
  }
}
