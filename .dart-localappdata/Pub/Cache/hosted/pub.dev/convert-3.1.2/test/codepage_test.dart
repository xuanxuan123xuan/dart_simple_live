// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';
import 'dart:core';
import 'dart:typed_data';

import 'package:convert/convert.dart';
import 'package:test/test.dart';

void main() {
  var bytes = Uint8List.fromList([for (var i = 0; i < 256; i++) i]);
  for (var cp in [
    latin2,
    latin3,
    latin4,
    latin5,
    latin6,
    latin7,
    latin8,
    latin9,
    latin10,
    latinCyrillic,
    latinGreek,
    latinHebrew,
    latinThai,
    latinArabic
  ]) {
    group('${cp.name} codepage', () {
      test('ascii compatible', () {
        for (var byte = 0x20; byte < 0x7f; byte++) {
          expect(cp[byte], byte);
        }
      });

      test('bidirectional mapping', () {
        // Maps both directions.
        for (var byte = 0; byte < 256; byte++) {
          var char = cp[byte];
          if (char != 0xFFFD) {
            var string = String.fromCharCode(char);
            expect(cp.encode(string), [byte]);
            expect(cp.decode([byte]), string);
          }
        }
      });

      test('decode invalid characters not allowed', () {
        expect(() => cp.decode([0xfffd]), throwsA(isA<FormatException>()));
      });

      test('decode invalid characters allowed', () {
        // Decode works like operator[].
        expect(cp.decode(bytes, allowInvalid: true),
            String.fromCharCodes([for (var i = 0; i < 256; i++) cp[i]]));
      });

      test('chunked conversion', () {
        late final String decodedString;
        final outputSink = StringConversionSink.withCallback(
            (accumulated) => decodedString = accumulated);
        final inputSink = cp.decoder.startChunkedConversion(outputSink);
        final expected = StringBuffer();

        for (var byte = 0; byte < 256; byte++) {
          var char = cp[byte];
          if (char != 0xFFFD) {
            inputSink.add([byte]);
            expected.writeCharCode(char);
          }
        }
        inputSink.close();
        expect(decodedString, expected.toString());
      });
    });
  }
  test('latin-2 roundtrip', () {
    // Data from http://www.columbia.edu/kermit/latin2.html
    var latin2text = '\xa0Ą˘Ł¤ĽŚ§¨ŠŞŤŹ\xadŽŻ°ą˛ł´ľśˇ¸šşťź˝žżŔÁÂĂÄĹĆÇČÉĘËĚÍÎĎĐŃŇ'
        'ÓÔŐÖ×ŘŮÚŰÜÝŢßŕáâăäĺćçčéęëěíîďđńňóôőö÷řůúűüýţ˙';
    expect(latin2.decode(latin2.encode(latin2text)), latin2text);
  });

  test('latin-3 roundtrip', () {
    // Data from http://www.columbia.edu/kermit/latin3.html
    var latin2text = '\xa0Ħ˘£¤\u{FFFD}Ĥ§¨İŞĞĴ\xad\u{FFFD}Ż°ħ²³´µĥ·¸ışğĵ½'
        '\u{FFFD}żÀÁÂ\u{FFFD}ÄĊĈÇÈÉÊËÌÍÎÏ\u{FFFD}ÑÒÓÔĠÖ×ĜÙÚÛÜŬŜßàáâ'
        '\u{FFFD}äċĉçèéêëìíîï\u{FFFD}ñòóôġö÷ĝùúûüŭŝ˙';
    var encoded = latin3.encode(latin2text, invalidCharacter: 0);
    var decoded = latin3.decode(encoded, allowInvalid: true);
    expect(decoded, latin2text);
  });

  group('Custom code page', () {
    late final cp = CodePage('custom', "ABCDEF${"\uFFFD" * 250}");

    test('simple encode', () {
      var result = cp.encode('BADCAFE');
      expect(result, [1, 0, 3, 2, 0, 5, 4]);
    });

    test('unencodable character', () {
      expect(() => cp.encode('GAD'), throwsFormatException);
    });

    test('unencodable character with invalidCharacter', () {
      expect(cp.encode('GAD', invalidCharacter: 0x3F), [0x3F, 0, 3]);
    });

    test('simple decode', () {
      expect(cp.decode([1, 0, 3, 2, 0, 5, 4]), 'BADCAFE');
    });

    test('undecodable byte', () {
      expect(() => cp.decode([6, 1, 255]), throwsFormatException);
    });

    test('undecodable byte with allowInvalid', () {
      expect(cp.decode([6, 1, 255], allowInvalid: true), '\u{FFFD}B\u{FFFD}');
    });

    test('chunked conversion', () {
      late final String decodedString;
      final outputSink = StringConversionSink.withCallback(
          (accumulated) => decodedString = accumulated);
      final inputSink = cp.decoder.startChunkedConversion(outputSink);

      inputSink
        ..add([1])
        ..add([0])
        ..add([3])
        ..close();
      expect(decodedString, 'BAD');
    });

    test('chunked conversion - byte conversion sink', () {
      late final String decodedString;
      final outputSink = StringConversionSink.withCallback(
          (accumulated) => decodedString = accumulated);
      final bytes = [1, 0, 3, 2, 0, 5, 4];

      final inputSink = cp.decoder.startChunkedConversion(outputSink);
      expect(inputSink, isA<ByteConversionSink>());

      (inputSink as ByteConversionSink)
        ..addSlice(bytes, 1, 3, false)
        ..addSlice(bytes, 4, 5, false)
        ..addSlice(bytes, 6, 6, true);

      expect(decodedString, 'ADA');
    });
  });
}
