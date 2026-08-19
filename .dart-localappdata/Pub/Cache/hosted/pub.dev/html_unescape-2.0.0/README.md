# html_unescape

[![Build Status](https://travis-ci.org/filiph/html_unescape.svg?branch=master)](https://travis-ci.org/filiph/html_unescape)

A Dart library for unescaping HTML-encoded strings.

Supports:

* Named Character References (`&nbsp;`)
  * 2099 of them
* Decimal Character References (`&#225;`)
* Hexadecimal Character References (`&#xE3;`)

The idea is that while you seldom need _encoding_ to such a level (most of the
time, all you need to escape is `<`, `>`, `/`, `&` and `"`), you do want to
make sure that you cover the whole spectrum when _decoding_ from HTML-escaped
strings.

Inspired by Java's [unbescape](https://www.unbescape.org/) library.

## Usage

A simple usage example:

```dart
import 'package:html_unescape/html_unescape.dart';

main() {
  var unescape = HtmlUnescape();
  var text = unescape.convert("&lt;strong&#62;This &quot;escaped&quot; string");
  print(text);
}
```

You can also use the converter to transform a stream. For example, the code
below will transform a POSIX `stdin` into an HTML-unencoded `stdout`.

```dart
await stdin
    .transform(Utf8Decoder())
    .transform(HtmlUnescape())
    .transform(Utf8Encoder())
    .pipe(stdout);
```

## Full versus small

If you're sure you will only encounter the most common escaped characters,
you can `import 'package:html_unescape/html_unescape_small.dart'` instead of
the full version. This will decrease code size and increase performance. The
only difference is in the size of the Named Character Reference dictionary.
The full set includes the likes of `&DownLeftRightVector;` or `&UpArrowBar;` 
while the small set only includes the first 255 charcodes.

## Issues

[Please use GitHub tracker](https://github.com/filiph/html_unescape/issues).
Don't hesitate to create 
[pull requests](https://github.com/filiph/html_unescape/pulls), too.
