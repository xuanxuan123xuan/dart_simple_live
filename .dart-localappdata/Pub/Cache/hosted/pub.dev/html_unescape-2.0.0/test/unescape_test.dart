// Copyright (c) 2018, Filip Hracek. All rights reserved. Use of this source
// code is governed by a BSD-style license that can be found in the LICENSE
// file.

import 'dart:async';
import 'dart:convert';

import 'package:html_unescape/html_unescape.dart' as lib_full;
import 'package:html_unescape/html_unescape_small.dart' as lib_small;
import 'package:html_unescape/src/base.dart' show HtmlUnescapeBase;
import 'package:test/test.dart';

void main() {
  group('Full', () {
    runTests(() => lib_full.HtmlUnescape());
  });
  group('Small', () {
    runTests(() => lib_small.HtmlUnescape());
  });

  test('converts in chunks', () async {
    var unescape = lib_full.HtmlUnescape();

    var stream = Stream.fromIterable(
        ['This is &quot;awesome&qu'.codeUnits, 'ot;.'.codeUnits]);
    expect(stream.transform(utf8.decoder).transform(unescape).first,
        completion('This is "awesome".'));
  });
}

void runTests(ConverterFactory converterFactory) {
  test('leaves empty string alone', () {
    final unescape = converterFactory();

    expect(unescape.convert(''), '');
  });

  group('unescapes named', () {
    final unescape = converterFactory();

    test('quotes', () {
      expect(unescape.convert('This is &quot;awesome&quot;.'),
          'This is "awesome".');
    });

    test('quotes next to beginning', () {
      expect(
          unescape.convert('&quot;awesome&quot; it is.'), '"awesome" it is.');
    });

    test('quotes next to end', () {
      expect(
          unescape.convert('This is &quot;awesome&quot;'), 'This is "awesome"');
    });

    test('complete &lt; instead of incomplete inner &lt', () {
      expect(
          unescape.convert('Look &lt;a&gt;here&lt/a&gt'), 'Look <a>here</a>');
    });

    test('but ignores non-existent', () {
      expect(unescape.convert('Look &lt;a&gt;here&lt/a&nonexistent;'),
          'Look <a>here</a&nonexistent;');
    });

    if (unescape is lib_full.HtmlUnescape) {
      test('&CounterClockwiseContourIntegral;', () {
        expect(
            unescape.convert('Hi &CounterClockwiseContourIntegral;'), 'Hi ∳');
      });
    }
  });

  group('unescapes decimal', () {
    final unescape = converterFactory();

    test('"<" and ">"', () {
      expect(unescape.convert('&#60;a&#62;'), '<a>');
    });
  });

  group('unescapes hexadecimal', () {
    final unescape = converterFactory();

    test('"<" and ">"', () {
      expect(unescape.convert('&#x3c;a&#x3E;'), '<a>');
    });
  });

  group('ignores invalid', () {
    final unescape = converterFactory();

    test('decimal', () {
      expect(unescape.convert('Hello &#123i;'), 'Hello &#123i;');
    });

    test('hexadecimal', () {
      expect(unescape.convert('Hello &#x3cw;'), 'Hello &#x3cw;');
    });

    test('decimal without semicolon', () {
      expect(unescape.convert('Hello &#345'), 'Hello &#345');
    });

    test('hexadecimal without semicolon', () {
      expect(unescape.convert('Hello &#x3cworld'), 'Hello &#x3cworld');
    });
  });
}

typedef ConverterFactory = HtmlUnescapeBase Function();
