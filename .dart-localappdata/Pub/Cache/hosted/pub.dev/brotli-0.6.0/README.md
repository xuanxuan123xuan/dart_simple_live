# Brotli

![Pub Version](https://img.shields.io/pub/v/brotli?style=flat-square)
[![CI](https://github.com/tiagohm/brotli/actions/workflows/ci.yml/badge.svg)](https://github.com/tiagohm/brotli/actions/workflows/ci.yml)

Pure Dart Brotli decoder.

## Installation

In `pubspec.yaml` add the following dependency:

```yaml
dependencies:
  brotli: ^0.6.0
```

## Example

```dart
import 'dart:io';

import 'package:brotli/brotli.dart';

void main() {
  final output = brotli.decodeToString(File("./brotli.br").readAsBytesSync());
  print(output);
}
```
